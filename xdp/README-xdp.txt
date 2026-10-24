XDP 试装件 —— /root/xdp/
==================================================
内容:
  xdp_pass.c    源码（恒 PASS 的最小 XDP 程序，零扰动）
  xdp_pass.o    编译产物（构建时由 clang -O2 -target bpf 生成）
  本文件        使用说明

两种挂法（先试 native，不行退 skb）:
  xdp-loader load -m native ethX /root/xdp/xdp_pass.o
  xdp-loader load -m skb    ethX /root/xdp/xdp_pass.o
  # 等价 ip 写法:
  ip -force link set dev ethX xdpdrv     obj /root/xdp/xdp_pass.o sec xdp   # native
  ip -force link set dev ethX xdpgeneric obj /root/xdp/xdp_pass.o sec xdp   # skb

口位支持速查（认驱动，不认机型）:
  SoC 原生 GMAC（stmmac / rk_gmac-dwmac 系）→ 可 native: R3S eth0(WAN) / R4S end0 / H28K 一口 …
  Realtek PCIe（RTL8111 / RTL8125 / RTL8168）→ 仅 skb : E52C 两口 / R3S eth1 …
  速判: 直接试挂 native，成功即支持（不支持会明确报错）

查看:
  xdp-loader status             # Mode 列: native / skb
  bpftool net                   # driver id = native; skb id = generic
  ip -d link show dev ethX      # prog/xdp = native; prog/xdpgeneric = generic

卸载:
  xdp-loader unload --all ethX
  # 或: ip link set dev ethX xdp off

随手工具:
  xdp-filter load ethX          # 轻量过滤（例: xdp-filter port 22）
  xdpdump -D ethX               # XDP 层抓包

注意:
  * 两种模式丢弃的包对本机 conntrack/tcpdump 都不可见；native 更早（无 skb 开销）
  * XDP 位于 tc/iptables 之前；与 dae（tc eBPF 透明代理）可共存（R3S 已实测）
  * 开机自动挂（2026-10-13 起）: 本固件 /etc/rc.local 已内置固化块——等 WAN 就绪（PPPoE: pppoe-wan；DHCP: eth0）再稳 5s，自动挂 eth0 native。撤 = 删 /etc/rc.local 中的块；手动重挂/卸载照常。
  * 为何等 WAN 才挂: attach 撞链路收敛窗口会致数据面半死（PPPoE PADO timeout）——2026-10-13 在 R3S 实锤修复（细节见 rc.local 块注释）。
