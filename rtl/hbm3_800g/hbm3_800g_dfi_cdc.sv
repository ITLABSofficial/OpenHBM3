// 16-channel digital CDC boundary to a DFI-like PHY command/data interface.
// The external HBM PHY supplies calibration, training and the actual DFI/HBM
// pin protocol. This block transfers complete scheduler packets safely between
// the independently-clocked digital core and PHY clock domains.
`include "hbm3_800g_defs.svh"

module hbm3_800g_dfi_cdc #(
    parameter int FIFO_ADDR_BITS = 3
) (
    input  logic core_clk_2ghz,
    input  logic phy_ck_1150mhz,
    input  logic core_rst_n,
    input  logic phy_rst_n,
    input  logic phy_cal_done,
    input  logic [HBM3_CHANNELS-1:0] core_valid,
    output logic [HBM3_CHANNELS-1:0] core_ready,
    input  logic [HBM3_CHANNELS*HBM3_ADDR_BITS-1:0] core_addr,
    input  logic [HBM3_CHANNELS*HBM3_HOST_DATA_BITS-1:0] core_wdata,
    output logic [HBM3_CHANNELS-1:0] dfi_valid,
    input  logic [HBM3_CHANNELS-1:0] dfi_ready,
    output logic [HBM3_CHANNELS*HBM3_ADDR_BITS-1:0] dfi_addr,
    output logic [HBM3_CHANNELS*HBM3_HOST_DATA_BITS-1:0] dfi_wdata
);
    localparam int PACKET_BITS = HBM3_ADDR_BITS + HBM3_HOST_DATA_BITS;
    logic [HBM3_CHANNELS*PACKET_BITS-1:0] wr_packet, rd_packet;
    logic [HBM3_CHANNELS-1:0] fifo_valid;
    genvar ch;
    generate for (ch = 0; ch < HBM3_CHANNELS; ch = ch + 1) begin : g_channel_cdc
        assign wr_packet[ch*PACKET_BITS +: PACKET_BITS] = {
            core_addr[ch*HBM3_ADDR_BITS +: HBM3_ADDR_BITS],
            core_wdata[ch*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS]
        };
        assign {dfi_addr[ch*HBM3_ADDR_BITS +: HBM3_ADDR_BITS],
                dfi_wdata[ch*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS]} =
            rd_packet[ch*PACKET_BITS +: PACKET_BITS];
        // No request is exposed to the PHY-facing interface until its
        // training/calibration handshake has completed.
        assign dfi_valid[ch] = fifo_valid[ch] && phy_cal_done;
        hbm3_800g_async_fifo #(.DATA_BITS(PACKET_BITS), .ADDR_BITS(FIFO_ADDR_BITS)) fifo (
            .wr_clk(core_clk_2ghz), .wr_rst_n(core_rst_n),
            .wr_valid(core_valid[ch]), .wr_ready(core_ready[ch]),
            .wr_data(wr_packet[ch*PACKET_BITS +: PACKET_BITS]),
            .rd_clk(phy_ck_1150mhz), .rd_rst_n(phy_rst_n),
            .rd_valid(fifo_valid[ch]), .rd_ready(dfi_ready[ch] && phy_cal_done),
            .rd_data(rd_packet[ch*PACKET_BITS +: PACKET_BITS])
        );
    end endgenerate
endmodule
