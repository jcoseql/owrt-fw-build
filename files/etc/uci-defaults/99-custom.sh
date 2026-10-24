#!/bin/sh
# ============================================================
# 首启脚本 (自建版, 极简): 仅设置 LAN 管理地址。
# 原则: 不放开 WAN 入站 / 不改 ttyd·dropbear 监听 / 不拉第三方仓库。
# 管理 IP 来源: /etc/config/custom_router_ip.txt (由 CI 构建时写入)
# ============================================================
IP_FILE="/etc/config/custom_router_ip.txt"
LOGFILE="/etc/config/uci-defaults-log.txt"
{
  echo "Starting 99-custom.sh at $(date)"
  if [ -f "$IP_FILE" ]; then
    IP=$(cat "$IP_FILE")
    uci -q delete network.lan.ipaddr
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr="$IP"
    uci set network.lan.netmask='255.255.255.0'
    uci commit network
    echo "lan.ipaddr -> $IP"
  else
    echo "no custom_router_ip.txt, keep default lan ip"
  fi

  # ----- Tailnet 入向:tailscale0 必须挂在某个 zone 上 -----
  # 缺这一行时,从 tailnet 进来的包匹配不到任何 zone → 落 fw4 默认 drop:
  # tailnet 到本机的 22/80/ICMP 全被丢,但 `tailscale ping` 仍通(tailscaled
  # 自己应答,不经 fw4),极易误判成"网络正常"。2026-10-23 R3S 实锤。
  if [ "$(uci -q get firewall.@zone[0].name)" = "lan" ]; then
    if uci -q get firewall.@zone[0].device 2>/dev/null | grep -qx 'tailscale0'; then
      echo "firewall: tailscale0 already in lan zone"
    else
      uci add_list firewall.@zone[0].device='tailscale0'
      uci commit firewall
      echo "firewall: tailscale0 -> lan zone"
    fi
  else
    echo "firewall: zone[0] is not lan, skipped tailscale0 binding"
  fi
} >>"$LOGFILE" 2>&1
exit 0
