`timescale 1ps/1ps
`include "hbm3_800g_defs.svh"

module tb_scheduler_pathological;
    parameter int CORE_CLK_PS = 500;
    localparam int TX_PER_LANE = 32;
    localparam int TARGET_CH = 0; // All 32 lanes target channel 0
    logic clk = 0, rst_n = 0;
    logic [HBM3_HOST_LANES-1:0] host_valid, host_ready;
    logic [HBM3_HOST_LANES*HBM3_ADDR_BITS-1:0] host_addr;
    logic [HBM3_HOST_LANES*HBM3_HOST_DATA_BITS-1:0] host_wdata;
    logic [HBM3_CHANNELS-1:0] egress_valid, egress_ready = '0;
    logic [HBM3_CHANNELS*HBM3_ADDR_BITS-1:0] egress_addr;
    logic [HBM3_CHANNELS*HBM3_HOST_DATA_BITS-1:0] egress_wdata;
    logic [HBM3_CHANNELS*4-1:0] egress_bank;

    integer lane_seq [0:HBM3_HOST_LANES-1];
    integer lane, ch, accepted = 0, emitted = 0;
    integer seed = 32'hdeadbeef;
    integer cycle = 0;

    always #(CORE_CLK_PS/2) clk = ~clk;

    always @* begin
        host_valid = '0;
        host_addr = '0;
        host_wdata = '0;
        for (lane = 0; lane < HBM3_HOST_LANES; lane = lane + 1) begin
            if (lane_seq[lane] < TX_PER_LANE) begin
                host_valid[lane] = 1'b1;
                // Channel 0, bank = lane & 15
                host_addr[lane*HBM3_ADDR_BITS +: HBM3_ADDR_BITS] = {16'h0, lane[7:0], 4'h0, lane[3:0]};
                host_wdata[lane*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS] = {8{32'ha5000000 | (lane << 16) | lane_seq[lane]}};
            end
        end
    end

    hbm3_800g_scheduler_32to16 dut (
        .clk_core(clk), .rst_n, .host_valid, .host_ready, .host_addr, .host_wdata,
        .egress_valid, .egress_ready, .egress_addr, .egress_wdata, .egress_bank
    );

    always @(negedge clk) begin
        if (!rst_n) egress_ready = '0;
        else begin
            seed = seed * 1103515245 + 12345;
            // 50% random backpressure on channel 0
            egress_ready[TARGET_CH] = seed[20];
            egress_ready[15:1] = '0;
        end
    end

    // Track host acceptances
    always @(posedge clk) begin
        if (rst_n) begin
            cycle = cycle + 1;
            for (lane = 0; lane < HBM3_HOST_LANES; lane = lane + 1) begin
                if (host_valid[lane] && host_ready[lane]) begin
                    lane_seq[lane] = lane_seq[lane] + 1;
                    accepted = accepted + 1;
                end
            end
            if (egress_valid[TARGET_CH] && egress_ready[TARGET_CH]) begin
                emitted = emitted + 1;
            end
        end
    end

    initial begin
        for (lane = 0; lane < HBM3_HOST_LANES; lane = lane + 1) lane_seq[lane] = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        
        while (emitted < HBM3_HOST_LANES * TX_PER_LANE && cycle < 50000) begin
            @(posedge clk);
        end

        if (emitted != HBM3_HOST_LANES * TX_PER_LANE) begin
            $fatal(1, "Deadlock or dropped packets! Emitted %0d, expected %0d, accepted %0d at cycle %0d",
                   emitted, HBM3_HOST_LANES * TX_PER_LANE, accepted, cycle);
        end else begin
            $display("PATHOLOGICAL_CONTENTION_TEST: PASS! All %0d transactions accepted and emitted without deadlock under 50%% backpressure in %0d cycles.",
                     emitted, cycle);
            $finish;
        end
    end
endmodule
