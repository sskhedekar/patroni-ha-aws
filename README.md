# Patroni HA Cluster on AWS EC2

A fully manual setup of a 3-node PostgreSQL High Availability cluster on AWS EC2, built from scratch without automation tools. Every component was installed, configured, and verified by hand.

> Built as a hands-on learning exercise to deeply understand PostgreSQL HA internals — etcd leader election, WAL streaming replication, HAProxy health-check routing, Keepalived VIP management, and pgBackRest S3 backups.

---

## Stack

| Component | Version | Role |
|---|---|---|
| OS | Ubuntu 24.04 LTS | EC2 t3.small (2GB RAM) |
| PostgreSQL | 17 (PGDG) | Database engine |
| Patroni | 4.1.3 | HA orchestration, leader election |
| etcd | v3.5.21 | Distributed lock store |
| HAProxy | latest | TCP load balancer, health-check routing |
| Keepalived | latest | Virtual IP (VIP) management via VRRP |
| pgBackRest | 2.58.0 | S3 backup from standby (dedicated repo host) |

---

## Architecture

```
                        APPLICATION
                            |
                   WRITE    |    READ
                 (port 5000)|  (port 5001)
                            |
                ┌───────────▼───────────┐
                │   VIP: 10.0.0.100     │  ← Keepalived manages this
                │   (Floating IP)       │
                └───────────┬───────────┘
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
          ▼                 ▼                 ▼
  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐
  │   pg-node-1   │ │   pg-node-2   │ │   pg-node-3   │
  │  10.0.0.10    │ │  10.0.0.11    │ │  10.0.0.12    │
  │  HAProxy      │ │  HAProxy      │ │  HAProxy      │
  │  Patroni      │ │  Patroni      │ │  Patroni      │
  │  PG 17        │ │  PG 17        │ │  PG 17        │
  │  etcd         │ │  etcd         │ │  etcd         │
  │  Keepalived   │ │  Keepalived   │ │  Keepalived   │
  └───────────────┘ └───────────────┘ └───────────────┘
          ▲                 ▲                 ▲
          └─────────────────┴─────────────────┘
                     SSH (backup)
                          │
                ┌─────────▼─────────┐
                │   pgbr-host       │
                │   10.0.0.20       │──────► S3: pg-cluster-pgbackrest
                │   pgBackRest      │
                └───────────────────┘
```

**Write path:** App → VIP:5000 → HAProxy → Patroni `/primary` check → PostgreSQL PRIMARY
**Read path:** App → VIP:5001 → HAProxy → Patroni `/replica` check → PostgreSQL REPLICA (round-robin)

---

## Scenarios Tested

| # | Scenario | Tool | Downtime |
|---|---|---|---|
| 1 | [Planned Switchover](docs/scenarios/scenario1-switchover/README.md) | `patronictl switchover` | ~1-2s |
| 2 | [Auto-Failover](docs/scenarios/scenario2-autofailover/README.md) | `systemctl stop patroni` on primary | ~25-30s |
| 3 | [Pause / Resume](docs/scenarios/scenario3-pause/README.md) | `patronictl pause/resume` | None |
| 4 | [Parameter Change](docs/scenarios/scenario4-parameter-change/README.md) | `patronictl edit-config` + reload/restart | None / ~1-2s |
| 5 | [Extension Install](docs/scenarios/scenario5-extension/README.md) | `apt install` + `CREATE EXTENSION` | None / ~1-2s |
| 6 | [Force Rebuild Replica](docs/scenarios/scenario6-reinit/README.md) | `patronictl reinit` | None |
| 7 | [pgBackRest Backup to S3](docs/scenarios/scenario7-pgbackrest/README.md) | `pgbackrest backup --type=full` | None |
| 8 | [Cluster Health Monitoring](docs/scenarios/scenario8-monitoring/README.md) | Native tools — patronictl, curl, etcdctl | None |

---

## Traffic Simulation

[scripts/app-traffic.sh](scripts/app-traffic.sh) — continuous read/write traffic via VIP, showing real-time impact of each scenario:

```
TIME       STATUS       WRITE(primary)     READ(replica)
----------------------------------------------------------------
09:36:38   OK           10.0.0.12          10.0.0.10
09:36:40   WRITE-FAIL   ---                10.0.0.11     ← failover happening
09:36:58   OK           10.0.0.10          10.0.0.12     ← new primary
```

---

## Repository Structure

```
patroni-ha-cluster/
├── README.md
├── docs/
│   ├── setup-guide.md              # Concise setup from scratch
│   ├── architecture.md             # Detailed architecture diagrams
│   └── scenarios/
│       ├── scenario1-switchover/   # Planned switchover
│       ├── scenario2-autofailover/ # Auto-failover
│       ├── scenario3-pause/        # Pause/resume
│       ├── scenario4-parameter-change/  # Parameter tuning
│       ├── scenario5-extension/    # Extension installation
│       ├── scenario6-reinit/       # Force rebuild replica
│       ├── scenario7-pgbackrest/   # pgBackRest S3 backup
│       └── scenario8-monitoring/   # Cluster health monitoring
├── scripts/
│   └── app-traffic.sh
└── screenshots/                    # General cluster screenshots
```

---

## Key Lessons Learned

- **etcd is the single source of truth** — the leader lock at `/service/pg-cluster/leader` controls everything. Once a node writes its name there, all others follow unconditionally.
- **VIP and Patroni leader are independent** — Keepalived tracks HAProxy health, not Patroni leadership. A planned switchover does not move the VIP.
- **pg_rewind vs streaming** — a cleanly-stopped former primary rejoins via streaming if it had zero lag. pg_rewind is only needed when WAL has diverged.
- **`patronictl edit-config` is the right tool** — never edit `postgresql.conf` directly. Config goes to etcd, all nodes pick it up within 10 seconds.
- **pgBackRest dedicated repo host** — the production-correct architecture: repo host SSHes into PG nodes to read backup files; primary only handles checkpoint start/stop.
- **PostgreSQL timelines** — every leadership change increments the timeline number, stamped into WAL segment filenames. This is how replicas know where to start streaming after a failover.
