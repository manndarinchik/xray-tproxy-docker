#!/bin/bash

DELETE_MODE=false
for arg in "$@"; do
    case $arg in
        --delete)
            DELETE_MODE=true
            shift
            ;;
    esac
done
if [ "$DELETE_MODE" = true ]; then
    set +e
else
    set -e
fi

SECONDARY_GATEWAYS="${SECONDARY_GATEWAYS:-}"

if [ "$DELETE_MODE" = false ]; then
    # Create route to tproxy
    ip route add local 0.0.0.0/0 dev lo table 100
    ip rule add fwmark 100 lookup 100
    ip -6 route add local ::/0 dev lo table 106
    ip -6 rule add fwmark 100 lookup 106

    # Create routes to secondary gateways
    if [ -n "$SECONDARY_GATEWAYS" ]; then
        IFS=',' read -ra GATEWAY_PAIRS <<< "$SECONDARY_GATEWAYS"
        for pair in "${GATEWAY_PAIRS[@]}"; do
            fwmark="${pair%%:*}"
            gateway="${pair#*:}"
            table_id=$((200 + fwmark))  # Use unique table ID for each fwmark
            
            ip route add default via "$gateway" table "$table_id"
            ip rule add fwmark "$fwmark" lookup "$table_id"
            
            echo "Added route: fwmark $fwmark -> gateway $gateway (table $table_id)"
        done
    fi
else
    # Delete route to tproxy
    ip rule del fwmark 100 lookup 100 2>/dev/null
    ip route del local 0.0.0.0/0 dev lo table 100 2>/dev/null
    ip -6 rule del fwmark 100 lookup 106 2>/dev/null
    ip -6 route del local ::/0 dev lo table 106 2>/dev/null

    # Delete routes to secondary gateways
    if [ -n "$SECONDARY_GATEWAYS" ]; then
        IFS=',' read -ra GATEWAY_PAIRS <<< "$SECONDARY_GATEWAYS"
        for pair in "${GATEWAY_PAIRS[@]}"; do
            fwmark="${pair%%:*}"
            gateway="${pair#*:}"
            table_id=$((200 + fwmark))
            
            ip route del default via "$gateway" table "$table_id" 2>/dev/null
            ip rule del fwmark "$fwmark" lookup "$table_id" 2>/dev/null
            
            echo "Deleted route: fwmark $fwmark -> gateway $gateway (table $table_id)"
        done
    fi
fi