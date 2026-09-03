#!/bin/sh

# exit if any command returns a non-zero result
set -e

echo "Shairport Sync Startup ($(date))"

# Peek at --address (all arguments are still forwarded to shairport-sync
# unchanged below):
#   --address=<ip>  -> a specific local IP: wait for it, and scope Avahi to it.
#
# nqptp is NOT started here. In this multi-instance model it runs once as a
# sidecar (binding 319/320 for the whole netns) and keeps a separate clock per
# instance, keyed by each instance's shared-memory name -- which shairport-sync
# derives from --address. shairport-sync reaches nqptp on localhost as usual.
ADDRESS=""
for arg in "$@"; do
  case "$arg" in
    --address=*) ADDRESS="${arg#*=}" ;;
  esac
done

# If a specific address is requested, wait for it to be assigned before
# shairport-sync tries to bind it -- something else may put it on the interface
# after we start, and the bind would otherwise fail with "Cannot assign
# requested address".
if [ -n "$ADDRESS" ]; then
  echo "Waiting for ${ADDRESS} to be assigned..."
  until ip addr 2>/dev/null | grep -q "inet ${ADDRESS}/"; do sleep 1; done
fi

if [ -z ${ENABLE_AVAHI+x} ] || [ $ENABLE_AVAHI -eq 1 ]; then
  # When bound to a specific address, scope Avahi to just the interface that owns
  # it, under a hostname derived from the address, so several instances in one
  # network namespace each advertise only their own IP (this is what stops one
  # Avahi daemon gathering every IP under a single hostname).
  if [ -n "$ADDRESS" ]; then
    MDNS_INTERFACE=$(ip -4 addr | awk -v p="${ADDRESS}/" '
      /^[0-9]+:/ { iface = $2; sub(/[@:].*/, "", iface) }
      $1 == "inet" && index($2, p) == 1 { print iface; exit }')
    if [ -n "$MDNS_INTERFACE" ]; then
      cat > /etc/avahi/avahi-daemon.conf <<EOF
[server]
host-name=shairport-$(echo "$ADDRESS" | tr . -)
use-ipv4=yes
use-ipv6=yes
allow-interfaces=$MDNS_INTERFACE
[publish]
publish-hinfo=no
publish-workstation=no
[rlimits]
EOF
    fi
  fi

  rm -rf /run/dbus/dbus.pid
  rm -rf /run/avahi-daemon/pid

  dbus-uuidgen --ensure
  dbus-daemon --system

  avahi-daemon --daemonize --no-chroot
fi

while [ ! -f /var/run/avahi-daemon/pid ]; do
  echo "Warning: avahi is not running, sleeping for 5 seconds before trying to start shairport-sync"
  sleep 5
done

# for PipeWire
export XDG_RUNTIME_DIR=/tmp

# for PulseAudio
export PULSE_SERVER=unix:/tmp/pulseaudio.socket
export PULSE_COOKIE=/tmp/pulseaudio.cookie

echo "Finished startup tasks ($(date)), starting Shairport Sync."

exec /usr/local/bin/shairport-sync "$@"
