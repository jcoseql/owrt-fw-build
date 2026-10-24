#!/bin/bash
# ============================================================
# 构建后自检 (在 runner 上执行, cwd = 仓库根)
#   1) manifest 断言: 无 argon; 关键包在列 (docker/XDP 按开关条件断言; 非 XDP 断言零残留)
#   2) 解包 squashfs: 比对烘入件 sha256; 检查首启脚本 / rc.d / 无 config.dae
#   3) XDP 门控: 白名单硬件断言试装件在位 (ELF .o); 非白名单断言零残留
#   4) gost 门控: enable_gost=yes 断言 binary/init/uci/自启; no 断言零残留
# 与 imm 版差异: 上游 feed 无 vlmcsd / diskman, 相应断言已删
# ============================================================
set -euo pipefail
cd bin/targets/rockchip/armv8
IMG=$(ls *squashfs-sysupgrade.img.gz | head -1)
[ -n "$IMG" ] || { echo "❌ 未找到 squashfs-sysupgrade 镜像"; ls -la; exit 1; }
MAN=$(ls *.manifest | head -1)
if ls *ext4* >/dev/null 2>&1; then echo "❌ ext4 产物残留 (应为 squashfs-only):"; ls -la *ext4*; exit 1; fi
echo "✓ 无 ext4 产物 (squashfs-only)"
echo "IMG = $IMG"
echo "MAN = $MAN"
echo "ENABLE_XDP = ${ENABLE_XDP:-no}"

echo "== [1] manifest 断言 =="
if grep -qi "argon" "$MAN"; then echo "❌ manifest 残留 argon:"; grep -i argon "$MAN"; exit 1; fi
echo "✓ 无 argon"
for p in luci-app-upnp miniupnpd-nftables luci-i18n-ttyd-zh-cn openssh-sftp-server \
         tailscale btop ethtool kmod-sched-core kmod-sched-bpf kmod-veth kmod-tun; do
  grep -q "^${p} " "$MAN" || { echo "❌ 缺包: $p"; exit 1; }
done
echo "✓ 关键包在列 (upnp / ttyd-zh / sftp-server / tailscale / btop / ethtool / dae deps)"
if grep -q "^dae " "$MAN"; then echo "❌ 意外: manifest 里有 feed 版 dae 包 (本构建只用烘入二进制)"; exit 1; fi
echo "✓ 无 feed 版 dae 包 (纯烘入二进制)"
if [ "${ENABLE_XDP:-no}" = "yes" ]; then
  for p in ip-full bpftool-minimal xdp-loader xdp-filter xdpdump; do
    grep -q "^${p} " "$MAN" || { echo "❌ 缺包 (native 硬件应带 XDP 工具面): $p"; exit 1; }
  done
  echo "✓ XDP 工具面在列 (native-capable 硬件)"
else
  for p in bpftool-minimal xdp-loader xdp-filter xdpdump libxdp; do
    if grep -q "^${p} " "$MAN"; then echo "❌ XDP 残留: $p (非 native 硬件按策略不应烘入)"; exit 1; fi
  done
  echo "✓ 无 XDP 工具面 (纯内核网络栈)"
  if grep -q "^ip-full " "$MAN"; then echo "  (注: ip-full 在列 — 通用件, 非 XDP 硬信号, 不判失败)"; fi
fi
if [ "${ENABLE_DOCKER:-no}" = "yes" ]; then
  for p in dockerd docker docker-compose containerd runc iptables-nft kmod-br-netfilter; do
    grep -q "^${p} " "$MAN" || { echo "❌ 缺包 (docker): $p"; exit 1; }
  done
  echo "✓ docker 关键依赖在列 (dockerd/compose/containerd/runc/iptables-nft/br-netfilter)"
fi

echo "== [2] 解包 rootfs 比对 =="
sudo apt-get -qq update >/dev/null 2>&1
sudo apt-get -qq install -y squashfs-tools >/dev/null 2>&1
gzip -dc "$IMG" > /tmp/img.raw || { [ -s /tmp/img.raw ] || exit 1; }
python3 - <<'PY'
import struct
d = open('/tmp/img.raw','rb').read()
cands = []; i = 0
while True:
    i = d.find(b'hsqs', i)
    if i < 0: break
    try:
        major, = struct.unpack_from('<H', d, i+28)
        bs,    = struct.unpack_from('<I', d, i+12)
        used,  = struct.unpack_from('<Q', d, i+40)
        if major == 4 and 4096 <= bs <= 1048576 and 0 < used < 2**31:
            cands.append((i, used, bs))
    except Exception: pass
    i += 4
assert cands, "no squashfs superblock found!"
off, used, bs = cands[-1]
open('/tmp/root.sqfs','wb').write(d[off:off+used])
print("squashfs: offset=%s used=%d (%.1f MiB)" % (off, used, used/1048576))
PY
sudo rm -rf /tmp/ex
sudo unsquashfs -no-progress -q -d /tmp/ex /tmp/root.sqfs

check_sha() { # $1=期望sha  $2=路径
  echo "$1  $2" | sha256sum -c - || { echo "❌ sha 不符: $2"; exit 1; }
}
check_sha cc6c18d47bb9c404fab864cadb983e188766a5187ec706ab6a7fb88257f14d59 /tmp/ex/usr/bin/dae
check_sha 93c3558f592200133b377dd9f96eac9b278b9057f7ae6b8656b15f4fa05506d0 /tmp/ex/usr/sbin/tailscale
check_sha 1ff5174fcbf3abbff85eacc73e6e548b0d094d913a48c1369f60811d1e92eeef /tmp/ex/usr/sbin/tailscaled
check_sha 824fc2e32cef8f14e8f669e7d53ede18870aeeb14983307bb53b3b9dbf4d19b4 /tmp/ex/etc/init.d/dae
echo "✓ 烘入件 sha 全部一致 (dae e3fee8fb / tailscale / tailscaled / dae-init)"

echo "== [2b] gost 门控 =="
if [ "${ENABLE_GOST:-no}" = "yes" ]; then
  check_sha eab7a864df3c5b68117c2e61cf40034638e76f99c862077043131e3ab71fecdf /tmp/ex/usr/bin/gost
  sudo test -x /tmp/ex/etc/init.d/gost || { echo "❌ 缺 /etc/init.d/gost"; exit 1; }
  sudo test -f /tmp/ex/etc/config/gost || { echo "❌ 缺 /etc/config/gost"; exit 1; }
  sudo grep -q "^config gost" /tmp/ex/etc/config/gost || { echo "❌ gost uci 配置节缺失"; exit 1; }
  sudo grep -q "option enabled" /tmp/ex/etc/config/gost || { echo "❌ gost uci 缺 enabled 项"; exit 1; }
  sudo grep -q "option password" /tmp/ex/etc/config/gost || { echo "❌ gost uci 缺 password 项"; exit 1; }
  sudo ls /tmp/ex/etc/rc.d/ | grep -qiE "^S[0-9]+gost$" || { echo "❌ rc.d 缺 S*gost (IB 未自动 enable)"; exit 1; }
  echo "✓ gost 烘入完整 (binary sha / init 755 / uci / S*gost 自启)"
else
  if sudo test -e /tmp/ex/usr/bin/gost; then echo "❌ gost 残留 (enable_gost=no 不应烘入)"; exit 1; fi
  if sudo test -e /tmp/ex/etc/config/gost; then echo "❌ gost uci 残留 (enable_gost=no)"; exit 1; fi
  echo "✓ 无 gost (按需开关关闭)"
fi

test -x /tmp/ex/etc/uci-defaults/99-custom.sh || { echo "❌ 首启脚本缺失或不可执行"; exit 1; }
grep -q "custom_router_ip" /tmp/ex/etc/uci-defaults/99-custom.sh
grep -q "tailscale0" /tmp/ex/etc/uci-defaults/99-custom.sh || { echo "❌ 首启脚本缺 tailscale0 → lan zone 绑定 (tailnet 入向会被 fw4 丢弃)"; exit 1; }
echo "✓ 首启脚本在位 (755, 含 tailscale0 → lan zone 绑定)"
echo "  管理IP文件: $(cat /tmp/ex/etc/config/custom_router_ip.txt 2>/dev/null)"

ls /tmp/ex/etc/rc.d/ | grep -qi "S99dae" || { echo "❌ rc.d 缺 S99dae (IB 未自动 enable)"; exit 1; }
echo "✓ S99dae 开机自启已就位"

if [ -e /tmp/ex/etc/dae/config.dae ]; then echo "❌ 发现 config.dae (不应存在! 配置走恢复套件)"; exit 1; fi
echo "✓ 无 config.dae (纯二进制版)"

echo "== [3] XDP 门控检查 =="
if [ "${ENABLE_XDP:-no}" = "yes" ]; then
  sudo test -f /tmp/ex/root/xdp/xdp_pass.c     || { echo "❌ 缺 xdp_pass.c"; exit 1; }
  sudo test -s /tmp/ex/root/xdp/xdp_pass.o     || { echo "❌ 缺 xdp_pass.o (CI clang 编译失败?)"; exit 1; }
  [ "$(sudo head -c4 /tmp/ex/root/xdp/xdp_pass.o | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] || { echo "❌ xdp_pass.o 非 ELF"; exit 1; }
  sudo test -f /tmp/ex/root/xdp/README-xdp.txt || { echo "❌ 缺 README-xdp.txt"; exit 1; }
  sudo test -f /tmp/ex/etc/rc.local            || { echo "❌ 缺 /etc/rc.local (门控机型应带 XDP 固化块)"; exit 1; }
  sudo grep -q "xdp-loader load -m native eth0" /tmp/ex/etc/rc.local || { echo "❌ /etc/rc.local 未含 XDP 固化块"; exit 1; }
  echo "✓ XDP 试装件在位 (xdp_pass.c + ELF .o + README-xdp.txt) + /etc/rc.local 固化块"
else
  for f in xdp_pass.c xdp_pass.o README-xdp.txt; do
    if sudo test -e "/tmp/ex/root/xdp/$f"; then echo "❌ XDP 试装件残留: /root/xdp/$f"; exit 1; fi
  done
  if sudo grep -q "xdp-loader" /tmp/ex/etc/rc.local 2>/dev/null; then echo "❌ /etc/rc.local 残留 XDP 块 (非白名单不应有)"; exit 1; fi
  echo "✓ 无 XDP 试装件 + rc.local 净 (纯内核网络栈, 门控生效)"
fi

echo "SELFCHECK_PASS"
