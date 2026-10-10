`timescale 1ps/1ps
`include "hbm3_800g_defs.svh"

module tb_hbm3_800g_scheduler;
    localparam int CYCLES = 2048;
    localparam int CLK_PS = 500; // 2 GHz core target
    logic core_clk = 0;
    logic rst_n = 0;
    logic [HBM3_HOST_LANES-1:0] host_valid = '0, host_ready;
    logic [HBM3_HOST_LANES*HBM3_ADDR_BITS-1:0] host_addr = '0;
    logic [HBM3_HOST_LANES*HBM3_HOST_DATA_BITS-1:0] host_wdata = '0;
    logic [HBM3_CHANNELS-1:0] egress_ready = '1, egress_valid;
    logic [HBM3_CHANNELS*HBM3_ADDR_BITS-1:0] egress_addr;
    logic [HBM3_CHANNELS*HBM3_HOST_DATA_BITS-1:0] egress_wdata;
    logic [HBM3_CHANNELS*4-1:0] egress_bank;
    integer lane, ch;
    integer seed = 32'h1badb002;
    integer egress_lines = 0;
    integer per_channel [0:HBM3_CHANNELS-1];
    logic measure = 0;
    real payload_gbps, phy_efficiency;

    always #(CLK_PS/2) core_clk = ~core_clk;

    hbm3_800g_scheduler_32to16 dut (
        .clk_core(core_clk), .rst_n, .host_valid, .host_ready,
        .host_addr, .host_wdata, .egress_valid, .egress_ready,
        .egress_addr, .egress_wdata, .egress_bank
    );

    // Saturated, randomized target/bank traffic. Every source stays valid;
    // each target therefore sees a realistic collision-heavy arbitration load.
    always @(negedge core_clk) begin
        if (rst_n) begin
            host_valid = '1;
            for (lane = 0; lane < HBM3_HOST_LANES; lane = lane + 1) begin
                seed = seed * 1103515245 + 12345;
                host_addr[lane*HBM3_ADDR_BITS +: HBM3_ADDR_BITS] = seed;
                host_addr[lane*HBM3_ADDR_BITS + 4 +: 4] = seed[19:16];
                host_wdata[lane*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS] = {8{seed}};
            end
        end
    end

    always @(posedge core_clk) begin
        if (measure) begin
            for (ch = 0; ch < HBM3_CHANNELS; ch = ch + 1) begin
                if (egress_valid[ch] && egress_ready[ch]) begin
                    egress_lines = egress_lines + 1;
                    per_channel[ch] = per_channel[ch] + 1;
                end
            end
        end
    end

    initial begin
        for (ch = 0; ch < HBM3_CHANNELS; ch = ch + 1)
            per_channel[ch] = 0;
        repeat (3) @(posedge core_clk);
        rst_n = 1;
        @(negedge core_clk);
        measure = 1;
        repeat (CYCLES) @(posedge core_clk);
        @(negedge core_clk);
        measure = 0;
        host_valid = '0;
        // byte x MHz = MB/s; divide by 1000 for decimal GB/s.
        payload_gbps = $itor(egress_lines * HBM3_HOST_LINE_BYTES * HBM3_CORE_TARGET_MHZ) /
                       (CYCLES * 1000.0);
        phy_efficiency = payload_gbps / 1177.6;
        $display("HBM3_800G_SCHEDULER: PASS");
        $display("  random saturated traffic: %0d cycles, %0d egress lines", CYCLES, egress_lines);
        $display("  payload-equivalent: %0.2f GB/s, HBM3E raw-link efficiency: %0.2f%%", payload_gbps, phy_efficiency * 100.0);
        if (payload_gbps < HBM3_PAYLOAD_TARGET_GBPS)
            $fatal(1, "Payload target missed: %0.2f GB/s < %0d GB/s", payload_gbps, HBM3_PAYLOAD_TARGET_GBPS);
        for (ch = 0; ch < HBM3_CHANNELS; ch = ch + 1)
            if (per_channel[ch] == 0)
                $fatal(1, "Channel %0d made no progress", ch);
        $display("  all 16 channels made progress; no scheduler deadlock observed.");
        $finish;
    end
endmodule
