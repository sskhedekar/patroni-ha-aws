# Patroni HA Cluster — Architecture

## Overview

```
                        APPLICATION
                            |
                   WRITE    |    READ
                 (port 5000)|  (port 5001)
                            |
                ┌───────────▼───────────┐
                │   VIP: 10.0.0.100     │  ← Keepalived manages this
                │   (Floating IP)       │    Lives on one node at a time
                └───────────┬───────────┘
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
          ▼                 ▼                 ▼
  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐
  │   pg-node-1   │ │   pg-node-2   │ │   pg-node-3   │
  │  10.0.0.10    │ │  10.0.0.11    │ │  10.0.0.12    │
  │               │ │               │ │               │
  │  ┌─────────┐  │ │  ┌─────────┐  │ │  ┌─────────┐  │
  │  │ HAProxy │  │ │  │ HAProxy │  │ │  │ HAProxy │  │
  │  │:5000    │  │ │  │:5000    │  │ │  │:5000    │  │
  │  │:5001    │  │ │  │:5001    │  │ │  │:5001    │  │
  │  │:7000    │  │ │  │:7000    │  │ │  │:7000    │  │
  │  └────┬────┘  │ │  └────┬────┘  │ │  └────┬────┘  │
  │       │       │ │       │       │ │       │       │
  │  ┌────▼────┐  │ │  ┌────▼────┐  │ │  ┌────▼────┐  │
  │  │ Patroni │  │ │  │ Patroni │  │ │  │ Patroni │  │
  │  │ :8008   │  │ │  │ :8008   │  │ │  │ :8008   │  │
  │  └────┬────┘  │ │  └────┬────┘  │ │  └────┬────┘  │
  │       │       │ │       │       │ │       │       │
  │  ┌────▼────┐  │ │  ┌────▼────┐  │ │  ┌────▼────┐  │
  │  │  PG 17  │  │ │  │  PG 17  │  │ │  │  PG 17  │  │
  │  │ PRIMARY │  │ │  │ REPLICA │  │ │  │ REPLICA │  │
  │  │ :5432   │  │ │  │ :5432   │◄─┼─┼──│ :5432   │  │
  │  └─────────┘  │ │  └─────────┘  │ │  └─────────┘  │
  │       ▲       │ │       ▲       │ │               │
  │       └───────┼─┼───────┘       │ │               │
  │   WAL stream  │ │               │ │               │
  │               │ │               │ │               │
  │  ┌─────────┐  │ │  ┌─────────┐  │ │  ┌─────────┐  │
  │  │  etcd   │◄─┼─┼─►│  etcd   │◄─┼─┼─►│  etcd   │  │
  │  │  :2379  │  │ │  │  :2379  │  │ │  │  :2379  │  │
  │  │  :2380  │  │ │  │  :2380  │  │ │  │  :2380  │  │
  │  └─────────┘  │ │  └─────────┘  │ │  └─────────┘  │
  │               │ │               │ │               │
  │  ┌─────────┐  │ │  ┌─────────┐  │ │  ┌─────────┐  │
  │  │Keepalvd │  │ │  │Keepalvd │  │ │  │Keepalvd │  │
  │  │MASTER   │  │ │  │BACKUP   │  │ │  │BACKUP   │  │
  │  │prio=101 │  │ │  │prio=100 │  │ │  │prio=99  │  │
  │  └─────────┘  │ │  └─────────┘  │ │  └─────────┘  │
  └───────────────┘ └───────────────┘ └───────────────┘
          │                 │                 │
          │  archive_command (WAL push)        │
          └─────────────────┼─────────────────┘
                            │
                ┌───────────▼───────────┐
                │   pgbr-host           │
                │   10.0.0.20           │
                │   pgBackRest          │
                │   (repo host)         │
                └───────────┬───────────┘
                            │ SSH (reads backup files from standby)
                            │ writes backup + WAL
                            ▼
                ┌───────────────────────┐
                │   S3 Bucket           │
                │ pg-cluster-pgbackrest │
                │   ap-south-1          │
                │                       │
                │  /archive/ ← WAL      │
                │  /backup/  ← basebackup│
                └───────────────────────┘
```

---

## Traffic Flow

### Write path (port 5000)
```
App → VIP:5000 → HAProxy → HTTP GET /primary on :8008
                         → routes to node returning 200
                         → PostgreSQL PRIMARY :5432
```

### Read path (port 5001)
```
App → VIP:5001 → HAProxy → HTTP GET /replica on :8008
                         → round-robin across nodes returning 200
                         → PostgreSQL REPLICA :5432
```

### HAProxy health check logic
```
GET /primary  → 200 if node is Leader    (Patroni REST API)
GET /replica  → 200 if node is Replica   (Patroni REST API)
```

---

## Replication Flow

```
  pg-node-1 (PRIMARY)
       │
       │  WAL streaming
       ├──────────────────► pg-node-2 (REPLICA, lag=0)
       │
       └──────────────────► pg-node-3 (REPLICA, lag=0)
```

---

## Leader Election Flow (etcd)

```
  Patroni loop every 10s (loop_wait):

  Leader node:
    ├── Renew /service/pg-cluster/leader key in etcd (TTL=30s)
    └── "no action. I am (pg-node-X), the leader with the lock"

  Replica nodes:
    ├── Check /service/pg-cluster/leader key
    └── "no action. I am (pg-node-X), a secondary, following a leader (pg-node-Y)"

  On leader failure:
    ├── TTL expires (30s) → etcd deletes /service/pg-cluster/leader
    ├── All replicas race to write their name to the key
    ├── First to succeed → promotes to primary (new timeline)
    └── Others → follow the new leader via streaming replication
```

---

## VIP Management (Keepalived)

```
  Normal state:
    pg-node-1 → MASTER  (prio=101) → holds VIP 10.0.0.100
    pg-node-2 → BACKUP  (prio=100)
    pg-node-3 → BACKUP  (prio=99)

  VIP moves when:
    HAProxy on pg-node-1 goes down → Keepalived health check fails
    → pg-node-1 stops sending VRRP heartbeats
    → pg-node-2 wins VRRP election (highest remaining priority)
    → AWS CLI: assign 10.0.0.100 to pg-node-2's ENI
    → VIP now on pg-node-2

  VIP does NOT move during:
    Patroni switchover (HAProxy stays healthy on all nodes)
    patronictl pause/resume
    PostgreSQL restart (as long as HAProxy recovers within check interval)
```

---

## Port Reference

| Port | Service | Purpose |
|------|---------|---------|
| 2379 | etcd | Client API — Patroni reads/writes cluster state here |
| 2380 | etcd | Peer communication — etcd nodes sync with each other |
| 5432 | PostgreSQL | Direct database connections |
| 8008 | Patroni REST API | HAProxy health checks, patronictl, cluster status |
| 5000 | HAProxy | Write port → primary only |
| 5001 | HAProxy | Read port → replicas, round-robin |
| 7000 | HAProxy | Stats UI — `curl http://10.0.0.100:7000/` |

---

## pgBackRest — WAL Archiving Flow

WAL archiving runs continuously on the primary. Every WAL segment written by PostgreSQL is pushed to S3 via `archive_command`.

```
pg-node-X (current primary)
    │
    │  PostgreSQL writes WAL segment
    │  archive_command triggers:
    │  pgbackrest --stanza=pg-cluster archive-push %p
    │
    ▼
S3: pg-cluster-pgbackrest
    └── /pgbackrest/archive/pg-cluster/17-1/
            └── 000000050000000000000009-<hash>.gz  ← compressed WAL segment
```

- Runs on whichever node is the current primary
- If archiving fails, PostgreSQL holds WAL locally until it succeeds
- Provides continuous WAL for point-in-time recovery (PITR)

---

## pgBackRest — Backup Flow

Full backup with `backup-standby=y`. Primary only handles checkpoint start/stop — all data files are read from a standby by pgbr-host.

```
pgbr-host (10.0.0.20)
    │
    │  1. SSH → primary (pg-node-X)
    │     └── pg_backup_start() — signals PostgreSQL to start backup
    │
    │  2. Check standby lag — wait for standby to reach backup LSN
    │
    │  3. SSH → standby (pg-node-Y)
    │     └── read all data files (979 files, 22.9MB)
    │
    │  4. SSH → primary
    │     └── pg_backup_stop() — signals backup complete
    │
    │  5. Write compressed backup to S3
    │
    ▼
S3: pg-cluster-pgbackrest
    └── /pgbackrest/backup/pg-cluster/
            └── 20260530-111320F/       ← backup label (date-time + F=full)
                    ├── backup.manifest ← catalog, checksums
                    └── pg_data/        ← compressed data files (3MB)
```

**Why standby for backup:**
- Primary only handles checkpoint signals — no file I/O
- Backup load (disk reads, network) falls entirely on the standby
- Live write traffic on primary is completely unaffected

**Restore flow:**
```
New/recovered node
    │
    │  pgbackrest --stanza=pg-cluster --delta restore
    │  ├── reads backup.manifest from S3
    │  ├── downloads data files from S3
    │  └── replays WAL from S3 archive to reach consistent state
    │
    ▼
PostgreSQL starts in standby mode → connects to primary → streaming replication
```

---

## Cluster State After Each Scenario

```
Initial bootstrap:       Node1=Leader(TL=1),  Node2=Replica, Node3=Replica
After Scenario 1:        Node1=Replica,       Node2=Leader(TL=2), Node3=Replica
After Scenario 2:        Node1=Replica,       Node2=stopped,      Node3=Leader(TL=3)
After Node2 rejoin:      Node1=Replica,       Node2=Replica,      Node3=Leader(TL=3)
After Scenario 3/4/5:    Node1=Replica,       Node2=Replica,      Node3=Leader(TL=3)
```
