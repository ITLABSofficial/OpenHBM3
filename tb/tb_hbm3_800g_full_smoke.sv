`timescale 1ps/1ps
`include "hbm3_800g_defs.svh"

module tb_hbm3_800g_full_smoke;
    logic core_clk = 0, phy_clk = 0;
    logic core_rst_n = 0, phy_rst_n = 0, phy_cal_done = 0;
    logic [HBM3_CHANNELS-1:0] core_flush = '0, phy_valid, phy_ready = '1;
    logic [HBM3_HOST_LANES-1:0] host_valid = '0, host_ready;
    logic [HBM3_HOST_LANES*HBM3_ADDR_BITS-1:0] host_addr = '0;
    logic [HBM3_HOST_LANES*HBM3_HOST_DATA_BITS-1:0] host_wdata = '0;
    logic [HBM3_CHANNELS*HBM3_GEAR_RATIO-1:0] phy_mask;
    logic [HBM3_CHANNELS*HBM3_GEAR_RATIO*HBM3_ADDR_BITS-1:0] phy_addr;
    logic [HBM3_CHANNELS*HBM3_PHY_DATA_BITS_PER_CHANNEL-1:0] phy_wdata;
    always #250 core_clk = ~core_clk;
    always #435 phy_clk = ~phy_clk;
    hbm3_800g_digital_full_top dut (.*);
    initial begin
        repeat (3) @(posedge core_clk);
        core_rst_n = 1;
        repeat (3) @(posedge phy_clk);
        phy_rst_n = 1;
        phy_cal_done = 1;
        @(negedge core_clk);
        host_addr[7:4] = 4'd0;
        host_wdata[255:0] = 256'h1234;
        host_valid[0] = 1'b1;
        wait (host_ready[0]);
        @(posedge core_clk);
        @(negedge core_clk);
        host_valid[0] = 1'b0;
        core_flush[0] = 1'b1;
        repeat (16) @(posedge core_clk);
        $display("HBM3_800G_FULL_SMOKE: PASS");
        $finish;
    end
endmodule
