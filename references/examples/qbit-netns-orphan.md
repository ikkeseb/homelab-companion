---
title: qBittorrent unreachable after gluetun restart
service: qbittorrent
severity: P3
duration: ~2h (silent failure window) + 5m (fix once diagnosed)
machine: nas-01
created: 2026-04-23
---

# qBittorrent unreachable after gluetun restart

A qBittorrent container running behind a gluetun VPN sidecar
became unreachable from LAN about two hours after a routine
gluetun restart. The qBit web UI silently stopped responding
while every surface signal — `docker ps`, port mapping, parent
healthcheck — stayed green. This is the canonical "VPN sidecar
parent restart orphans the child's netns" failure mode; the
same shape applies to any compose stack using
`network_mode: service:<parent>`.

## What broke

The qBittorrent web UI returned `Connection reset by peer` from
outside:

```
$ curl -v http://10.0.0.218:8080/
*   Trying 10.0.0.218:8080...
* Connected to 10.0.0.218 (10.0.0.218) port 8080 (#0)
> GET / HTTP/1.1
> Host: 10.0.0.218:8080
> User-Agent: curl/7.88.1
> Accept: */*
>
* Recv failure: Connection reset by peer
* Closed connection 0
curl: (56) Recv failure: Connection reset by peer
```

`docker ps` showed both containers Up. gluetun reported
`(healthy)`. Port mapping was intact:

```
$ docker port qbittorrent
8080/tcp -> 0.0.0.0:8080
8080/tcp -> :::8080
```

Internal monitoring showed gluetun's healthcheck green
throughout. No alerts had fired. The failure was discovered
manually when a user noticed the web UI wasn't responding.

## Why

This is an instance of
[network_mode netns orphan](../pitfalls/network-mode-netns-orphan.md).

qBittorrent was configured with `network_mode: service:gluetun`
in compose. That binds the qBit container's network namespace
to gluetun's namespace **at child start time**. Docker records
the parent's container ID in the child's `HostConfig.NetworkMode`.

When gluetun was restarted at 18:41 (routine maintenance script
triggered by an unhealthy probe upstream), it got a new network
namespace. Docker did not re-wire qBittorrent to the new
namespace. The qBit process kept running, bound to
`0.0.0.0:8080`, in its original namespace — which now contained
only `lo`. No `eth0`. No `tun0`.

Docker's port mapping bookkeeping is independent of the child's
namespace state. `docker port qbittorrent` continued showing
the mapping. The host's iptables DNAT for port 8080 still
pointed at the now-empty namespace.

### What conditions had to hold

- qBittorrent had to be running with
  `network_mode: service:<parent>` (or `container:<id>`) — any
  shared-network-stack pattern. The same applies to wireguard
  + arr-stack and similar VPN-sidecar compositions.
- The parent had to restart while the child kept running. Bare
  `docker compose restart gluetun` triggers it. So does the
  unhealthy auto-recovery script.

The bug fires every time a parent restarts without restarting
its children. Not intermittent — deterministic.

### Diagnostic walk

```bash
$ docker inspect qbittorrent \
    --format '{{.NetworkSettings.SandboxID}}'

```

Empty output. Healthy containers populate `SandboxID`; the empty
result was the first concrete signal.

```bash
$ docker exec qbittorrent ip -4 addr | grep -E 'eth|tun|wg'

$ docker exec qbittorrent ip -4 addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 ...
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
```

Only `lo`. The namespace had no path to anywhere except itself.
Cross-checking the binding shape confirmed the orphan:

```bash
$ docker inspect qbittorrent \
    --format '{{.HostConfig.NetworkMode}}'
container:f4a2e81b...

$ docker inspect gluetun --format '{{.Id}}'
9c3d712e...    # different ID — parent has been restarted
```

qBit's `NetworkMode` referenced a container ID that no longer
existed. Diagnosis took ~3 minutes once the right primitives
were on the screen; the prior 2 hours had been spent reading
qBit's own logs (which were healthy — the process is happy in
an empty namespace) and tweaking compose files (which were
correct).

## Fix

```bash
$ docker restart qbittorrent
qbittorrent
```

Synchronous restart re-attaches the child to the parent's
**current** namespace. Order matters: parent must be `(healthy)`
before child restart, otherwise the child comes up into another
orphaned state. In this incident gluetun had been healthy for
2 hours, so the order condition was already satisfied.

Total fix time after diagnosis: ~5 seconds.

## Recovery

No data recovery needed. The qBit process had been running the
whole time, just in an empty namespace — its database and
session state were untouched. Once the namespace was reattached,
peer connections re-established within the normal qBittorrent
reconnection cycle.

The auto-recovery script (`gluetun-auto-fix.sh`) was patched
the same day to restart both gluetun **and** any downstream
containers when it triggers, in that order, with a wait for
gluetun's healthcheck before restarting the children:

```bash
docker restart gluetun
until docker inspect gluetun \
        --format '{{.State.Health.Status}}' \
        | grep -q healthy; do
  sleep 2
done
docker restart qbittorrent
```

## Verification

```bash
$ docker inspect qbittorrent \
    --format '{{.NetworkSettings.SandboxID}}'
8a9f23bc1f...

$ docker exec qbittorrent ip -4 addr | grep -E 'eth|tun|wg'
2: tun0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1500 ...
    inet 10.64.0.7/32 scope global tun0

$ curl -sS -o /dev/null -w '%{http_code}\n' http://10.0.0.218:8080/
401
```

`SandboxID` populated. `tun0` present in the namespace, with
the expected VPN address. Web UI returning HTTP 401 (auth
challenge) — the expected response from qBit without
credentials, and proof that the listener is reachable.

## Open

- [x] Patch `gluetun-auto-fix.sh` to restart children after
  parent. Done same day.
- [ ] Add an external HTTP probe of the qBit web UI to the
  monitor stack. gluetun's healthcheck and the port-mapping
  check both stay green during this failure mode. Only a probe
  of the **child's** actual user-facing endpoint catches it.
- [ ] Audit other compose stacks on `nas-01` for the same
  `network_mode: service:<parent>` shape — VPN sidecars in
  general, jump-host shared-net patterns, Tor-proxy sidecars.
  The same trap applies to all of them.
