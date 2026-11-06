# Architecture

This document describes the architecture of InfraWatch as implemented: the components, how metrics and alerts flow from the monitored host to the dashboard, and the main design decisions. For installation and usage, see the [README](../README.md).

## Overview

```
                      Host (Linux, rootless Podman or Docker)
 +----------------------------------------------------------------------------+
 |  host network namespace - every service listens on 127.0.0.1 only          |
 |                                                                            |
 |  +---------------+   scrape every 15s    +-----------------------------+   |
 |  | Node Exporter | <-------------------- |         Prometheus          |   |
 |  | :9100         |                       |  :9090                      |   |
 |  | reads /proc,  |                       |  - TSDB (volume, 15d)       |   |
 |  | /sys, /host   |   scrape every 15s    |  - evaluates alerts.yml     |   |
 |  +---------------+ <-------------------- |    every 15s                |   |
 |  +---------------+                       |  - exposes ALERTS metric    |   |
 |  | demo-service  |                       +--------------+--------------+   |
 |  | :9101         |                                      ^                  |
 |  +---------------+                                      | PromQL           |
 |                                           +-------------+--------------+   |
 |                                           |           Grafana          |   |
 |                                           |  :3000                     |   |
 |                                           |  - Prometheus datasource   |   |
 |                                           |  - System Overview (13     |   |
 |                                           |    panels), provisioned    |   |
 |                                           +----------------------------+   |
 +----------------------------------------------------------------------------+
```

## Components

### Node Exporter (`node-exporter`, port 9100)
Exposes host metrics (CPU, memory, filesystems, disk I/O, network, load) at `/metrics`. It runs unprivileged with the host PID namespace and the host network namespace, so network metrics describe the real host interfaces. The host root is mounted read-only at `/host` (`--path.rootfs=/host`) to read filesystem data. The mount has no SELinux relabeling.

### Prometheus (`prometheus`, port 9090)
Scrapes three jobs every 15 seconds and stores the samples in a local time-series database (volume `prometheus_data`, 15 days of retention):

| Job | Target | Purpose |
| --- | --- | --- |
| `prometheus` | `localhost:9090` | Prometheus self-monitoring |
| `node-exporter` | `localhost:9100` | Host metrics |
| `demo-service` | `localhost:9101` | Demo target for outage simulation |

It also loads `alerts.yml` (see below) and serves the query API used by Grafana.

### Grafana (`grafana`, port 3000)
Visualizes Prometheus data. Everything is provisioned from files in `grafana/`, so a fresh start needs no manual setup:

- `provisioning/datasources/prometheus.yml`: the default Prometheus datasource (`uid: prometheus`, `http://127.0.0.1:9090`, not editable).
- `provisioning/dashboards/dashboards.yml`: a file provider that loads `dashboards/` into the **InfraWatch** folder, re-scanning every 30 seconds, with UI edits and deletion disabled.
- `dashboards/system-overview.json`: the **InfraWatch | System Overview** dashboard (13 panels, default range 15 minutes, refresh 15 seconds).

Dashboard data and users are stored in the `grafana_data` volume. The admin password comes from the untracked `.env` file.

### demo-service (`demo-service`, port 9101)
A second Node Exporter instance with only the `uname` and `time` collectors and no host mounts. It exists only so the `TargetDown` alert can be exercised safely: stopping it never affects the real monitoring targets. It is controlled by `scripts/demo-service.sh`.

## Metrics flow

1. **Generation:** Node Exporter reads host data from `/proc`, `/sys` and `/host`.
2. **Exposure:** it publishes the data in Prometheus text format at `http://127.0.0.1:9100/metrics`.
3. **Collection:** Prometheus scrapes each target every 15 seconds and records an `up` sample (1 = scrape succeeded, 0 = failed).
4. **Storage:** samples are written to the Prometheus TSDB.
5. **Visualization:** Grafana runs PromQL queries through its Prometheus datasource and renders the panels.

## Alerting flow

Rules are defined in `prometheus/alerts.yml` (group `infrawatch-host`) and evaluated every 15 seconds:

| Alert | Expression (summary) | For | Severity |
| --- | --- | --- | --- |
| `HighCpuUsage` | `100 - avg(rate(idle[5m])) * 100 > 90` | 5m | warning |
| `HighMemoryUsage` | `(1 - MemAvailable / MemTotal) * 100 > 90` | 5m | warning |
| `RootDiskUsageHigh` | used % of `/` (excluding tmpfs-like filesystems) `> 85` | 5m | critical |
| `TargetDown` | `up == 0` | 1m | critical |

Each alert moves through the Prometheus states:

```
 inactive --(expression true)--> pending --(true for the whole "for" duration)--> firing
    ^                              |                                                |
    +------(expression false)------+------------------(expression false)-----------+
```

While an alert is `pending` or `firing`, Prometheus exposes it as the `ALERTS{alertname, alertstate, ...}` time series. The dashboard's top row (Firing alerts, Pending alerts, Active alerts table) queries that metric, so no rules are duplicated in Grafana. Inactive rules produce no series; their state is visible in the Prometheus UI (`/alerts`, `/rules`) and API (`/api/v1/rules`).

There is **no Alertmanager yet**, so alerts are not routed to notifications. Adding it is on the roadmap.

### Verification of the alerting pipeline

- `scripts/test-alerts.sh` runs `promtool test rules` with 26 synthetic-data cases, covering normal, pending, firing, recovery, short spikes and exact threshold values for every rule. It does not use the running stack.
- `scripts/test-target-down.sh` stops only `demo-service`, observes `TargetDown` go `inactive` -> `pending` -> `firing`, restores the service and observes the recovery. In the recorded run, pending appeared after about 15 seconds, firing after about 76 seconds, and the alert cleared about 10 seconds after the restore.

## Repository layout

| Path | Purpose |
| --- | --- |
| `docker-compose.yml` | Defines the four services and two named volumes |
| `.env.example` | Template for the local `.env` (the real `.env` is untracked) |
| `prometheus/prometheus.yml` | Scrape jobs and rule file |
| `prometheus/alerts.yml` | Alert rules |
| `prometheus/tests/alerts_test.yml` | Unit tests for the alert rules |
| `grafana/provisioning/` | Datasource and dashboard provider |
| `grafana/dashboards/` | Dashboard JSON |
| `scripts/` | Test and demo helpers |
| `docs/` | Documentation and screenshots |

## Deployment and security decisions

- **Host networking, loopback only:** all services use `network_mode: host` and bind to `127.0.0.1`, no ports are published. This gives Node Exporter accurate network metrics while keeping every endpoint unreachable from other machines. The trade-off is that any local user or process on the machine can reach the endpoints.
- **Least privilege:** no `privileged`; every container drops all capabilities and sets `no-new-privileges`.
- **SELinux stays Enforcing:** the host root is mounted read-only without relabeling (relabeling `/` would be destructive). Only project files are relabeled with `z`, all read-only: `prometheus.yml`, `alerts.yml`, `grafana/provisioning/` and `grafana/dashboards/`.
- **Rootless-friendly:** works with rootless Podman. Named volumes keep Prometheus and Grafana data across `down`/`up` cycles; `down -v` deletes them.
- **No secrets in Git:** the Grafana admin password is read from the untracked `.env`. The compose file fails fast if it is missing.
- **Pinned versions:** images are fully qualified and pinned (Prometheus v3.5.0, Node Exporter v1.9.1, Grafana 12.2.0).
- **Declarative:** datasource, dashboard and alert rules live in version control; there is no manual setup after `up`.

## Known limitations

- No Alertmanager or notifications.
- Rootless Podman can only expose what the user is allowed to read; some host metrics may be partial on other systems.
- Tested only on Fedora 44 with rootless Podman. Docker has not been tested.
- The dashboard was reviewed in a real browser (Firefox 150) in the normal and `firing` states; the `pending` styling has not been captured.
