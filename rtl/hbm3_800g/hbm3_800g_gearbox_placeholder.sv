// Digital integration boundary for a licensed HBM3E PHY.
// This is deliberately not a fake analog PHY or an asynchronous FIFO claim.
// A signoff integration replaces this block with the PHY vendor's CDC/gearbox
// macro and its reset, calibration, DFI-like command/data and training logic.
`include "hbm3_800g_defs.svh"

module hbm3_800g_gearbox_placeholder (
    input  logic core_clk_2ghz,
    input  logic phy_ck_1150mhz,
    input  logic rst_n,
    input  logic [HBM3_CHANNELS-1:0] core_valid,
    output logic [HBM3_CHANNELS-1:0] core_ready,
    input  logic [HBM3_CHANNELS*HBM3_ADDR_BITS-1:0] core_addr,
    input  logic [HBM3_CHANNELS*HBM3_HOST_DATA_BITS-1:0] core_wdata,
    input  logic phy_cal_done,
    output logic [HBM3_CHANNELS-1:0] dfi_valid,
    input  logic [HBM3_CHANNELS-1:0] dfi_ready,
    output logic [HBM3_CHANNELS*HBM3_ADDR_BITS-1:0] dfi_addr,
    output logic [HBM3_CHANNELS*HBM3_HOST_DATA_BITS-1:0] dfi_wdata
);
    // Prevent accidental use as an unverified CDC. The PHY integration owns
    // the real asynchronous FIFOs/gear ratios; simulation can drive ready.
    assign core_ready = phy_cal_done ? dfi_ready : '0;
    assign dfi_valid = phy_cal_done ? core_valid : '0;
    assign dfi_addr = core_addr;
    assign dfi_wdata = core_wdata;
endmodule
