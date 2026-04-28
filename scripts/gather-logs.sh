#!/usr/bin/env bash
# gather-logs.sh — bundle journalctl + docker logs + systemctl status
#                  for one service into labeled stdout sections.
#
# Usage:   gather-logs.sh <service> [--since <duration>]
# Example: gather-logs.sh qbittorrent --since 2h
#          gather-logs.sh sonarr --since "2 hours ago"
#          gather-logs.sh nginx --since 30m
#
# The skill calls this in retrospective mode to produce one bundle
# Claude can read in a single Read call. Sections are clearly
# labeled so the reader can grep into them without losing context.
#
# Designed to degrade gracefully:
#   - Missing systemd unit -> section says "no systemd unit found"
#   - Missing docker container -> section says "no docker container found"
#   - Neither present -> exits with a clear error
#
# POSIX-friendly bash. Requires: journalctl OR docker (preferably both).

set -u
# Note: not using 'set -e' — we want to continue past missing tools
# and report sections individually rather than aborting the whole
# bundle on the first absent dependency.

#######################################
# Argument parsing
#######################################

print_usage() {
    cat <<'EOF'
gather-logs.sh — bundle service logs into one labeled stdout dump

USAGE
    gather-logs.sh <service> [--since <duration>]

ARGUMENTS
    <service>          Service name. Used as both the systemd unit
                       (with .service suffix added if missing) and
                       the docker container/compose service name.

    --since <duration> How far back to pull logs.
                       journalctl-friendly forms: "2h", "30m",
                       "2 hours ago", "today", "2026-04-28".
                       Default: "1 hour ago".

EXAMPLES
    gather-logs.sh qbittorrent --since 2h
    gather-logs.sh sonarr --since "today"
    gather-logs.sh nginx --since 30m
EOF
}

if [ "$#" -lt 1 ]; then
    print_usage >&2
    exit 2
fi

case "$1" in
    -h|--help)
        print_usage
        exit 0
        ;;
esac

SERVICE="$1"
shift

SINCE="1 hour ago"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --since)
            if [ "$#" -lt 2 ]; then
                echo "ERROR: --since requires a value" >&2
                exit 2
            fi
            SINCE="$2"
            shift 2
            ;;
        --since=*)
            SINCE="${1#--since=}"
            shift
            ;;
        *)
            echo "ERROR: unrecognised argument: $1" >&2
            print_usage >&2
            exit 2
            ;;
    esac
done

# Normalize systemd unit name (add .service if not specified)
case "$SERVICE" in
    *.service|*.timer|*.socket|*.target|*.path|*.mount)
        UNIT="$SERVICE"
        ;;
    *)
        UNIT="${SERVICE}.service"
        ;;
esac

# Container name lookup uses the bare service name (no .service)
CONTAINER="${SERVICE%.service}"

#######################################
# Section header / footer
#######################################

section() {
    local title="$1"
    printf '\n'
    printf '===============================================================\n'
    printf '== %s\n' "$title"
    printf '===============================================================\n'
}

#######################################
# Capability detection
#######################################

HAVE_JOURNALCTL=0
HAVE_DOCKER=0
HAVE_SYSTEMCTL=0

command -v journalctl >/dev/null 2>&1 && HAVE_JOURNALCTL=1
command -v docker     >/dev/null 2>&1 && HAVE_DOCKER=1
command -v systemctl  >/dev/null 2>&1 && HAVE_SYSTEMCTL=1

if [ "$HAVE_JOURNALCTL" -eq 0 ] && [ "$HAVE_DOCKER" -eq 0 ]; then
    echo "ERROR: neither journalctl nor docker is available." >&2
    echo "       This script needs at least one of them." >&2
    exit 1
fi

#######################################
# Header
#######################################

section "gather-logs.sh report"
printf 'service:    %s\n' "$SERVICE"
printf 'unit:       %s\n' "$UNIT"
printf 'container:  %s\n' "$CONTAINER"
printf 'since:      %s\n' "$SINCE"
printf 'host:       %s\n' "$(hostname 2>/dev/null || echo unknown)"
printf 'date:       %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"

#######################################
# systemctl status
#######################################

section "systemctl status ${UNIT}"
if [ "$HAVE_SYSTEMCTL" -eq 1 ]; then
    if systemctl status --no-pager --lines=20 "$UNIT" 2>&1; then
        :
    else
        rc=$?
        # systemctl returns non-zero for inactive/failed units; that's
        # interesting state, not a script failure. Annotate but don't bail.
        printf '\n[systemctl exit code: %d — non-zero is normal for inactive/failed units]\n' "$rc"
    fi
else
    echo "[systemctl not available on this host]"
fi

#######################################
# journalctl
#######################################

section "journalctl -u ${UNIT} --since \"${SINCE}\""
if [ "$HAVE_JOURNALCTL" -eq 1 ]; then
    if journalctl -u "$UNIT" --since "$SINCE" --no-pager 2>&1; then
        :
    else
        rc=$?
        printf '\n[journalctl exit code: %d]\n' "$rc"
    fi
else
    echo "[journalctl not available on this host]"
fi

#######################################
# docker logs
#######################################

section "docker logs ${CONTAINER} --since \"${SINCE}\""
if [ "$HAVE_DOCKER" -eq 1 ]; then
    # Check the container exists before pulling logs — clearer than
    # the raw "Error: No such container" message.
    if docker inspect "$CONTAINER" >/dev/null 2>&1; then
        # 2>&1 because docker writes container stderr to its stderr,
        # which we want bundled into the same readable stream.
        docker logs --since "$SINCE" "$CONTAINER" 2>&1
        rc=$?
        if [ "$rc" -ne 0 ]; then
            printf '\n[docker logs exit code: %d]\n' "$rc"
        fi
    else
        echo "[no docker container named '$CONTAINER' found]"
        # Try finding similarly-named containers as a hint
        echo ""
        echo "Containers with names matching '$CONTAINER':"
        docker ps -a --format '  {{.Names}}\t{{.Status}}' \
            2>/dev/null | grep -i "$CONTAINER" || \
            echo "  (no matches)"
    fi
else
    echo "[docker not available on this host]"
fi

#######################################
# docker inspect (network and state — useful for netns-orphan diagnoses)
#######################################

if [ "$HAVE_DOCKER" -eq 1 ] && docker inspect "$CONTAINER" >/dev/null 2>&1; then
    section "docker inspect ${CONTAINER} (network + state summary)"
    docker inspect "$CONTAINER" --format '
state:           {{.State.Status}}
running:         {{.State.Running}}
health:          {{if .State.Health}}{{.State.Health.Status}}{{else}}(no healthcheck){{end}}
started_at:      {{.State.StartedAt}}
network_mode:    {{.HostConfig.NetworkMode}}
sandbox_id:      {{.NetworkSettings.SandboxID}}
ip_address:      {{.NetworkSettings.IPAddress}}
' 2>&1

    section "docker exec ${CONTAINER} ip -4 addr (inside the namespace)"
    if docker exec "$CONTAINER" sh -c 'command -v ip' >/dev/null 2>&1; then
        docker exec "$CONTAINER" ip -4 addr 2>&1 || \
            echo "[ip command failed inside container]"
    else
        echo "[no 'ip' command inside container — try 'ifconfig' or skip]"
    fi
fi

#######################################
# Footer
#######################################

section "end of bundle"
printf 'gather-logs.sh complete.\n'
