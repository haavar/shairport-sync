# Multiple AirPlay 2 instances on one host

This example runs several AirPlay 2 instances of Shairport Sync in a single
network namespace, sharing one NQPTP, with **one shared config file**. Each
instance is distinguished by a single command-line option, `--address`.

It is a reference for the "multiple instances on one host" pattern, not a
turn-key deployment -- adjust the addresses, names and audio devices for your
system.

## What makes it work

* **`--address=<ip>`** binds one instance's RTSP socket to a single local IP, and
  (in this branch) also drives everything else that must differ per instance:
  * the Avahi advertisement is scoped to the interface that owns the address,
    under a host-name derived from it (see `run.sh`), so one Avahi daemon does
    not gather every IP under a single host-name;
  * the AirPlay 2 device id is taken from that interface's MAC;
  * the NQPTP shared-memory interface name is derived from the address
    (`/nqptp-<address>`).

  So the only per-instance settings are on the command line -- `--address`,
  `--name`, and the output device -- and every instance shares one
  `shairport-sync.conf`.

* **One NQPTP** runs as a sidecar for the whole namespace. It binds ports
  319/320 once and keeps a **separate clock per instance**, keyed by the
  shared-memory name each instance sends. This needs an NQPTP with multi-client
  support (mikebrady/nqptp#50). The instances share the sidecar's IPC namespace
  (`ipc: service:nqptp`) so they can read its clock, and reach it on `localhost`
  -- no per-instance IP or control port.

Each instance needs its own local IP on the host (one per `--address`), e.g. IP
aliases or separate interfaces. Assign them before starting the containers.

## Build the image

The stock image does not contain these changes, so build one from this branch,
with NQPTP built from the multi-client branch:

```sh
# from the root of this repository (the demo/shape2 branch)
docker build \
  --build-arg NQPTP_BRANCH=<nqptp branch with #50> \
  -t shairport-sync-multi:latest \
  -f docker/Dockerfile .
```

(`NQPTP_BRANCH` is consumed by `docker/Dockerfile`; point it at the nqptp#50
branch. Everything else is the standard image build.)

## Run

```sh
docker compose up -d
```

`Living Room` and `Kitchen` will appear as two independent AirPlay 2 targets.
Play to each separately, or group them in Control Center -- grouped, they share
one PTP timeline through the single NQPTP and stay in sync.
