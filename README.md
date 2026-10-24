# owrt-fw-build — OpenWrt **上游** Rockchip 固化固件（自建构建）

与 [`imm-fw-build`](https://github.com/jcoseql/imm-fw-build) 同构的**最上游版**：底座换成
`downloads.openwrt.org` 官方 feed + 官方 `openwrt/imagebuilder` 容器，不使用任何第三方源。
包清单、`files/` 叠加层、首启脚本、XDP/gost 门控、自检断言全部从 imm 版平移，差异见下。

> 用途：生产面只用「最上游 + ImmortalWrt」。本仓库 = 最上游那条线，先在 E52C 上试。

## 烘入清单

| 项 | 来源 | 校验 |
|---|---|---|
| dae `main@e3fee8fb` | 本仓库 Releases `dae-bin-e3fee8fb`（防上游 nightly 滚动覆盖） | 构建时 sha256 `cc6c18d4…` 锁定；自检解包比对 |
| geoip / geosite | Loyalsoldier latest | 构建时下载 |
| dae procd init | `files/etc/init.d/dae` | sha256 `824fc2e3…`；IB 自动 enable（S99dae） |
| Tailscale 官方静态 `v1.102.4` | `pkgs.tailscale.com` | sha256 ×3（tgz + 两二进制）；自检解包比对 |
| XDP 工具面（门控） | 官方 feed：`ip-full` `bpftool-minimal` `xdp-loader` `xdp-filter` `xdpdump` —— 仅 native-capable 硬件白名单烘入 | 自检条件断言；非白名单断言零残留 |
| XDP 试装件 + 开机固化（门控） | `xdp/`（xdp_pass.c + rc.local + README；CI 条件叠加进 `files/`） | native 硬件才现编 .o；自检断言 ELF + rc.local 固化块 |
| 首启脚本 | `files/etc/uci-defaults/99-custom.sh`（设管理 IP + **tailscale0 挂进 lan zone**） | 自检断言在位 |
| btop / ethtool | 官方 feed | 全构建常驻（监控 + 网卡/IRQ 诊断）；selfcheck 断言在列 |
| gost 2.12.0（按需） | 本仓库 Releases `gost-bin-2.12.0`（官方静态 arm64） | `enable_gost=yes` 才烘入；sha256 `eab7a864…`；含 init + uci（默认 enabled=0） |
| 包清单 | `scripts/build.sh`（唯一权威位置） | 自检断言关键包 |

## 与 imm 版的差异（都是上游 feed 里没有的东西）

| 项 | imm 版 | 上游版 | 处理 |
|---|---|---|---|
| dae / daed 包 | 源内有（`net/dae`，天灵维护） | **无** | 本来就用烘入二进制，无影响 |
| `kmod-xdp-sockets-diag` | 有（dae 包声明的依赖） | **无** | 不列；它是 iproute2 的 AF_XDP 诊断模块，dae 运行不需要，AF_XDP 能力由 kernel `CONFIG_XDP_SOCKETS` 提供 |
| vlmcsd（KMS 三件套） | 有 | **无** | 去掉（客户端激活用不上就删） |
| luci-app-diskman / 中文包 | 有 | **无** | 去掉；要分区管理用上游 `luci-app-...` 或命令行 |
| 包管理 | apk | apk | 一致（25.x 起两边都是 apk） |
| ramips/mt7621 等老板 | 多 | 视上游 target 而定 | 本仓库默认只跑 rockchip/armv8 |

已核对（2026-10-24，`downloads.openwrt.org/releases/25.12.6` 的 `index.json`）：
`curl` `openssh-sftp-server` `luci-app-upnp` `miniupnpd-nftables` `tailscale 1.104.1`
`btop 1.4.7` `ethtool 6.15` `ip-full` `bpftool-minimal` `xdp-loader/filter/dump`
`docker/dockerd 29.6.1` `docker-compose 5.1.4` `containerd` `runc` `iptables-nft`
`kmod-sched-core` `kmod-sched-bpf` `kmod-veth` `kmod-tun` `kmod-br-netfilter` 全在。
上游 `rockchip/armv8` 共 47 个 profile，含 `radxa_e52c` 与 `hinlink_h28k`。

## 运行

1. Actions → `Build OpenWrt 上游 Rockchip` → Run workflow
2. 输入：
   - `version`：25.12.6（= `openwrt/imagebuilder:rockchip-armv8-<ver>` tag）
   - `profile`：设备型号（如 `radxa_e52c`）；注意上游命名与 imm 略有差异（`radxa_cm3-io` 不是 `radxa_cm3_io`）
   - `custom_router_ip`：管理地址（家里 E52C 是 `192.168.15.1`）
   - `rootfs_partsize`：**无 docker 一律 2G**；Docker 才上 4G
   - `enable_docker` / `enable_gost`：默认 no
3. 构建结束前自带 **Self-check**（manifest 断言 + 解包 sha 比对 + XDP/gost 门控）
4. 产物在 Releases（tag `Autobuild`）：`*.img.gz` + `sha256sums` + `*.manifest`

## 刷机后

- 网络/PPPoE/dae 配置/TS state **刻意不进镜像**；按恢复套件 scp 恢复（E52C 用 `~/Downloads/deploy/e52c_imm_kit/kit/README_restore.md` 一套流程，文件路径不变）
- dae：放 `/etc/dae/config.dae`（0640）→ `/etc/init.d/dae start`（S99dae 已就位）
- Tailscale：恢复 `/etc/tailscale/` state → `/etc/init.d/tailscale start`；`tailscale debug prefs` 核对三条宣告
- 上游 25.12 用 **apk**：`apk add <pkg>`，不是 opkg
- root 无密码：尽快设置；WAN 入站默认拒绝（首启脚本不做任何放开）

## 版本升级

- **上游新版本**：workflow 下拉加版本号（`docker manifest inspect` 会假阴性，用 registry HTTP 200 判真）
- **dae 换版**：传新二进制到本仓库 Releases → 改 workflow URL + sha（2 行）+ `selfcheck.sh` sha（1 行）
- **Tailscale 换版**：改 workflow URL（1 处）+ sha（3 处）+ `selfcheck.sh`（2 行）
- **增删包**：只改 `scripts/build.sh` 的 PACKAGES；先在 `releases/<ver>/packages/<arch>/<feed>/index.json` 里确认包在不在
