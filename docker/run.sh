#!/bin/sh

# exit if any command returns a non-zero result
set -e

echo "Shairport Sync Startup ($(date))"

# Peek at a couple of the shairport-sync arguments (all name=value; every
# argument is still forwarded to shairport-sync unchanged below):
#   --address=<ip>      -> a specific local IP: run nqptp on it and scope avahi to it
#   --service-type=<t>  -> decides below whether nqptp is needed
SERVICE_TYPE=""
ADDRESS=""
for arg in "$@"; do
  case "$arg" in
    --address=*)      ADDRESS="${arg#*=}" ;;
    --service-type=*) SERVICE_TYPE="${arg#*=}" ;;
  esac
done

# Control address for nqptp, derived from the bind address (IPv4 a.b.c.d ->
# 127.b.c.d, loopback only); empty for a non-IPv4 or unset address.
NQPTP_CONTROL=""
case "$ADDRESS" in
  *.*.*.*) NQPTP_CONTROL="127.$(echo "$ADDRESS" | cut -d. -f2-4)" ;;
esac

# If a specific address is requested, wait for it to be assigned before we bind
# it below -- it is usually put on the interface by something else, perhaps after
# we start, and the binds would otherwise fail with "Cannot assign requested
# address". (Needed regardless of the mDNS backend.)
if [ -n "$ADDRESS" ]; then
  echo "Waiting for ${ADDRESS} to be assigned..."
  until ip addr 2>/dev/null | grep -q "inet ${ADDRESS}/"; do sleep 1; done
fi

if [ -z ${ENABLE_AVAHI+x} ] || [ $ENABLE_AVAHI -eq 1 ]; then
  # When bound to a specific address, scope avahi to just the interface that owns
  # it, under a hostname derived from the address -- unique per instance and never
  # user-visible (the AirPlay name lives in the config) -- so several instances in
  # one network namespace each advertise only their own IP.
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

# Start NQPTP for AirPlay 2 -- not needed for AirPlay 1 (classic / airplay1).
if [ "$SERVICE_TYPE" != classic ] && [ "$SERVICE_TYPE" != airplay1 ]; then
  echo "Starting NQPTP ($(date))"
  if [ -n "$NQPTP_CONTROL" ]; then
    (/usr/local/bin/nqptp -a "$ADDRESS" -c "$NQPTP_CONTROL" > /dev/null 2>&1) &
  else
    (/usr/local/bin/nqptp > /dev/null 2>&1) &
  fi
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

# Prepend the derived control address (ahead of any "--" audio-backend separator)
# so shairport-sync reaches the same nqptp. Empty -> unchanged single-instance.
if [ -n "$NQPTP_CONTROL" ]; then
  exec /usr/local/bin/shairport-sync --nqptp-control-address="$NQPTP_CONTROL" "$@"
else
  exec /usr/local/bin/shairport-sync "$@"
fi
