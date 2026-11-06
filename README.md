# InfraWatch

InfraWatch is an open source monitoring and observability stack for Linux hosts. It collects system metrics, stores them as time series, and presents them in ready-to-use dashboards, all deployable with a single Docker Compose command.

> **Status:** early development. Prometheus and Node Exporter are available; Grafana is planned.

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

### Limitations

- **Rootless Podman:** the container only sees what your user can read, so some host files and metrics may be missing.
- **SELinux (Fedora):** confined containers cannot read most host files under `/host`. CPU, memory and network come from `/proc` and `/sys` and are unaffected. Filesystem and `node_os_info` metrics may be partial. Check denials with `sudo ausearch -m avc -ts recent`. This project does not relax SELinux.
- **Host networking:** the container shares the host network namespace. Binding to loopback keeps it local, but any local user or process on the machine can reach the endpoints.
- **Docker (rootful):** works the same way, with more complete filesystem metrics.
- This configuration has been written but not yet run; verify the targets after the first start.

## Roadmap

1. Repository structure and documentation
2. Docker Compose stack with Prometheus and Node Exporter (current)
3. Grafana provisioning and dashboards
4. Alerting rules
5. Helper scripts and usage guide

## License

To be defined.
