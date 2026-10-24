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
