#!/bin/bash
# ============================================================
# 容器内构建脚本 (在上游官方 ImageBuilder 容器 /builder 执行)
# 底座 = downloads.openwrt.org 官方 feed (无任何第三方 feed)
# 包清单 = 唯一权威位置; 增删包只改这里 (与 files/ 叠加层配合)
# ============================================================
set -e
cd /builder

# 上游 IB 镜像默认不一定跑过 setup.sh (RUN_SETUP=0 时压缩包还没解开)
if [ ! -d ./scripts ]; then
  echo "== 首次: 运行 setup.sh 解包 ImageBuilder =="
  ./setup.sh
fi

PACKAGES="curl openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn luci-i18n-filemanager-zh-cn"
# upnp (本体 + 中文包 + nftables 实现)
PACKAGES="$PACKAGES luci-app-upnp luci-i18n-upnp-zh-cn miniupnpd-nftables"
# ---- 网络增强对齐 (2026-10-24 定) ----
# 目的: 与 imm 版做对比测试时不引入传输面变量。只对齐"影响转发/DNS/NAT 行为"的件,
#       不影响转发的一律不跟 (见下方说明)。
# dnsmasq-full: imm 默认是 full (基础版没有 ipset/nftset/DNSSEC); 必须显式卸掉基础版
PACKAGES="$PACKAGES -dnsmasq dnsmasq-full"
# NAT/桥接/连接跟踪: imm 默认带的传输面件
PACKAGES="$PACKAGES kmod-macvlan kmod-nf-nathelper kmod-nf-conntrack-netlink"
# 无法对齐 (记录在案, 测试时算已知变量):
#   kmod-nft-fullcone  — 上游 feed 里根本没有 (imm 侧补丁), 全锥 NAT 只能靠 dae 或放弃
# 刻意不对齐 (与转发路径无关):
#   kmod-mppe + kmod-crypto-* 链 — 只有 PPTP/IPsec 用, PPPoE 不需要
#   autocore / luci-app-cpufreq / default-settings / 中文 i18n — 面板与壳层, 不影响转发
#   block-mount / fdisk / kmod-fs-* / USB 存储 — 存储面, 测试无关 (要挂盘再 apk add)
# dae 运行依赖
# 注: 上游 25.12.6 feed 无 kmod-xdp-sockets-diag (imm 有), 那是 ss/iproute2 的
#     AF_XDP 诊断模块, dae 运行不需要; 故此处不列, 改由 kernel CONFIG_XDP_SOCKETS 提供能力。
#     kmod-nft-tproxy / kmod-nf-tproxy 在上游 target kmods 里存在, 按需再加。
PACKAGES="$PACKAGES kmod-sched-core kmod-sched-bpf kmod-veth kmod-tun"
PACKAGES="$PACKAGES tailscale"
# 注: tailscale 包提供 init/配置/uci 集成; 实际二进制由 files/usr/sbin/ 覆盖为官方静态版
# 系统监控 / 网络诊断
PACKAGES="$PACKAGES btop ethtool"
# XDP 工具面 —— 门控: 仅 native-capable 硬件 (workflow 白名单判定, ENABLE_XDP=yes) 才烘入;
# 默认 no = 纯内核网络栈 (Realtek 口无 native XDP; 试装件在 xdp/, 由 workflow 条件叠加)
if [ "${ENABLE_XDP:-no}" = "yes" ]; then
  PACKAGES="$PACKAGES ip-full bpftool-minimal xdp-loader xdp-filter xdpdump"
fi

if [ "${ENABLE_DOCKER:-no}" = "yes" ]; then
  # 引擎 + CLI + compose (containerd/runc/iptables-nft/kmod 依赖自动解析)
  PACKAGES="$PACKAGES docker dockerd docker-compose"
  # docker 桥接过滤必需; dockerd 包依赖里没有它, 需显式加:
  PACKAGES="$PACKAGES kmod-br-netfilter"
fi

echo "================================================"
echo "BASE             = OpenWrt 上游 (downloads.openwrt.org)"
echo "PROFILE          = $PROFILE"
echo "ROOTFS_PARTSIZE  = $ROOTFS_PARTSIZE"
echo "ENABLE_DOCKER    = ${ENABLE_DOCKER:-no}"
echo "ENABLE_XDP       = ${ENABLE_XDP:-no}"
echo "PACKAGES         = $PACKAGES"
echo "--- repositories (官方 feed) ---"
cat repositories
echo "================================================"

# 仅产 squashfs 版: 关闭 ext4 镜像目标, 省一半产物空间
sed -i 's/^CONFIG_TARGET_ROOTFS_EXT4FS=y/# CONFIG_TARGET_ROOTFS_EXT4FS is not set/' .config
grep -n "EXT4FS" .config || echo "(未找到 EXT4FS 行, 以下方兜底删除为准)"

make image \
  PROFILE="$PROFILE" \
  PACKAGES="$PACKAGES" \
  FILES="/builder/files" \
  ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE"

# 收尾: 兜底去 ext4 (防 .config 行格式变动) + sha256sums 只覆盖将发布的文件
cd bin/targets/rockchip/armv8
rm -f *ext4*
sha256sum *.img.gz *.manifest > sha256sums
echo "== 产物 (squashfs-only) =="
ls -la
cd /builder

echo "BUILD_OK"
