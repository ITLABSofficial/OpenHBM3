// 32-lane ingress contract for an HBM3-class controller.
//
// Each lane is an independent 256-bit stream and maps one-to-one to a
// pseudo-channel. At the 2 GHz core target, accepting one 32-byte line on
// every lane each cycle is 2048 GB/s raw core ingress. The downstream command
// scheduler/async FIFOs/PHY must rate-limit this to the HBM3E PHY's 1177.6 GB/s
// raw budget. This module deliberately proves the interface width needed to
// feed a real 1024-bit HBM3 stack, rather than faking a PHY in RTL.
`include "hbm3_800g_defs.svh"

module hbm3_800g_ingress (
    input  logic clk_ck,
    input  logic rst_n,
    input  logic [HBM3_HOST_LANES-1:0] host_valid,
    output logic [HBM3_HOST_LANES-1:0] host_ready,
    input  logic [HBM3_HOST_LANES*HBM3_ADDR_BITS-1:0] host_addr,
    input  logic [HBM3_HOST_LANES*HBM3_HOST_DATA_BITS-1:0] host_wdata,

    // Contract presented to 32 per-pseudo-channel request FIFOs.
    output logic [HBM3_PSEUDO_CHANNELS-1:0] pc_valid,
    input  logic [HBM3_PSEUDO_CHANNELS-1:0] pc_ready,
    output logic [HBM3_PSEUDO_CHANNELS*HBM3_ADDR_BITS-1:0] pc_addr,
    output logic [HBM3_PSEUDO_CHANNELS*HBM3_HOST_DATA_BITS-1:0] pc_wdata
);
    // Backpressure is per pseudo-channel.  This prevents one stalled PC from
    // stopping the other 31, and prevents the old single req_ready port from
    // silently becoming the bandwidth bottleneck again.
    assign host_ready = pc_ready;
    assign pc_valid = host_valid;
    assign pc_addr = host_addr;
    assign pc_wdata = host_wdata;
endmodule
