`timescale 1ps/1ps
`include "hbm3_800g_defs.svh"

// Protocol-correct randomized backpressure test. Every source holds valid,
// address and data until ready; every accepted output is matched to exactly
// one accepted input and stalled output payloads must remain stable.
module tb_hbm3_800g_scheduler_scoreboard;
    parameter int CORE_CLK_PS = 500;
    localparam int TX_PER_LANE = 48;
    localparam int TOTAL_TX = HBM3_HOST_LANES * TX_PER_LANE;
    logic clk = 0, rst_n = 0;
    logic [HBM3_HOST_LANES-1:0] host_valid, host_ready;
    logic [HBM3_HOST_LANES*HBM3_ADDR_BITS-1:0] host_addr;
    logic [HBM3_HOST_LANES*HBM3_HOST_DATA_BITS-1:0] host_wdata;
    logic [HBM3_CHANNELS-1:0] egress_valid, egress_ready = '0;
    logic [HBM3_CHANNELS*HBM3_ADDR_BITS-1:0] egress_addr;
    logic [HBM3_CHANNELS*HBM3_HOST_DATA_BITS-1:0] egress_wdata;
    logic [HBM3_CHANNELS*4-1:0] egress_bank;
    logic [HBM3_CHANNELS-1:0] was_stalled = '0;
    logic [HBM3_ADDR_BITS-1:0] stalled_addr [0:HBM3_CHANNELS-1];
    logic [HBM3_HOST_DATA_BITS-1:0] stalled_data [0:HBM3_CHANNELS-1];
    integer lane_seq [0:HBM3_HOST_LANES-1];
    integer per_channel [0:HBM3_CHANNELS-1];
    integer lane, ch, target, grant_count;
    integer cycle = 0, accepted = 0, emitted = 0;
    integer seed = 32'h51a7c0de;
    integer valid_while_blocked = 0;

    always #(CORE_CLK_PS/2) clk = ~clk;

    function automatic integer channel_for(input integer src, input integer seq);
        channel_for = (src*5 + seq*7 + (seq >> 2)) & 15;
    endfunction

    function automatic [HBM3_ADDR_BITS-1:0] make_addr(input integer src,
                                                        input integer seq);
        integer target_ch, bank_value;
        begin
            target_ch = channel_for(src, seq);
            bank_value = src + seq;
            make_addr = '0;
            make_addr[7:4] = target_ch[3:0];
            make_addr[3:0] = bank_value[3:0];
            make_addr[15:8] = src[7:0];
            make_addr[31:16] = seq[15:0];
        end
    endfunction

    function automatic [HBM3_HOST_DATA_BITS-1:0] make_data(input integer src,
                                                             input integer seq);
        make_data = {8{32'h5c000000 | (src << 16) | seq}};
    endfunction

    always @* begin
        host_valid = '0;
        host_addr = '0;
        host_wdata = '0;
        for (lane = 0; lane < HBM3_HOST_LANES; lane = lane + 1) begin
            if (lane_seq[lane] < TX_PER_LANE) begin
                host_valid[lane] = 1'b1;
                host_addr[lane*HBM3_ADDR_BITS +: HBM3_ADDR_BITS] =
                    make_addr(lane, lane_seq[lane]);
                host_wdata[lane*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS] =
                    make_data(lane, lane_seq[lane]);
            end
        end
    end

    hbm3_800g_scheduler_32to16 dut (
        .clk_core(clk), .rst_n, .host_valid, .host_ready, .host_addr, .host_wdata,
        .egress_valid, .egress_ready, .egress_addr, .egress_wdata, .egress_bank
    );

    always @(negedge clk) begin
        if (!rst_n)
            egress_ready = '0;
        else begin
            for (ch = 0; ch < HBM3_CHANNELS; ch = ch + 1) begin
                seed = seed * 1103515245 + 12345;
                // Use high LCG bits; the low bits have a tiny deterministic
                // period and can accidentally hold one channel blocked forever.
                egress_ready[ch] = (seed[30:28] != 3'b000); // ~87.5% ready
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycle = cycle + 1;
            for (ch = 0; ch < HBM3_CHANNELS; ch = ch + 1) begin
                if (was_stalled[ch]) begin
                    if (!egress_valid[ch])
                        $fatal(1, "Valid dropped while stalled on channel %0d", ch);
                    if (egress_addr[ch*HBM3_ADDR_BITS +: HBM3_ADDR_BITS] !== stalled_addr[ch] ||
                        egress_wdata[ch*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS] !== stalled_data[ch])
                        $fatal(1, "Payload changed while stalled on channel %0d", ch);
                end
                was_stalled[ch] = egress_valid[ch] && !egress_ready[ch];
                if (was_stalled[ch]) begin
                    stalled_addr[ch] = egress_addr[ch*HBM3_ADDR_BITS +: HBM3_ADDR_BITS];
                    stalled_data[ch] = egress_wdata[ch*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS];
                    valid_while_blocked = valid_while_blocked + 1;
                end

                grant_count = 0;
                for (lane = 0; lane < HBM3_HOST_LANES; lane = lane + 1) begin
                    if (host_valid[lane] && host_ready[lane] &&
                        host_addr[lane*HBM3_ADDR_BITS + 4 +: 4] == ch[3:0]) begin
                        grant_count = grant_count + 1;
                        if (egress_addr[ch*HBM3_ADDR_BITS +: HBM3_ADDR_BITS] !==
                            host_addr[lane*HBM3_ADDR_BITS +: HBM3_ADDR_BITS] ||
                            egress_wdata[ch*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS] !==
                            host_wdata[lane*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS])
                            $fatal(1, "Input/output data mismatch ch=%0d lane=%0d", ch, lane);
                    end
                end
                if (egress_valid[ch] && egress_ready[ch]) begin
                    if (grant_count != 1)
                        $fatal(1, "Expected exactly one accepted source for ch=%0d, got %0d", ch, grant_count);
                    if (egress_addr[ch*HBM3_ADDR_BITS + 4 +: 4] != ch[3:0])
                        $fatal(1, "Wrong channel decode on egress %0d", ch);
                    if (egress_bank[ch*4 +: 4] != egress_addr[ch*HBM3_ADDR_BITS +: 4])
                        $fatal(1, "Bank metadata mismatch on channel %0d", ch);
                    emitted = emitted + 1;
                    per_channel[ch] = per_channel[ch] + 1;
                end else if (grant_count != 0) begin
                    $fatal(1, "Source accepted without output handshake on channel %0d", ch);
                end
            end

            for (lane = 0; lane < HBM3_HOST_LANES; lane = lane + 1) begin
                if (host_valid[lane] && host_ready[lane]) begin
                    lane_seq[lane] <= lane_seq[lane] + 1;
                    accepted = accepted + 1;
                end
            end
            if (accepted != emitted)
                $fatal(1, "Conservation failure: accepted=%0d emitted=%0d", accepted, emitted);
            if (accepted == TOTAL_TX) begin
                if (valid_while_blocked == 0)
                    $fatal(1, "Randomized test never exercised valid while ready=0");
                for (ch = 0; ch < HBM3_CHANNELS; ch = ch + 1)
                    if (per_channel[ch] == 0)
                        $fatal(1, "No progress on channel %0d", ch);
                $display("HBM3_800G_SCHEDULER_SCOREBOARD: PASS (%0d conserved transactions, %0d cycles, %0d blocked-valid observations, %0dps)",
                         accepted, cycle, valid_while_blocked, CORE_CLK_PS);
                $finish;
            end
            if (cycle > 20000)
                $fatal(1, "Scheduler scoreboard timeout: %0d/%0d accepted", accepted, TOTAL_TX);
        end
    end

    initial begin
        for (lane = 0; lane < HBM3_HOST_LANES; lane = lane + 1)
            lane_seq[lane] = 0;
        for (ch = 0; ch < HBM3_CHANNELS; ch = ch + 1)
            per_channel[ch] = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
    end
endmodule
