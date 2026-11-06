# Architecture

This document describes the planned architecture of InfraWatch and how metrics flow from the monitored host to the dashboards. Nothing described here is implemented yet.

## Components

### Node Exporter
Runs on each monitored host and exposes system metrics (CPU, memory, filesystem, network, load) over HTTP at `/metrics`, by default on port `9100`.

### Prometheus
Pulls (scrapes) metrics from its configured targets at a fixed interval, stores them in its local time-series database, and exposes a query API using PromQL, by default on port `9090`.

### Grafana
Connects to Prometheus as a data source and renders metrics as dashboards, by default on port `3000`. Data sources and dashboards are meant to be provisioned from files so the setup is reproducible.

### Docker Compose
Defines and runs all services on a shared network, with named volumes for persistent data.

## Metrics flow

```
 Host                Collection              Storage / Query         Visualization
+-----------+       +--------------+        +----------------+      +-----------+
| Kernel    |  -->  | Node         |  -->   | Prometheus     | -->  | Grafana   |
| /proc,/sys|       | Exporter     | scrape | TSDB + PromQL  | query| Dashboards|
+-----------+       | :9100/metrics|        | :9090          |      | :3000     |
                    +--------------+        +----------------+      +-----------+
```

1. **Generation:** Node Exporter reads host data from `/proc` and `/sys`.
2. **Exposure:** it publishes the data in Prometheus text format at `/metrics`.
3. **Collection:** Prometheus scrapes the endpoint at the configured interval.
4. **Storage:** samples are stored in Prometheus' time-series database with a retention policy.
5. **Visualization:** Grafana runs PromQL queries against Prometheus and displays the results.

## Repository layout

| Path          | Purpose                                         |
| ------------- | ----------------------------------------------- |
| `prometheus/` | Prometheus configuration and rules              |
| `grafana/`    | Grafana provisioning (data sources, dashboards) |
| `scripts/`    | Helper scripts                                  |
| `docs/`       | Documentation                                   |

## Design principles

- **Declarative:** all configuration lives in version control.
- **Reproducible:** the full stack starts from a single Compose file.
- **Minimal:** only the components needed for host monitoring.
- **Extensible:** new scrape targets and dashboards can be added without changing the core.
