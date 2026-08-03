# Xray transparent proxy Docker Image

Containerized transparent proxy xray service intended to be used as a l4 router between multiple gateways. This container is intended to be attached to host's network to create necessary nftables rules and ip routes on start, as well as to remove them on stop.

## Example

Let's say our goal is to do l4 routing between 2 headscale tailents.

docker-compose.yml would then look something like this:

```yml
services:
  xray-tproxy:
    image: ghcr.io/manndarinchik/xray-tproxy-docker:latest
    container_name: xray
    restart: unless-stopped
    environment:
      - SECONDARY_GATEWAYS=1:172.19.0.9
      # Optional overrides
      - TPROXY_PORT=2500
      - TPROXY_OUTPUT_MARK=200
    volumes:
      - ./xray.json:/usr/local/etc/xray/config.json:ro
    cap_add:
      - NET_ADMIN
    network_mode: "host"
    depends_on:
      - tailscaled-awg

# Don't forget to add these to host's sysctl.conf:
# net.ipv4.ip_forward=1
# net.ipv4.conf.all.rp_filter=2
# net.ipv4.conf.all.route_localnet=1
# net.ipv4.ip_nonlocal_bind=1
# net.ipv6.ip_forward=1
# net.ipv6.conf.all.rp_filter=2
# net.ipv6.conf.all.route_localnet=1
# net.ipv6.ip_nonlocal_bind=1

  tailscaled:
    image: tailscale/tailscale:latest
    container_name: tailscaled
    hostname: ${NODENAME}
    environment:
      - TS_AUTHKEY=${WG_AUTHKEY}
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_EXTRA_ARGS=${LOGIN_SERVER:+--login-server=${LOGIN_SERVER}}
      - TS_TAILSCALED_EXTRA_ARGS=--socket=/var/run/tailscale/tailscaled.sock
    volumes:
      - wgstate:/var/lib/tailscale
    cap_add:
      - NET_ADMIN
      - NET_RAW
    restart: unless-stopped
    networks:
      proxynet:
        ipv4_address: 172.19.0.10

  tailscaled-awg:
    image: ltlei/tailscale-awg:latest
    container_name: tailscaled-awg
    hostname: ${NODENAME}-awg
    environment:
      - TS_AUTHKEY=${AWG_AUTHKEY}
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_EXTRA_ARGS=${LOGIN_SERVER:+--login-server=${LOGIN_SERVER}}
      - TS_TAILSCALED_EXTRA_ARGS=--socket=/var/run/tailscale/tailscaled.sock
    volumes:
      - awgstate:/var/lib/tailscale
    cap_add:
      - NET_ADMIN
      - NET_RAW
    restart: unless-stopped
    networks:
      proxynet:
        ipv4_address: 172.19.0.9

volumes:
  awgstate:
  wgstate:   

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