# `network_mode` parent restart orphans the child's netns

When a child container is bound to a parent's network namespace
via `network_mode: container:<parent>` or `service:<parent>`, a
parent restart silently orphans the child's network. Both
containers stay "Up", port mappings remain intact, the parent's
healthcheck stays green — but the child becomes unreachable from
LAN. This is the canonical VPN-sidecar trap (gluetun + qBit,
wireguard + arr-stack).

## Symptom

`docker ps` shows both containers Up. The parent reports
`(healthy)`. `docker port <child>` shows the published port mapped
to the host. From outside, the child's service answers with
`Connection reset by peer` or a TCP timeout. From inside the
container, `curl` against the parent's gateway fails too.

Restarting just the parent (because "the parent is the one with
the VPN") does not fix it. Auto-remediation scripts that
restart-on-unhealthy fire correctly on the parent and leave the
child broken behind them.

## Root cause

`network_mode: container:<id>` (or the compose-shorthand
`service:<parent>`) binds the child's network namespace to the
parent's namespace at **child container start time**. Docker
records the parent's container ID in `HostConfig.NetworkMode` for
the child.

When the parent restarts, it gets a new namespace (a new
`SandboxID`). Docker does **not** re-wire the child to that new
namespace. The child process keeps running, bound to
`0.0.0.0:<port>` in its old namespace, which now has only `lo`.
No `eth0`. No `tun0`. No way out.

Worse: Docker's port-mapping bookkeeping is independent of the
child's actual netns state. `docker port <child>` still shows the
mapping. `iptables` rules for the published port are still in
place. The mapping just points into a namespace that has no
listener for inbound traffic anymore. The surface says "Up";
the data layer says "empty namespace".

### Diagnosis

```bash
# The smoking-gun primitive — empty SandboxID = orphaned
docker inspect <child> --format '{{.NetworkSettings.SandboxID}}'

# Inside the netns: only lo present = orphaned
docker exec <child> ip -4 addr | grep -E 'eth|tun|wg'

# Confirm the binding shape
docker inspect <child> --format '{{.HostConfig.NetworkMode}}'
docker inspect <parent> --format '{{.Id}}'
```

Empty `SandboxID` plus only `lo` in the namespace plus a parent
ID that doesn't match the child's `NetworkMode` reference
confirms the orphan.

## Fix

Restart the children **after** the parent reaches healthy. Order
matters:

```bash
docker restart <parent>
# wait for parent's healthcheck to pass
until docker inspect <parent> --format '{{.State.Health.Status}}' \
    | grep -q healthy; do sleep 2; done
docker restart <child1>
docker restart <child2>
```

Restarting the child synchronously re-attaches its namespace to
the parent's current netns. If the parent isn't healthy first,
the child comes up into another orphaned state and you're back
where you started.

For docker-compose: `docker compose restart <parent> <child1> <child2>`
in that argument order works the same way — compose stops/starts
in the order given.

**Auto-remediation script implication.** Any script that restarts
the parent on unhealthy must also restart the children, in order.
A "restart unhealthy parent" loop without child restart is a
silent failure machine — it satisfies its own success metric
("parent healthy again") while the actually-important service
stays down. Pair this with an external monitor against the
**child's** service URL, not the parent's healthcheck.

## Why LLMs miss this

The default response is *"restart the child"* — and that works
in the moment. The miss is at the next level up: the model rarely
volunteers that **anything restarting the parent** must also
restart the child, and rarely names this as a generalizable trap
across all VPN-sidecar patterns (gluetun, wireguard, openvpn) and
shared-network-stack patterns (Tor, jump-host sidecars).

The diagnostic primitives — `SandboxID`, `ip addr` inside the
namespace, `NetworkMode` cross-reference — are weak in model
training compared to surface commands like `docker logs`,
`docker ps`, `curl` from outside. Models will troubleshoot for
hours by reading container logs and tweaking compose files
because the surface tools they reach for first cannot
distinguish "child is fine" from "child is in an empty
namespace". `docker ps` lies in the same way `iptables -L` lies
when the rule is correct but the source IP is unanticipated
(see [ufw-docker bridge drop](ufw-docker-bridge-drop.md)).

A useful prompt to deflect the surface miss: *"the parent is
healthy and port mapping is intact, but the child is unreachable
— inspect SandboxID and the child's namespace interfaces before
touching compose."* That short instruction routes models to the
data-layer evidence directly.

## See also

- [ufw-docker bridge drop](ufw-docker-bridge-drop.md) — sibling
  pitfall in the surface-vs-data-layer cluster. There the surface
  is `iptables -L` showing rules; here it's `docker ps` showing
  Up.
- [mutative-vs-readonly diagnostics](mutative-vs-readonly-diagnostics.md)
  — when reasoning about how to confirm orphan state, prefer the
  read-only `inspect` primitives over actions like "restart and
  see".
