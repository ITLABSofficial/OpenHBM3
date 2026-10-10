// Physical-experiment top: digital scheduler only. No analog PHY/TSV claim.
`include "hbm3_800g_defs.svh"

module hbm3_800g_digital_top (
    input logic core_clk_2ghz,
    input logic rst_n,
    input logic [HBM3_HOST_LANES-1:0] host_valid,
    output logic [HBM3_HOST_LANES-1:0] host_ready,
    input logic [HBM3_HOST_LANES*HBM3_ADDR_BITS-1:0] host_addr,
    input logic [HBM3_HOST_LANES*HBM3_HOST_DATA_BITS-1:0] host_wdata,
    input logic [HBM3_CHANNELS-1:0] egress_ready,
    output logic [HBM3_CHANNELS-1:0] egress_valid,
    output logic [HBM3_CHANNELS*HBM3_ADDR_BITS-1:0] egress_addr,
    output logic [HBM3_CHANNELS*HBM3_HOST_DATA_BITS-1:0] egress_wdata
);
    logic [HBM3_CHANNELS*4-1:0] egress_bank;
    hbm3_800g_scheduler_32to16 scheduler (
        .clk_core(core_clk_2ghz), .rst_n,
        .host_valid, .host_ready, .host_addr, .host_wdata,
        .egress_valid, .egress_ready, .egress_addr, .egress_wdata, .egress_bank
    );
endmodule
