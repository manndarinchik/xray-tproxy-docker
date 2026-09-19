# Xray transparent proxy Docker Image

This is a transparent proxy xray service packaged into a docker container. It's intended to be attached to host's network to create necessary nftables rules and ip routes on start, as well as to remove them on stop.

Upon launch, the container does the following:
- creates nftable `transparentproxy` with `tproxy-prerouting` and `tproxy-output` chains
- creates ip rules and ip tables for each gateway specified

After finishing the container cleans up all created ip rules, ip tables and nftable specified above. 

Traffic that is routed via tproxy:
- LAN traffic forwarded though the host (from both physical and virtual interfaces - e.g. other docker networks )
- host's outgoing traffic 

Traffic that is not routed via tproxy:
- any traffic originating from `WHITELIST` (see below)
- any traffic originaring from or destined to each IP specified in `SECONDARY_GATEWAYS` (see below)
- traffic destined to reserved privite IP pools: 10.0.0.0/8,100.64.0.0/10,127.0.0.0/8,172.16.0.0/12,169.254.0.0/16,192.168.0.0/16,::1/128,fe80::/10,fc00::/7,ff00::/8
- inbound TCP traffic and statefull UDP traffic

## Usage

This container must be launched with the following env variables:
- `WHITELIST`: Comma-separated list of IPv4 address that should be whitelisted from entering tproxy. Set to entire docker network by default (172.17.0.0/16).
- `SECONDARY_GATEWAYS`: a comma-separated list of 'fwmark:ipv4_gateway_adress' pairs. Each pair is converted to corresponding ip rules and tables for policy-based routing on tproxy exit.

```yaml
services:
# Don't forget to add these to host's sysctl.conf:
# net.ipv4.ip_forward=1
# net.ipv4.conf.all.rp_filter=0
# net.ipv4.conf.all.route_localnet=1
# net.ipv4.ip_nonlocal_bind=1

  xray:
    image: ghcr.io/manndarinchik/xray-tproxy-docker:latest
    container_name: xray
    restart: always
    environment:
      - WHITELIST=172.19.0.0/24
      - SECONDARY_GATEWAYS=1:172.19.0.9
    volumes:
      - ./xray.json:/usr/local/etc/xray/config.json:ro
    cap_add:
      - NET_ADMIN
    network_mode: "host"
    depends_on:
      gateway1:
        condition: service_healthy
```

xray outbound configuration must have several "freedom" outbounds. One must be configured with `"sockopt": {"mark": 200}`, which is going to route traffic via hosts default gateway. Others should have fwmarks specified in the `SECONDARY_GATEWAYS` env variable - these outbounds will route traffic to ipv4 gateways corresponding to these fwmarks.

```json
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
```

## Example

TBA
