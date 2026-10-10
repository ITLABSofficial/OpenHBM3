`timescale 1ps/1ps
`include "hbm3_800g_defs.svh"

module tb_hbm3_800g_contract;
    localparam int CYCLES = 64;
    localparam int CLK_PS = 500; // 2 GHz digital-controller target
    logic clk_ck = 0;
    logic rst_n = 0;
    logic [HBM3_HOST_LANES-1:0] host_valid = '0;
    logic [HBM3_HOST_LANES-1:0] host_ready;
    logic [HBM3_HOST_LANES*HBM3_ADDR_BITS-1:0] host_addr = '0;
    logic [HBM3_HOST_LANES*HBM3_HOST_DATA_BITS-1:0] host_wdata = '0;
    logic [HBM3_PSEUDO_CHANNELS-1:0] phy_pc_ready = '1;
    logic [HBM3_PSEUDO_CHANNELS-1:0] pc_in_ready;
    logic [HBM3_PSEUDO_CHANNELS-1:0] pc_valid;
    logic [HBM3_PSEUDO_CHANNELS*HBM3_ADDR_BITS-1:0] pc_addr;
    logic [HBM3_PSEUDO_CHANNELS*HBM3_HOST_DATA_BITS-1:0] pc_wdata;
    longint accepted_lines = 0;
    integer lane;
    integer accepted_this_cycle;

    always #(CLK_PS/2) clk_ck = ~clk_ck;

    hbm3_800g_ingress ingress (
        .clk_ck, .rst_n, .host_valid, .host_ready, .host_addr, .host_wdata,
        .pc_valid, .pc_ready(pc_in_ready), .pc_addr, .pc_wdata
    );

    hbm3_800g_pc_queues #(.QUEUE_DEPTH(4)) queues (
        .clk_ck, .rst_n,
        .in_valid(pc_valid), .in_ready(pc_in_ready), .in_addr(pc_addr), .in_wdata(pc_wdata),
        .out_valid(), .out_ready(phy_pc_ready), .out_addr(), .out_wdata()
    );

    always @(posedge clk_ck) begin
        accepted_this_cycle = 0;
        if (rst_n)
            for (lane = 0; lane < HBM3_HOST_LANES; lane = lane + 1)
                if (host_valid[lane] && host_ready[lane])
                    accepted_this_cycle = accepted_this_cycle + 1;
        accepted_lines <= accepted_lines + accepted_this_cycle;
    end

    initial begin
        repeat (2) @(posedge clk_ck);
        rst_n = 1;
        @(negedge clk_ck);
        host_valid = '1;
        repeat (CYCLES) @(posedge clk_ck);
        @(negedge clk_ck);
        host_valid = '0;
        @(posedge clk_ck);
        if (accepted_lines != HBM3_HOST_LANES * CYCLES)
            $fatal(1, "Ingress lost lines: got %0d expected %0d", accepted_lines,
                   HBM3_HOST_LANES * CYCLES);
        $display("HBM3_800G_CONTRACT: PASS");
        $display("  topology: %0d channels / %0d pseudo-channels / %0d-bit DQ",
                 HBM3_CHANNELS, HBM3_PSEUDO_CHANNELS, HBM3_DQ_BITS);
        $display("  core ingress: %0d lanes x %0d B x %0d MHz = 2048 GB/s raw",
                 HBM3_HOST_LANES, HBM3_HOST_LINE_BYTES, HBM3_CORE_TARGET_MHZ);
        $display("  PHY budget: 1024 bits x %0d MT/s = 1177.6 GB/s raw; 800 GB/s payload needs >=67.9%% efficiency.",
                 HBM3_DQ_MT_S);
        $display("  NOTE: This verifies the digital ingress contract, not an analog HBM3E PHY.");
        $finish;
    end
endmodule
