# Xray transparent proxy Docker Image

Containerized transparent proxy xray service intended to be used as a l4 router between multiple gateways. 

## Example

Let's say our goal is to route some containerized openconnect network between 2 gateways: host's default gateway and a Tailscale node.

Our docker-compose.yml would then look something like this:

```yml
services:
  xray-tproxy:
    image: ghcr.io/manndarinchik/xray-tproxy-docker:latest
    restart: unless-stopped
    environment:
      # Secondary gateways: fwmark:gateway_ip pairs
      - SECONDARY_GATEWAYS=1:172.19.0.9
      # Optional overrides
      - TPROXY_PORT=2500
      - TPROXY_OUTPUT_MARK=200
    volumes:
      - ./config.json:/usr/local/etc/xray/config.json:ro
      - ./geoip.dat:/usr/local/share/xray/geoip.dat:ro
      - ./geosite.dat:/usr/local/share/xray/geosite.dat:ro
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.rp_filter=2
      - net.ipv4.conf.all.route_localnet=1
      - net.ipv4.ip_nonlocal_bind=1
    networks:
      proxynet:
        ipv4_address: 172.19.0.10

  ocserv-primary:
    image: ocserv-server:latest 
    restart: unless-stopped
    cap_add:
      - NET_ADMIN    
    devices:
      - /dev/net/tun:/dev/net/tun
    volumes:
      - ./ocserv.conf:/etc/ocserv/ocserv.conf
      - /root/ssl:/ssl:ro
    network_mode: service:xray-tproxy

  tailscale:
    image: tailscale/tailscale:latest
    environment:
      - TS_AUTHKEY=<tskey-YOUR-AUTH-KEY>
      - TS_STATE_DIR=/var/lib/tailscale
    volumes:
      - ./tailscale-state:/var/lib/tailscale
    cap_add:
      - net_admin
      - net_raw
    restart: unless-stopped
    networks:
      proxynet:
        ipv4_address: 172.19.0.9

networks:
  proxynet:
    driver: bridge
    ipam:
      config:
        - subnet: 172.19.0.0/24
```

Xray configuration would include fwmarks that we specified in SECONDARY_GATEWAYS env variable for the xray tproxy service:

```json
{
  // ...
  "inbounds": [  
    {
      "port": 2500,    
      "listen": "0.0.0.0",
      "protocol": "dokodemo-door",
      "settings": {
        "network": "tcp,udp",
        "followRedirect": true
      },
      "sniffing": {
        "enabled": true,
        "routeOnly": true,
        "destOverride": ["http","tls","quic"]
      },
      "streamSettings": {
        "sockopt": {"tproxy": "tproxy"}
      },
      "tag": "tproxy"
    }
  ],
  // ...
  "outbounds": [  
    {
        "tag": "proxy",
        "protocol": "freedom",
        "settings": {},
        "streamSettings": {
            "sockopt": {"mark": 1}
        }
    },
    {
        "tag": "direct",
        "protocol": "freedom",
        "settings": {},
        "streamSettings": {
            "sockopt": {"mark": 200}
        }
    }
  ]
    // ...
}
```

You can also attach xray-tproxy to host's network namespace to proxy its local network instead of docker network.