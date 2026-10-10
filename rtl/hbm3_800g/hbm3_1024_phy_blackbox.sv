// Integration contract only. A real implementation is a qualified HBM3E PHY
// macro with PLL, WCK/DQ/DQS training, CDC, ESD, package/interposer and TSV
// collateral.  It cannot be truthfully produced by OpenROAD from digital RTL.
`include "hbm3_800g_defs.svh"

(* blackbox *)
module hbm3_1024_phy_blackbox (
    // Clocked data is handed over through a verified CDC/gearbox in a real
    // integration. This port is the 2 GHz digital-controller clock only.
    input logic core_clk_2ghz,
    input logic rst_n,
    input logic [HBM3_PSEUDO_CHANNELS-1:0] pc_valid,
    output logic [HBM3_PSEUDO_CHANNELS-1:0] pc_ready,
    input logic [HBM3_PSEUDO_CHANNELS*HBM3_ADDR_BITS-1:0] pc_addr,
    input logic [HBM3_PSEUDO_CHANNELS*HBM3_HOST_DATA_BITS-1:0] pc_wdata,
    output logic phy_ready
);
endmodule
