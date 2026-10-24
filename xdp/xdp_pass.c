/* xdp_pass.c — 最小 XDP 程序：恒定返回 XDP_PASS（零扰动试装件）
 *
 * 编译:  clang -O2 -target bpf -c xdp_pass.c -o xdp_pass.o
 * 挂载:  xdp-loader load -m native ethX /root/xdp/xdp_pass.o   (或 -m skb)
 *        ip -force link set dev ethX xdpdrv obj /root/xdp/xdp_pass.o sec xdp
 * 卸载:  xdp-loader unload --all ethX   (或 ip link set dev ethX xdp off)
 *
 * 说明:  挂载模式按网口驱动定: native 优先 (SoC GMAC 口)，不支持退 skb (Realtek 口)；
 *        本程序不丢任何包、不修改任何内容，仅用于验证挂载/观测/卸载链路。
 */
#define SEC(NAME) __attribute__((section(NAME), used))

struct xdp_md {
	unsigned int data;
	unsigned int data_end;
	unsigned int data_meta;
	unsigned int ingress_ifindex;
	unsigned int rx_queue_index;
	unsigned int egress_ifindex;
};

SEC("xdp")
int xdp_pass_prog(struct xdp_md *ctx)
{
	(void)ctx;
	return 2; /* XDP_PASS */
}

char _license[] SEC("license") = "GPL";
