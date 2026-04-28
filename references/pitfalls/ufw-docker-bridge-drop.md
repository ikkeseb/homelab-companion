# ufw drops Docker bridge-to-host traffic

A container can reach the public internet but cannot reach a service
on its own host's LAN IP. The packet originates from the Docker
bridge subnet, hits ufw's `default deny (incoming)` policy, and is
silently dropped — DROP without ICMP, so the failure looks like a
network problem, not a firewall one.

## Symptom

Container can curl `https://example.com` fine. Container cannot
connect to the host's LAN IP on a specific port — for example, an
SSH bastion the container is supposed to tunnel through, or a
service running directly on the host. The container sees a TCP
*timeout*, not a connection-refused. Other LAN clients reach the
host on the same port without trouble. Host logs are empty.

This pattern is most obvious with self-hosted CI runners polling a
Forgejo / Gitea instance on the host, or any container that needs
to reach a host-bound service that isn't published into Docker.

## Root cause

Docker creates a virtual bridge network for each compose stack
(typically `172.17.0.0/16`, `172.18.0.0/16`, `172.19.0.0/16`, etc.,
allocated automatically). When a container on that bridge sends a
packet to the host's LAN IP, the packet is routed up through the
bridge interface to the host's network stack. ufw evaluates the
packet against its rules. With `default deny (incoming)` and no
allow rule for the bridge subnet, the packet is dropped.

`ufw` (like raw `iptables` with `-j DROP`) sends nothing back. The
client side sees only "no response", which presents as a TCP
timeout. There's no ICMP unreachable to suggest "firewall". The
host's auth.log / syslog show nothing because the packet never
reached any service. Symptom looks like a network problem; data
layer is firewall.

### Diagnosis

Three commands resolve the question:

```bash
# Identify the source subnet from inside the container
docker exec <ctr> bash -c 'ip -4 -o addr show | grep -v lo'

# Confirm the host is unreachable on the relevant port
docker exec <ctr> bash -c "(timeout 5 bash -c '</dev/tcp/<host-lan-ip>/22') 2>&1 \
    && echo OPEN || echo BLOCKED"

# Check whether ufw has a rule covering that source subnet
sudo ufw status verbose
```

If the container's source IP is on a `172.x.x.x` subnet, the host
port answers from other LAN clients, and `ufw status verbose` shows
no allow rule for that subnet — this is the pitfall.

## Fix

Three options, ordered from least to most blast-radius. Pick by
container shape, not habit.

**A. `network_mode: host`** — when the container has no inbound
ports and is purely outbound (CI runners, polling agents, cron
jobs):

```yaml
services:
  ci-runner:
    network_mode: host
```

Container inherits the host's network namespace. `127.0.0.1` is the
host. Loopback is never filtered by ufw. No firewall changes
needed. Trade-off: container loses Docker's port isolation. Fine
for outbound-only workloads; not fine for services that need a
stable bridge identity.

**B. Allow the bridge subnet on the host port** — when the
container must stay on a bridge:

```bash
sudo ufw allow from 172.18.0.0/16 to any port 22 \
  comment "SSH from docker bridge"
```

Container stays on its bridge. Trade-off: any container on that
bridge can attempt the service — wider blast radius than A. Pin
the subnet (don't widen to `172.16.0.0/12`) and pin the port
(don't `to any`).

**C. `host.docker.internal` via `extra_hosts`** — convenience layer
on top of B, not a standalone fix:

```yaml
services:
  app:
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

Useful when application config needs a portable hostname rather
than a hardcoded LAN IP. Still requires the ufw allow rule from B
to actually carry traffic.

## Why LLMs miss this

The default reach for "container can't connect to host port" is
*"open the port"* — `sudo ufw allow 8080`. That's a rule by
**port**, not by **source**. The container's source address isn't
on the LAN; it's on the bridge subnet. An allow rule keyed by port
alone often already exists for that port from the LAN, which is
precisely why the symptom is confusing.

Models also reflexively volunteer *"Docker bypasses ufw"* as a
blanket truth. That's correct for **publish-to-host** traffic —
`-p 8080:8080` mappings short-circuit ufw because Docker injects
its own iptables rules ahead of ufw's chains. It is wrong for the
**bridge-to-host LAN-IP** path, which goes through the host's
normal routing stack and hits ufw with a non-LAN source. Both
behaviors live in the same product. Conflating them by saying
"ufw doesn't apply to Docker" sends the user looking for a Docker
config bug that doesn't exist.

The right move is to identify the source subnet **first** (via
`docker exec ... ip addr` or `docker network inspect`), then
choose a fix keyed by source. Models that skip the source-IP
inspection and jump to a port-based rule, or to the
"ufw-doesn't-apply" framing, will plausibly be wrong.

## See also

- [scene-RAR vs P2P imports](arr-stack-scene-imports.md) — another
  case where the surface diagnostic ("Sonarr says completed") hides
  a structural difference at a different layer.
- [network_mode netns orphan](network-mode-netns-orphan.md) — the
  related pitfall when a container's network namespace itself is
  the variable, not the firewall.
