#!/bin/bash
# Simulates application traffic — continuous reads and writes via VIP
# Run this while practising manual failover commands in another terminal
# Credentials via ~/.pgpass — no passwords in this script

export PGCONNECT_TIMEOUT=5
VIP="10.0.0.100"
PGUSER="postgres"

# Create table if not exists
psql -h $VIP -p 5000 -U $PGUSER -c "
  CREATE TABLE IF NOT EXISTS app_traffic (
    id     serial PRIMARY KEY,
    ts     timestamptz DEFAULT now(),
    server text
  );" 2>/dev/null

echo ""
echo "  App traffic running — Ctrl+C to stop"
echo "  WRITE → 10.0.0.100:5000 (primary)"
echo "  READ  → 10.0.0.100:5001 (replica)"
echo ""
printf "%-10s %-12s %-18s %-18s\n" "TIME" "STATUS" "WRITE(primary)" "READ(replica)"
echo "----------------------------------------------------------------"

while true; do
    WRITE_OUT=$(psql -h $VIP -p 5000 -U $PGUSER -t -A -v ON_ERROR_STOP=1 -c \
        "INSERT INTO app_traffic(server) VALUES (host(inet_server_addr())) RETURNING server;" 2>&1)
    WOK=$?
    WRITE=$(echo "$WRITE_OUT" | grep -v "^INSERT")

    READ=$(psql -h $VIP -p 5001 -U $PGUSER -t -A -v ON_ERROR_STOP=1 -c \
        "SELECT host(inet_server_addr());" 2>&1)
    ROK=$?

    NOW=$(date '+%H:%M:%S')

    if   [ $WOK -eq 0 ] && [ $ROK -eq 0 ]; then
        printf "%-10s %-12s %-18s %-18s\n" "$NOW" "OK" "$WRITE" "$READ"
    elif [ $WOK -ne 0 ] && [ $ROK -eq 0 ]; then
        printf "%-10s %-12s %-18s %-18s\n" "$NOW" "WRITE-FAIL" "---" "$READ"
    elif [ $WOK -eq 0 ] && [ $ROK -ne 0 ]; then
        printf "%-10s %-12s %-18s %-18s\n" "$NOW" "READ-FAIL" "$WRITE" "---"
    else
        printf "%-10s %-12s %-18s %-18s\n" "$NOW" "BOTH-FAIL" "---" "---"
    fi

    sleep 2
done
