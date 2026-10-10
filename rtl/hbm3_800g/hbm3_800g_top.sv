// Top-level digital boundary for one HBM3E 1024-bit stack.
`include "hbm3_800g_defs.svh"

module hbm3_800g_top (
    // 2 GHz digital-controller target. This is not WCK and does not claim
    // that the external PHY itself runs at 2 GHz.
    input  logic core_clk_2ghz,
    input  logic rst_n,
    input  logic [HBM3_HOST_LANES-1:0] host_valid,
    output logic [HBM3_HOST_LANES-1:0] host_ready,
    input  logic [HBM3_HOST_LANES*HBM3_ADDR_BITS-1:0] host_addr,
    input  logic [HBM3_HOST_LANES*HBM3_HOST_DATA_BITS-1:0] host_wdata,
    output logic phy_ready
);
    logic [HBM3_PSEUDO_CHANNELS-1:0] pc_in_valid, pc_in_ready;
    logic [HBM3_PSEUDO_CHANNELS*HBM3_ADDR_BITS-1:0] pc_in_addr;
    logic [HBM3_PSEUDO_CHANNELS*HBM3_HOST_DATA_BITS-1:0] pc_in_wdata;
    logic [HBM3_PSEUDO_CHANNELS-1:0] pc_valid, pc_ready;
    logic [HBM3_PSEUDO_CHANNELS*HBM3_ADDR_BITS-1:0] pc_addr;
    logic [HBM3_PSEUDO_CHANNELS*HBM3_HOST_DATA_BITS-1:0] pc_wdata;

    hbm3_800g_ingress ingress (
        .clk_ck(core_clk_2ghz), .rst_n,
        .host_valid, .host_ready, .host_addr, .host_wdata,
        .pc_valid(pc_in_valid), .pc_ready(pc_in_ready),
        .pc_addr(pc_in_addr), .pc_wdata(pc_in_wdata)
    );

    hbm3_800g_pc_queues #(.QUEUE_DEPTH(4)) pc_queues (
        .clk_ck(core_clk_2ghz), .rst_n,
        .in_valid(pc_in_valid), .in_ready(pc_in_ready),
        .in_addr(pc_in_addr), .in_wdata(pc_in_wdata),
        .out_valid(pc_valid), .out_ready(pc_ready),
        .out_addr(pc_addr), .out_wdata(pc_wdata)
    );

    hbm3_1024_phy_blackbox phy (
        .core_clk_2ghz, .rst_n, .pc_valid, .pc_ready, .pc_addr, .pc_wdata, .phy_ready
    );
endmodule
