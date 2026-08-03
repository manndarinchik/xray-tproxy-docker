#!/bin/bash
set -e

# Default values
TPROXY_PORT="${TPROXY_PORT:-2500}"
TPROXY_OUTPUT_MARK="${TPROXY_OUTPUT_MARK:-200}"

# Local networks to exclude
EXCLUDE_NETS_V4="10.0.0.0/8,100.64.0.0/10,127.0.0.0/8,172.16.0.0/12,169.254.0.0/16,192.168.0.0/16"
EXCLUDE_NETS_V6="::1/128,fe80::/10,fc00::/7,ff00::/8"

# Parse SECONDARY_GATEWAYS env var (format: "1:172.19.0.9,2:172.19.0.10")
SECONDARY_GATEWAYS="${SECONDARY_GATEWAYS:-}"

# Build a list of exit fwmarks to avoid traffic re-entering tproxy
TPROXY_EXIT_LIST="$TPROXY_OUTPUT_MARK"
# Build a list of gateway IP addresses to avoid their exit traffic re-entering tproxy
GATEWAY_LIST=""
if [ -n "$SECONDARY_GATEWAYS" ]; then
    # Parse comma-separated fwmark:gateway pairs
    IFS=',' read -ra GATEWAY_PAIRS <<< "$SECONDARY_GATEWAYS"
    for pair in "${GATEWAY_PAIRS[@]}"; do
        fwmark="${pair%%:*}"
        gateway="${pair#*:}"
        TPROXY_EXIT_LIST="$TPROXY_EXIT_LIST, $fwmark"
        GATEWAY_LIST="$GATEWAY_LIST, $gateway"
    done
fi
if [ -n "$GATEWAY_LIST" ]; then
    GATEWAY_LIST="${GATEWAY_LIST:2}"
fi

# Generate nftables.conf
cat > /nftables.conf << EOF
#!/usr/sbin/nft -f

# Flush table
table inet transparentproxy 
delete table inet transparentproxy 

table inet transparentproxy {
    # Divert forwaded traffic to xray
    chain tproxy-prerouting {
        type filter hook prerouting priority filter; policy accept;
        # skip whitelist
        ip daddr { $EXCLUDE_NETS_V4 } return
        ip6 daddr { $EXCLUDE_NETS_V6 } return
        # Divert gateway traffic from re-entering proxy
        ip saddr { $GATEWAY_LIST } return
        ip daddr { $GATEWAY_LIST } return
        # skip direct traffic returned from tproxy
        meta mark { $TPROXY_EXIT_LIST } return
        # send to tproxy
        meta l4proto { tcp, udp } meta mark set 100 tproxy ip to 127.0.0.1:$TPROXY_PORT accept
        meta l4proto { tcp, udp } meta mark set 100 tproxy ip6 to [::1]:$TPROXY_PORT accept
    }

    # Divert locally generated outgoing traffic to xray
    chain tproxy-output {
        type route hook output priority filter; policy accept;
        # skip white list
        ip daddr { $EXCLUDE_NETS_V4 } return
        ip6 daddr { $EXCLUDE_NETS_V6 } return
        # skip direct traffic returned from tproxy
        meta mark { $TPROXY_EXIT_LIST } return
        # send to tproxy
        meta l4proto { tcp, udp } meta mark 0 meta mark set 100 accept
    }
}
EOF

cleanup() {
    echo "Received exit signal, running cleanup..."
    /bin/bash /ip_setup.sh --delete
}

trap cleanup EXIT SIGINT SIGTERM SIGHUP TERM INT

# Execute nftables and IP setup
if [ -f /nftables.conf ]; then
    echo "Creating nft table inet transparentproxy..."
    nft -f /nftables.conf
fi

if [ -f /ip_setup.sh ]; then
    echo "Applying IP routing rules..."
    /bin/bash /ip_setup.sh
fi

echo "Starting Xray..."
"$@" &
MAIN_PID=$!
wait $MAIN_PID
cleanup