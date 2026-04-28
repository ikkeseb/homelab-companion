#!/usr/bin/env bash
# check-ufw-docker.sh — diagnose the ufw-docker bridge-drop pitfall.
#
# Usage:   check-ufw-docker.sh [<container>] [<host-ip>] [<port>]
#
# When invoked with no arguments, the script prints the host's ufw
# state, all Docker bridge subnets, and flags allow/deny mismatches.
# When given a container plus a host IP and port, it tests
# reachability from inside the container, identifies the source
# subnet, and recommends the correct fix shape.
#
# This is a *diagnostic* — it does not modify ufw or docker config.
# Read-only. See pitfall reference:
#   references/pitfalls/ufw-docker-bridge-drop.md
#
# Exit codes:
#   0 — diagnosis complete (no judgment about whether you have the bug)
#   1 — required tool missing (ufw or docker)
#   2 — argument error

set -u

print_usage() {
    cat <<'EOF'
check-ufw-docker.sh — diagnose ufw vs Docker bridge traffic

USAGE
    check-ufw-docker.sh
    check-ufw-docker.sh <container>
    check-ufw-docker.sh <container> <host-ip> <port>

ARGUMENTS
    <container>   Docker container name to test from. Optional.
                  When given, the script identifies the container's
                  source subnet.

    <host-ip>     Host LAN IP the container should reach. Optional.
                  Defaults to skipping the reachability test.

    <port>        Host port the container should reach. Optional.
                  Required if <host-ip> is given.

EXAMPLES
    check-ufw-docker.sh
        Show ufw state + all bridge subnets, flag mismatches.

    check-ufw-docker.sh ci-runner
        As above, plus identify ci-runner's source subnet.

    check-ufw-docker.sh ci-runner 192.168.1.10 22
        As above, plus test ci-runner -> 192.168.1.10:22.
EOF
}

case "${1:-}" in
    -h|--help)
        print_usage
        exit 0
        ;;
esac

CONTAINER="${1:-}"
HOST_IP="${2:-}"
PORT="${3:-}"

if [ -n "$HOST_IP" ] && [ -z "$PORT" ]; then
    echo "ERROR: <port> is required when <host-ip> is given." >&2
    print_usage >&2
    exit 2
fi

#######################################
# Capability checks
#######################################

HAVE_UFW=0
HAVE_DOCKER=0
HAVE_IPTABLES=0
command -v ufw      >/dev/null 2>&1 && HAVE_UFW=1
command -v docker   >/dev/null 2>&1 && HAVE_DOCKER=1
command -v iptables >/dev/null 2>&1 && HAVE_IPTABLES=1

if [ "$HAVE_DOCKER" -eq 0 ]; then
    echo "ERROR: docker is required for this diagnostic." >&2
    exit 1
fi

#######################################
# Helpers
#######################################

section() {
    printf '\n=== %s ===\n' "$1"
}

# sudo only if needed and available — ufw and iptables typically
# need root. We don't auto-sudo (would require interactive prompt
# in some environments); we just hint when output is empty.
need_sudo_hint() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "  (note: run with sudo to read ufw / iptables state)"
    fi
}

#######################################
# 1. ufw status
#######################################

section "ufw status"
if [ "$HAVE_UFW" -eq 1 ]; then
    if ! ufw status verbose 2>&1; then
        echo "  ufw status returned non-zero — likely needs sudo"
        need_sudo_hint
    fi
else
    echo "ufw is not installed on this host."
    echo "  If a different firewall (firewalld, raw iptables, nftables)"
    echo "  is active, this pitfall may still apply with adapted commands."
fi

#######################################
# 2. Docker bridge subnets
#######################################

section "Docker bridge networks (subnet allocations)"
docker network ls --filter driver=bridge --format '{{.Name}}' \
    | while read -r net; do
        # Pull subnets out of inspect; skip networks with no IPAM config
        subnets=$(docker network inspect "$net" \
            --format '{{range .IPAM.Config}}{{.Subnet}} {{end}}' 2>/dev/null)
        if [ -n "$subnets" ]; then
            printf '  %-25s %s\n' "$net" "$subnets"
        fi
    done

#######################################
# 3. Quick mismatch flag
#######################################

section "Bridge subnets vs ufw allow rules"
if [ "$HAVE_UFW" -eq 1 ] && [ "$(id -u)" -eq 0 ]; then
    UFW_RULES=$(ufw status 2>/dev/null)
    DEFAULT=$(echo "$UFW_RULES" | grep -i 'default:' || true)
    INCOMING_DENY=0
    case "$DEFAULT" in
        *deny\ \(incoming\)*|*deny\ \(routed\)*)
            INCOMING_DENY=1
            ;;
    esac

    if [ "$INCOMING_DENY" -eq 1 ]; then
        echo "  ufw default policy: deny incoming."
        echo "  Bridge-to-host LAN-IP traffic will be dropped unless"
        echo "  the bridge subnet has an explicit allow rule."
        echo ""
        echo "  Bridge subnets in use:"
        docker network ls --filter driver=bridge --format '{{.Name}}' \
            | while read -r net; do
                docker network inspect "$net" \
                    --format '{{range .IPAM.Config}}    {{.Subnet}}{{end}}' \
                    2>/dev/null
            done | sort -u | grep -v '^$' || true
        echo ""
        echo "  Compare against allow rules above. Any subnet without"
        echo "  a matching 'ufw allow from <subnet>' rule is at risk"
        echo "  if a container on that bridge tries to reach the host's"
        echo "  LAN IP on a port other than what's in the allow list."
    else
        echo "  ufw default policy is not deny-incoming."
        echo "  This pitfall does not apply directly."
    fi
else
    echo "  (skipped — needs ufw + sudo to inspect rules)"
    need_sudo_hint
fi

#######################################
# 4. Container-side checks (optional)
#######################################

if [ -n "$CONTAINER" ]; then
    section "Container '$CONTAINER' — source subnet identification"
    if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
        echo "  ERROR: no container named '$CONTAINER'."
        exit 0
    fi

    NETWORK_MODE=$(docker inspect "$CONTAINER" \
        --format '{{.HostConfig.NetworkMode}}' 2>/dev/null)
    echo "  network_mode: $NETWORK_MODE"

    case "$NETWORK_MODE" in
        host)
            echo "  Container uses host network. ufw bridge-drop pitfall"
            echo "  does not apply (no separate bridge subnet)."
            exit 0
            ;;
        container:*|service:*)
            echo "  Container is bound to another container's namespace."
            echo "  Inspect the parent for the actual source subnet."
            ;;
    esac

    echo ""
    if docker exec "$CONTAINER" sh -c 'command -v ip' >/dev/null 2>&1; then
        echo "  Source addresses inside the namespace:"
        docker exec "$CONTAINER" ip -4 -o addr show 2>&1 \
            | awk '$2 != "lo" {printf "    %s %s\n", $2, $4}' \
            || echo "    (ip command failed)"
    else
        echo "  No 'ip' command in container; falling back to network inspect."
        docker inspect "$CONTAINER" \
            --format '  IPAddress: {{.NetworkSettings.IPAddress}}' 2>&1
        docker inspect "$CONTAINER" --format '{{range $k, $v := .NetworkSettings.Networks}}    network={{$k}} ip={{$v.IPAddress}} subnet=(see "docker network inspect {{$k}}"){{"\n"}}{{end}}'
    fi
fi

#######################################
# 5. Reachability test (optional)
#######################################

if [ -n "$CONTAINER" ] && [ -n "$HOST_IP" ] && [ -n "$PORT" ]; then
    section "Reachability test: ${CONTAINER} -> ${HOST_IP}:${PORT}"
    # /dev/tcp is bash-only and present in most container shells.
    # Fall back to a clear message if the test infrastructure isn't there.
    docker exec "$CONTAINER" bash -c "
        if (timeout 5 bash -c '</dev/tcp/${HOST_IP}/${PORT}') 2>/dev/null; then
            echo '  RESULT: OPEN — container reached host:port'
        else
            echo '  RESULT: BLOCKED — container could not reach host:port'
            echo '          (TCP timeout, no ICMP — consistent with ufw DROP)'
        fi
    " 2>&1 || \
        echo "  (test failed to run — container may lack bash)"
fi

#######################################
# Footer with pitfall reference
#######################################

section "Next steps"
cat <<'EOF'
  If this diagnostic shows a bridge subnet without an allow rule
  AND the container can't reach the host port, see:

    references/pitfalls/ufw-docker-bridge-drop.md

  The three fix shapes (host networking, ufw allow from <subnet>,
  host.docker.internal) are documented there with trade-offs.
EOF
