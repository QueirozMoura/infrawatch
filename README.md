# InfraWatch

InfraWatch is an open source monitoring and observability stack for Linux hosts. It collects system metrics, stores them as time series, and presents them in ready-to-use dashboards, all deployable with a single Docker Compose command.

> **Status:** early development. Prometheus and Node Exporter are working and have been tested on Fedora 44 with rootless Podman; Grafana is planned.

## Goals

- Provide a simple, reproducible monitoring stack for a single host or a small fleet.
- Ship with sensible defaults: preconfigured scrape jobs and provisioned dashboards.
- Keep configuration declarative, versioned and easy to maintain.
- Serve as a learning-friendly reference for Prometheus and Grafana.

## Technologies

| Component     | Role                                          |
| ------------- | --------------------------------------------- |
| Node Exporter | Exposes host-level metrics (CPU, memory, disk, network) |
| Prometheus    | Scrapes, stores and queries time-series metrics |
| Grafana       | Visualizes metrics through dashboards         |
| Docker Compose| Orchestrates the whole stack                  |

## Planned architecture

```
+---------------+   scrape    +------------+   query    +---------+
| Node Exporter | <---------- | Prometheus | <--------- | Grafana |
|  (host metrics)|   :9100    |   :9090    |   PromQL   |  :3000  |
+---------------+             +------------+            +---------+
```

See [docs/architecture.md](docs/architecture.md) for details.

## Repository structure

```
InfraWatch/
├── docker-compose.yml  # Prometheus + Node Exporter stack
├── prometheus/   # Prometheus configuration (scrape jobs, rules)
├── grafana/      # Grafana provisioning and dashboards
├── scripts/      # Helper scripts
└── docs/         # Project documentation
```

## Getting started

The stack runs with **Podman (rootless)** or **Docker**, using the same `docker-compose.yml`.

### Requirements

- A Linux host
- One of:
  - Podman 4+ with a compose provider (`podman-compose` or `docker-compose`), used as `podman compose`
  - Docker with the Compose plugin, used as `docker compose`

The commands below use `podman compose`; replace it with `docker compose` if you use Docker.

### Start

```bash
podman compose up -d
```

### Verify

```bash
podman compose ps
curl -s http://127.0.0.1:9100/metrics | head      # Node Exporter metrics
curl -s http://127.0.0.1:9090/-/ready             # Prometheus readiness
ss -ltn | grep -E ':(9090|9100)\b'                # must show 127.0.0.1 only
```

Then open <http://127.0.0.1:9090/targets>: the `prometheus` and `node-exporter` targets should be `UP`. Example queries:

- `100 - avg(rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100` (CPU %)
- `node_memory_MemAvailable_bytes` (RAM)
- `node_filesystem_avail_bytes` (disk)
- `rate(node_network_receive_bytes_total[1m])` (network)

### Validate configuration (optional)

```bash
podman compose config -q
podman run --rm --entrypoint promtool -v "$PWD/prometheus:/cfg:ro,z" docker.io/prom/prometheus:v3.5.0 check config /cfg/prometheus.yml
```

### Stop

```bash
podman compose down        # stop and remove containers, keep metrics data
podman compose down -v     # also delete the Prometheus data volume
```

Services are not configured to start automatically on boot.

### Security model

- Both services use `network_mode: host` and bind **only to `127.0.0.1`** (`--web.listen-address`); no ports are published, so nothing is reachable from other machines.
- No `privileged`; both containers drop all capabilities (`cap_drop: [ALL]`) and set `no-new-privileges`.
- Node Exporter mounts the host root read-only at `/host` with **no SELinux relabeling** (`:z`/`:Z` on `/` would relabel the whole filesystem). SELinux is left enforcing.
- Only `prometheus.yml` is mounted with `z`, which relabels that single file.

### Tested environment

Prometheus and Node Exporter were run and verified on **Fedora 44 (Workstation) with Podman 5.8.1 rootless**, `podman-compose` 1.6.0 and SELinux in **Enforcing** mode, with no changes to the SELinux policy.

| Check | Result |
|---|---|
| `podman compose config` and `promtool check config` | valid |
| Listening sockets | only `127.0.0.1:9090` and `127.0.0.1:9100` |
| Prometheus targets `prometheus` and `node-exporter` | **UP** |
| CPU (`node_cpu_seconds_total`) | validated, host usage and load |
| RAM (`node_memory_*`) | validated, host total and available |
| Disk (`node_filesystem_*`, `node_disk_*`) | validated, mountpoints `/`, `/home`, `/boot`, `/boot/efi` and disk I/O |
| Network (`node_network_*`) | validated, real host interfaces (not container-only) |
| `node_os_info` | reports the host OS (Fedora Linux 44) |
| SELinux denials related to the containers | none found |

Nine Node Exporter collectors report `success=0` (`bonding`, `fibrechannel`, `infiniband`, `ipvs`, `nfs`, `nfsd`, `nvme`, `tapestats`, `zfs`). They cover hardware or features absent on the test machine and do not affect the metrics above.

### Limitations

- **Rootless Podman:** the container only sees what your user can read, so some host files and metrics may be missing on other machines.
- **SELinux:** on the tested host, Node Exporter read `/host` without relabeling or policy changes. Other policies or hosts may behave differently; to check for denials, run `sudo ausearch -m avc -ts recent` (or `journalctl _AUDIT_TYPE=1400`). This project does not relax SELinux.
- **Host networking:** the containers share the host network namespace. Binding to loopback keeps the endpoints local, but any local user or process on the machine can reach them.
- **Docker:** the same `docker-compose.yml` is intended to work with Docker Compose, but it has not been tested with Docker.

## Alerts

Alert rules live in [`prometheus/alerts.yml`](prometheus/alerts.yml) and are evaluated by Prometheus every 15 seconds (CPU > 90%, RAM > 90%, root disk > 85%, target down). Notifications are not implemented yet.

Check the rules and their state:

- Web UI: <http://127.0.0.1:9090/alerts> (states) and <http://127.0.0.1:9090/rules> (definitions and last evaluation).
- API:

  ```bash
  curl -s http://127.0.0.1:9090/api/v1/rules  | python3 -m json.tool   # all rules with state and health
  curl -s http://127.0.0.1:9090/api/v1/alerts | python3 -m json.tool   # only pending/firing alerts
  ```

- PromQL: `ALERTS{alertstate=~"pending|firing"}` returns active alerts only.

The **InfraWatch | System Overview** dashboard shows firing and pending counts and a table of active alerts, built from the `ALERTS` metric (no rules are duplicated in Grafana). Rules in the `inactive` state produce no `ALERTS` series, so they do not appear in the dashboard; use the Prometheus UI or API to see them.

### Simulating an outage (TargetDown)

A lightweight `demo-service` (a minimal second Node Exporter on `127.0.0.1:9101`, scraped as job `demo-service`) exists only to exercise the alerts. The helper scripts only ever stop or start that one container; Prometheus, Grafana and Node Exporter are never touched.

```bash
scripts/demo-service.sh status          # start | stop | restore | status
scripts/test-target-down.sh             # full automated test, ~90 seconds
```

The test checks that the target is UP, stops the demo service, follows `TargetDown` through `inactive` -> `pending` -> `firing` (the rule uses `for: 1m`, evaluated every 15s), restores the service and waits for the alert to clear. The service is always restored on exit, even if the test fails or is interrupted. To do it by hand: run `scripts/demo-service.sh stop`, watch <http://127.0.0.1:9090/alerts> and the dashboard's alert panels, then run `scripts/demo-service.sh restore`.

Last run on Fedora 44 (rootless Podman): pending after ~15s, firing after ~76s, recovered ~10s after restore.

## Roadmap

1. Repository structure and documentation
2. Docker Compose stack with Prometheus and Node Exporter (current)
3. Grafana provisioning and dashboards
4. Alerting rules
5. Helper scripts and usage guide

## License

To be defined.
