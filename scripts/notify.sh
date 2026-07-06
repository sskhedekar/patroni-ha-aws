#!/bin/bash
# Keepalived notify script — called automatically on every VRRP state change.
# Place on all 3 PG nodes at: /etc/keepalived/notify.sh
# chmod +x /etc/keepalived/notify.sh
#
# MASTER: moves VIP to this node's ENI via AWS API, adds IP to OS interface
# BACKUP/FAULT: removes VIP from OS interface (AWS-level handled by new MASTER)

ROLE=$1
VIP="10.0.0.100"

# All dynamic values fetched from EC2 instance metadata — nothing hardcoded
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
MAC=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/network/interfaces/macs/)
ENI_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/network/interfaces/macs/${MAC}/interface-id)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/placement/region)
IFACE=$(ip -o link | grep -i "${MAC%/}" | awk '{print $2}' | tr -d ':')

if [ "$ROLE" = "MASTER" ]; then
    aws ec2 assign-private-ip-addresses \
        --network-interface-id $ENI_ID \
        --private-ip-addresses $VIP \
        --allow-reassignment \
        --region $REGION
    ip addr add $VIP/24 dev $IFACE 2>/dev/null || true
fi

if [ "$ROLE" = "BACKUP" ] || [ "$ROLE" = "FAULT" ]; then
    ip addr del $VIP/24 dev $IFACE 2>/dev/null || true
fi
