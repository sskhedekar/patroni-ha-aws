# Setup Guide — Patroni HA Cluster on AWS

## Stack
- Ubuntu 24.04 LTS — EC2 t3.small (2GB RAM), 20GB gp3
- PostgreSQL 17 (PGDG repo)
- etcd v3.5.21
- Patroni 4.1.3
- HAProxy
- Keepalived + AWS CLI v2
- pgBackRest 2.58.0 (dedicated repo host, t3.micro)

---

## AWS Infrastructure

### EC2 Instances

| Node | Role | Private IP | Type |
|---|---|---|---|
| pg-node-1 | PostgreSQL + Patroni + etcd + HAProxy | 10.0.0.10 | t3.small |
| pg-node-2 | PostgreSQL + Patroni + etcd + HAProxy | 10.0.0.11 | t3.small |
| pg-node-3 | PostgreSQL + Patroni + etcd + HAProxy | 10.0.0.12 | t3.small |
| pgbr-host | pgBackRest repository host | 10.0.0.20 | t3.micro |

VIP: `10.0.0.100` — secondary private IP managed by Keepalived

### Security Group Inbound Rules

| Port | Source | Purpose |
|---|---|---|
| 22 | Your IP + 10.0.0.0/24 | SSH (10.0.0.0/24 for pgbr-host → PG nodes) |
| 2379/2380 | VPC CIDR | etcd client/peer |
| 5432 | VPC CIDR | PostgreSQL |
| 8008 | VPC CIDR | Patroni REST API |
| 5000/5001/7000 | 0.0.0.0/0 | HAProxy ports |

### EC2 Instance Launch

**PG nodes (pg-node-1, pg-node-2, pg-node-3) — launch 3 instances:**
- AMI: Ubuntu 24.04 LTS
- Type: t3.small
- Storage: 20GB gp3
- VPC: `pg-cluster-vpc`, Subnet: `pg-cluster-subnet`
- Private IP: set manually — 10.0.0.10, 10.0.0.11, 10.0.0.12
- Key pair: `pg-cluster-key`
- Security group: `pg-cluster-sg`
- IAM role: `pg-cluster-vip-role`

**pgbr-host — launch 1 instance:**
- AMI: Ubuntu 24.04 LTS
- Type: t3.micro
- Storage: 8GB gp3
- VPC: `pg-cluster-vpc`, Subnet: `pg-cluster-subnet`
- Private IP: set manually — 10.0.0.20
- Key pair: `pg-cluster-key`
- Security group: `pg-cluster-sg`
- IAM role: `pg-cluster-vip-role`

**Assign Elastic IPs — for each instance:**
1. EC2 → Elastic IPs → Allocate Elastic IP → Allocate
2. Select allocated IP → Actions → Associate → select instance → Associate

**Attach IAM role (if not set at launch):**
EC2 → Instances → select instance → Actions → Security → Modify IAM role → select `pg-cluster-vip-role` → Save

**VIP secondary IP (pg-node-1 only):**
EC2 → Network Interfaces → select pg-node-1's ENI → Actions → Manage IP addresses → Add `10.0.0.100` as secondary IP

### IAM Role (`pg-cluster-vip-role`) — attach to all 4 instances

**VIP management policy:**
```json
{
  "Effect": "Allow",
  "Action": ["ec2:AssignPrivateIpAddresses","ec2:DescribeNetworkInterfaces"],
  "Resource": "*"
}
```

**pgBackRest S3 policy:**
```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket","s3:GetBucketLocation"],
  "Resource": ["arn:aws:s3:::pg-cluster-pgbackrest","arn:aws:s3:::pg-cluster-pgbackrest/*"]
}
```

### S3 and VPC

- S3 bucket: `pg-cluster-pgbackrest` — ap-south-1, SSE-S3, block all public access
- VPC Gateway Endpoint for S3 — free, keeps backup traffic private

---

## Phase 1 — OS Prep (all 3 PG nodes)

```bash
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y curl wget gnupg2 lsb-release apt-transport-https \
    ca-certificates software-properties-common net-tools awscli

sudo hostnamectl set-hostname pg-node-1   # pg-node-2, pg-node-3 on respective nodes

sudo tee -a /etc/hosts <<EOF
10.0.0.10 pg-node-1
10.0.0.11 pg-node-2
10.0.0.12 pg-node-3
EOF

sudo swapoff -a && sudo sed -i '/swap/d' /etc/fstab
```

---

## Phase 2 — etcd (all 3 PG nodes)

```bash
ETCD_VERSION="v3.5.21"
cd /tmp
wget https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz
tar xzf etcd-${ETCD_VERSION}-linux-amd64.tar.gz
sudo mv etcd-${ETCD_VERSION}-linux-amd64/etcd /usr/local/bin/
sudo mv etcd-${ETCD_VERSION}-linux-amd64/etcdctl /usr/local/bin/

sudo useradd --system --no-create-home --shell /bin/false etcd
sudo mkdir -p /var/lib/etcd && sudo chown etcd:etcd /var/lib/etcd && sudo chmod 700 /var/lib/etcd
```

Create `/etc/systemd/system/etcd.service` with node-specific IPs (listen/advertise URLs). Start all 3 nodes simultaneously — they must form quorum together.

```bash
sudo systemctl daemon-reload && sudo systemctl enable etcd && sudo systemctl start etcd
etcdctl --endpoints=http://10.0.0.10:2379,http://10.0.0.11:2379,http://10.0.0.12:2379 endpoint health
```

---

## Phase 3 — PostgreSQL 17 (all 3 PG nodes)

```bash
sudo apt install -y postgresql-common
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
sudo apt install -y postgresql-17 postgresql-client-17

# Patroni manages PostgreSQL — stop and mask the native service
sudo systemctl stop postgresql
sudo systemctl disable postgresql
sudo systemctl mask postgresql@17-main

# Clear auto-created data dir — Patroni runs its own initdb
sudo -u postgres find /var/lib/postgresql/17/main -mindepth 1 -delete
```

---

## Phase 4 — Patroni (all 3 PG nodes)

```bash
sudo add-apt-repository universe -y && sudo apt update
sudo apt install -y patroni python3-etcd3
```

Create `/etc/patroni/patroni.yml` (node-specific IPs):

```yaml
scope: pg-cluster
name: pg-node-1

etcd3:
  hosts: 10.0.0.10:2379,10.0.0.11:2379,10.0.0.12:2379

restapi:
  listen: 10.0.0.10:8008
  connect_address: 10.0.0.10:8008

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        max_connections: 100
        max_wal_senders: 10
        max_replication_slots: 10
        wal_log_hints: "on"
        archive_mode: "on"
        archive_command: "pgbackrest --stanza=pg-cluster archive-push %p"
  initdb:
    - encoding: UTF8
    - data-checksums
  pg_hba:
    - host replication replicator 0.0.0.0/0 md5
    - host all all 0.0.0.0/0 md5

postgresql:
  listen: 10.0.0.10:5432
  connect_address: 10.0.0.10:5432
  data_dir: /var/lib/postgresql/17/main
  bin_dir: /usr/lib/postgresql/17/bin
  authentication:
    replication:
      username: replicator
      password: <replication-password>
    superuser:
      username: postgres
      password: <superuser-password>
    rewind:
      username: rewind_user
      password: <rewind-password>
  parameters:
    unix_socket_directories: '/var/run/postgresql'
```

```bash
sudo chown postgres:postgres /etc/patroni/patroni.yml && sudo chmod 600 /etc/patroni/patroni.yml
sudo systemctl enable patroni && sudo systemctl start patroni
```

> **Important:** Start pg-node-1 first. Wait for it to initialise and become primary before starting pg-node-2 and pg-node-3. Starting all 3 simultaneously causes a bootstrap race — only one node can initialise the cluster.

**Verify pg-node-1 is primary before proceeding:**
```bash
sudo -u postgres patronictl -c /etc/patroni/patroni.yml list
# Wait until pg-node-1 shows: Role=Leader, State=running
# This typically takes 15-30 seconds
```

**Then start pg-node-2 and pg-node-3** — they will join as replicas automatically:
```bash
sudo systemctl enable patroni && sudo systemctl start patroni  # on pg-node-2 and pg-node-3
```

**Verify all 3 nodes:**
```bash
sudo -u postgres patronictl -c /etc/patroni/patroni.yml list
# Expected: pg-node-1 Leader, pg-node-2 and pg-node-3 Replica | streaming | lag=0
```

---

## Phase 5 — HAProxy (all 3 PG nodes)

```bash
sudo apt install -y haproxy
```

`/etc/haproxy/haproxy.cfg`:

```
global
    maxconn 100

defaults
    mode tcp
    timeout connect 10s
    timeout client 30s
    timeout server 30s

frontend pgsql_primary
    bind *:5000
    default_backend pgsql_primary_backend

backend pgsql_primary_backend
    option httpchk GET /primary
    http-check expect status 200
    server pg-node-1 10.0.0.10:5432 check port 8008 inter 3s fall 3 rise 2
    server pg-node-2 10.0.0.11:5432 check port 8008 inter 3s fall 3 rise 2
    server pg-node-3 10.0.0.12:5432 check port 8008 inter 3s fall 3 rise 2

frontend pgsql_replicas
    bind *:5001
    default_backend pgsql_replica_backend

backend pgsql_replica_backend
    balance roundrobin
    option httpchk GET /replica
    http-check expect status 200
    server pg-node-1 10.0.0.10:5432 check port 8008 inter 3s fall 3 rise 2
    server pg-node-2 10.0.0.11:5432 check port 8008 inter 3s fall 3 rise 2
    server pg-node-3 10.0.0.12:5432 check port 8008 inter 3s fall 3 rise 2

frontend stats
    bind *:7000
    mode http
    stats enable
    stats uri /
```

```bash
sudo systemctl enable haproxy && sudo systemctl start haproxy
```

---

## Phase 6 — Keepalived + VIP (all 3 PG nodes)

```bash
sudo apt install -y keepalived
```

**AWS prerequisite:** Assign `10.0.0.100` as a secondary private IP to pg-node-1's ENI in EC2 console.

Create `/etc/keepalived/notify.sh` — uses AWS CLI + IMDS to reassign the VIP secondary IP to the new MASTER's ENI on state change.

`/etc/keepalived/keepalived.conf` — node-specific:
- `interface enX0` (EC2 Nitro — not eth0)
- Unicast VRRP (AWS blocks multicast)
- Priorities: pg-node-1=101, pg-node-2=100, pg-node-3=99
- `nopreempt` on all nodes

```bash
sudo systemctl enable keepalived && sudo systemctl start keepalived
ip addr show enX0 | grep 10.0.0.100  # should appear on pg-node-1
```

---

## Phase 7 — pgBackRest (pgbr-host + all 3 PG nodes)

### pgbr-host

```bash
# Add PGDG repo (must match version on PG nodes)
sudo apt install -y curl ca-certificates
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail \
    https://www.postgresql.org/media/keys/ACCC4CF8.asc
sudo sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
    https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list'
sudo apt update && sudo apt install -y pgbackrest

# SSH key for postgres user → PG nodes
sudo -u postgres ssh-keygen -t rsa -b 4096 -f /var/lib/postgresql/.ssh/id_rsa -N ""
# Copy public key to /var/lib/postgresql/.ssh/authorized_keys on all 3 PG nodes
```

`/etc/pgbackrest/pgbackrest.conf` on pgbr-host:
```ini
[global]
repo1-type=s3
repo1-s3-bucket=pg-cluster-pgbackrest
repo1-s3-region=ap-south-1
repo1-s3-endpoint=s3.ap-south-1.amazonaws.com
repo1-s3-uri-style=host
repo1-s3-key-type=auto
repo1-path=/pgbackrest
repo1-retention-full=2
backup-standby=y
log-level-console=info
log-level-file=detail
log-path=/var/log/pgbackrest

[pg-cluster]
pg1-host=10.0.0.11
pg1-host-user=postgres
pg1-path=/var/lib/postgresql/17/main
pg1-port=5432
pg2-host=10.0.0.10
pg2-host-user=postgres
pg2-path=/var/lib/postgresql/17/main
pg2-port=5432
pg3-host=10.0.0.12
pg3-host-user=postgres
pg3-path=/var/lib/postgresql/17/main
pg3-port=5432
```

### All 3 PG nodes

```bash
sudo apt install -y pgbackrest
sudo mkdir -p /var/log/pgbackrest && sudo chown postgres:postgres /var/log/pgbackrest
```

`/etc/pgbackrest/pgbackrest.conf` on each PG node:
```ini
[global]
repo1-type=s3
repo1-s3-bucket=pg-cluster-pgbackrest
repo1-s3-region=ap-south-1
repo1-s3-endpoint=s3.ap-south-1.amazonaws.com
repo1-s3-uri-style=host
repo1-s3-key-type=auto
repo1-path=/pgbackrest
log-level-console=info
log-level-file=detail
log-path=/var/log/pgbackrest

[pg-cluster]
pg1-path=/var/lib/postgresql/17/main
pg1-port=5432
```

### Initialize (on pgbr-host)

```bash
sudo mkdir -p /var/log/pgbackrest && sudo chown postgres:postgres /var/log/pgbackrest
sudo -u postgres pgbackrest --stanza=pg-cluster stanza-create
sudo -u postgres pgbackrest --stanza=pg-cluster check
sudo -u postgres pgbackrest --stanza=pg-cluster backup --type=full
sudo -u postgres pgbackrest --stanza=pg-cluster info
```

---

## Verify Full Stack

```bash
sudo -u postgres patronictl -c /etc/patroni/patroni.yml list
psql -h 10.0.0.100 -p 5000 -U postgres -c "SELECT inet_server_addr();"
psql -h 10.0.0.100 -p 5001 -U postgres -c "SELECT pg_is_in_recovery(), inet_server_addr();"
etcdctl --endpoints=http://10.0.0.10:2379,http://10.0.0.11:2379,http://10.0.0.12:2379 endpoint health
ip addr show enX0 | grep 10.0.0.100
sudo -u postgres pgbackrest --stanza=pg-cluster info
```
