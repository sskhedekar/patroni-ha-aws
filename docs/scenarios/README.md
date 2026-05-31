# DBA Scenarios — Patroni HA Cluster

All scenarios were executed on a live 3-node Patroni cluster (Ubuntu 24.04, PostgreSQL 17, etcd, HAProxy, Keepalived) running on AWS EC2. Traffic was simulated using `app-traffic.sh` — a write every 2 seconds via port 5000 (primary) and a read via port 5001 (replica), showing real-time impact of each operation.

---

## Scenarios Overview

| # | Scenario | Tool | Downtime | Details |
|---|---|---|---|---|
| 1 | Planned Switchover | `patronictl switchover` | ~1-2s | [→](scenario1-switchover/README.md) |
| 2 | Auto-Failover | `systemctl stop patroni` on primary | ~25-30s | [→](scenario2-autofailover/README.md) |
| 3 | Pause / Resume | `patronictl pause/resume` | None | [→](scenario3-pause/README.md) |
| 4 | Parameter Change | `patronictl edit-config` + reload/restart | None / ~1-2s | [→](scenario4-parameter-change/README.md) |
| 5 | Extension Install | `apt install` + `CREATE EXTENSION` | None / ~1-2s | [→](scenario5-extension/README.md) |
| 6 | Force Rebuild Replica | `patronictl reinit` | None | [→](scenario6-reinit/README.md) |
| 7 | pgBackRest Backup to S3 | `pgbackrest backup --type=full` | None | [→](scenario7-pgbackrest/README.md) |
| 8 | Cluster Health Monitoring | patronictl, curl, etcdctl | None | [→](scenario8-monitoring/README.md) |

---

## Scenario 1 — Planned Switchover
**[→ Full details](scenario1-switchover/README.md)**

Moves the primary role to another node with minimal downtime. Patroni gracefully demotes the current primary, promotes the candidate, and HAProxy detects the new primary within ~9 seconds. The VIP does NOT move — Keepalived is independent of Patroni leadership.

---

## Scenario 2 — Auto-Failover
**[→ Full details](scenario2-autofailover/README.md)**

Simulates unexpected primary failure. Patroni waits for the etcd TTL (30s) to expire, then surviving replicas race to acquire the leader lock. First to write its name wins — no explicit priority. The former primary rejoins as a replica after recovery.

---

## Scenario 3 — Pause / Resume
**[→ Full details](scenario3-pause/README.md)**

Freezes Patroni's HA automation before planned maintenance. PostgreSQL and replication continue normally — only automatic failover decisions are suspended. All nodes log `PAUSE: no action` every loop iteration while paused.

---

## Scenario 4 — Parameter Change
**[→ Full details](scenario4-parameter-change/README.md)**

Changes PostgreSQL parameters cluster-wide via `patronictl edit-config` (writes to etcd, all nodes pick it up). Reload-only params (`work_mem`) apply instantly with no restart. Restart-required params (`shared_buffers`) show `pending_restart` in `patronictl list` — restart replicas first, primary last.

---

## Scenario 5 — Extension Installation
**[→ Full details](scenario5-extension/README.md)**

OS package must be installed on all 3 nodes. `CREATE EXTENSION` runs on primary only — WAL replicates the DDL to replicas automatically. Extensions needing `shared_preload_libraries` (like `pgaudit`) require a restart of all nodes before the extension can be created.

---

## Scenario 6 — Force Rebuild Replica
**[→ Full details](scenario6-reinit/README.md)**

`patronictl reinit` wipes a replica's data directory and rebuilds it from scratch via `pg_basebackup` from the current primary. Used when a replica is corrupt, too far behind to stream, or pg_rewind failed. Primary and other replicas are completely unaffected.

---

## Scenario 7 — pgBackRest Backup to S3
**[→ Full details](scenario7-pgbackrest/README.md)**

Enterprise-grade backup using a dedicated pgBackRest repository host (pgbr-host). With `backup-standby=y`, the primary only handles the backup checkpoint start/stop — all data files are read from a standby via SSH. Backups go to S3 with compression (22.9MB → 3MB).

---

## Scenario 8 — Cluster Health Monitoring
**[→ Full details](scenario8-monitoring/README.md)**

Full observability check across all layers: Patroni (`patronictl list`, REST API), etcd (health + leader lock), HAProxy (stats page), PostgreSQL replication lag (`pg_stat_replication`), and VIP location (`ip addr show enX0`).

> In production, these checks feed into Prometheus/Grafana via `postgres_exporter` and `patroni_exporter`.
