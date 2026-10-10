// Full synthesizable digital experiment: scheduler plus sixteen CDC FIFOs.
// This still excludes the licensed analog HBM PHY, TSVs and package.
`include "hbm3_800g_defs.svh"

module hbm3_800g_digital_full_top (
    input  logic core_clk,
    input  logic phy_clk,
    input  logic core_rst_n,
    input  logic phy_rst_n,
    input  logic phy_cal_done,
    input  logic [HBM3_CHANNELS-1:0] core_flush,
    input  logic [HBM3_HOST_LANES-1:0] host_valid,
    output logic [HBM3_HOST_LANES-1:0] host_ready,
    input  logic [HBM3_HOST_LANES*HBM3_ADDR_BITS-1:0] host_addr,
    input  logic [HBM3_HOST_LANES*HBM3_HOST_DATA_BITS-1:0] host_wdata,
    output logic [HBM3_CHANNELS-1:0] phy_valid,
    input  logic [HBM3_CHANNELS-1:0] phy_ready,
    output logic [HBM3_CHANNELS*HBM3_GEAR_RATIO-1:0] phy_mask,
    output logic [HBM3_CHANNELS*HBM3_GEAR_RATIO*HBM3_ADDR_BITS-1:0] phy_addr,
    output logic [HBM3_CHANNELS*HBM3_PHY_DATA_BITS_PER_CHANNEL-1:0] phy_wdata
);
    logic [HBM3_CHANNELS-1:0] sched_valid, sched_ready;
    logic [HBM3_CHANNELS*HBM3_ADDR_BITS-1:0] sched_addr;
    logic [HBM3_CHANNELS*HBM3_HOST_DATA_BITS-1:0] sched_wdata;
    logic core_sync_rst_n, phy_sync_rst_n;
    logic [HBM3_HOST_LANES-1:0] scheduler_host_ready;
    logic [HBM3_HOST_LANES-1:0] queue_in_ready, queue_out_valid;
    logic [HBM3_HOST_LANES*HBM3_ADDR_BITS-1:0] queue_out_addr;
    logic [HBM3_HOST_LANES*HBM3_HOST_DATA_BITS-1:0] queue_out_wdata;

    // Reset dagitimi: yuk dagitimi SDC'deki `set_max_fanout` ile OpenROAD
    // repair_design'a birakilir (bkz. reset_sync basligi, HATA 21).
    // TUM tuketiciler AYNI kopyayi kullanir -- kademeli birakma denendi ve
    // tb_hbm3_800g_full_top'ta cift-gonderime yol acti (bkz. reset_sync).
    logic [3:0] core_rst_fan;
    hbm3_800g_reset_sync #(.FANOUT(4)) core_reset_sync (
        .clk(core_clk), .async_rst_n(core_rst_n), .sync_rst_n(core_sync_rst_n),
        .sync_rst_n_fan(core_rst_fan)
    );
    hbm3_800g_reset_sync phy_reset_sync (
        .clk(phy_clk), .async_rst_n(phy_rst_n), .sync_rst_n(phy_sync_rst_n),
        .sync_rst_n_fan()
    );

    // Do not expose an acceptance while the internal core domain is still in
    // its two-cycle reset release sequence.
    assign host_ready = queue_in_ready & {HBM3_HOST_LANES{core_rst_fan[0]}};

    hbm3_800g_pc_queues #(.QUEUE_DEPTH(4)) ingress_queues (
        .clk_ck(core_clk), .rst_n(core_rst_fan[0]),
        .in_valid(host_valid), .in_ready(queue_in_ready),
        .in_addr(host_addr), .in_wdata(host_wdata),
        .out_valid(queue_out_valid), .out_ready(scheduler_host_ready),
        .out_addr(queue_out_addr), .out_wdata(queue_out_wdata)
    );

    hbm3_800g_scheduler_32to16 scheduler (
        .clk_core(core_clk), .rst_n(core_rst_fan[0]),
        .host_valid(queue_out_valid), .host_ready(scheduler_host_ready),
        .host_addr(queue_out_addr), .host_wdata(queue_out_wdata),
        .egress_valid(sched_valid), .egress_ready(sched_ready),
        .egress_addr(sched_addr), .egress_wdata(sched_wdata),
        .egress_bank()
    );

    hbm3_800g_gearbox_2to1_cdc gearbox_cdc (
        .core_clk, .phy_clk,
        .core_rst_n(core_rst_fan[0]), .phy_rst_n(phy_sync_rst_n), .phy_cal_done,
        .core_valid(sched_valid), .core_ready(sched_ready),
        .core_flush,
        .core_addr(sched_addr), .core_wdata(sched_wdata),
        .phy_valid, .phy_ready, .phy_mask, .phy_addr, .phy_wdata
    );
endmodule
