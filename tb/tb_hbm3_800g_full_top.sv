`timescale 1ps/1ps
`include "hbm3_800g_defs.svh"

module tb_hbm3_800g_full_top;
    parameter int CORE_CLK_PS = 500;
    parameter int PHY_CLK_PS = 870;
    parameter int TX_PER_LANE = 20;
    parameter int ACTIVE_LANES = HBM3_HOST_LANES;
    parameter int READY_SEED = 32'h7e57bacc;
    localparam int TOTAL_TX = ACTIVE_LANES * TX_PER_LANE;
    logic core_clk = 0, phy_clk = 0;
    logic core_rst_n = 0, phy_rst_n = 0, phy_cal_done = 0;
    logic [HBM3_CHANNELS-1:0] core_flush = '0;
    logic [HBM3_HOST_LANES-1:0] host_valid, host_ready;
    logic [HBM3_HOST_LANES*HBM3_ADDR_BITS-1:0] host_addr;
    logic [HBM3_HOST_LANES*HBM3_HOST_DATA_BITS-1:0] host_wdata;
    logic [HBM3_CHANNELS-1:0] phy_valid, phy_ready = '0;
    logic [HBM3_CHANNELS*HBM3_GEAR_RATIO-1:0] phy_mask;
    logic [HBM3_CHANNELS*HBM3_GEAR_RATIO*HBM3_ADDR_BITS-1:0] phy_addr;
    logic [HBM3_CHANNELS*HBM3_PHY_DATA_BITS_PER_CHANNEL-1:0] phy_wdata;
    logic [HBM3_ADDR_BITS-1:0] expected_addr [0:HBM3_CHANNELS-1][0:TOTAL_TX-1];
    logic [HBM3_HOST_DATA_BITS-1:0] expected_data [0:HBM3_CHANNELS-1][0:TOTAL_TX-1];
    logic accepted_seen [0:HBM3_HOST_LANES-1][0:TX_PER_LANE-1];
    logic received_seen [0:HBM3_HOST_LANES-1][0:TX_PER_LANE-1];
    integer lane_seq [0:HBM3_HOST_LANES-1];
    integer write_count [0:HBM3_CHANNELS-1];
    integer read_count [0:HBM3_CHANNELS-1];
    integer drive_lane, score_lane, ready_ch, score_ch, score_beat, init_lane, init_ch;
    integer target, decoded_lane, decoded_seq;
    integer accepted = 0, received = 0, core_cycles = 0, phy_cycles = 0;
    integer host_stall_observations = 0;
    integer seed = READY_SEED;
    logic all_sent = 0;
    time first_phy_transfer = 0, last_phy_transfer = 0;
    real measured_gbps, measured_efficiency;

    always #(CORE_CLK_PS/2) core_clk = ~core_clk;
    always #(PHY_CLK_PS/2) phy_clk = ~phy_clk;

    function automatic integer channel_for(input integer src, input integer seq);
        channel_for = (src*3 + seq*11 + (src >> 1)) & 15;
    endfunction

    function automatic [HBM3_ADDR_BITS-1:0] make_addr(input integer src,
                                                        input integer seq);
        integer target_ch, bank_value;
        begin
            target_ch = channel_for(src, seq);
            bank_value = src ^ seq;
            make_addr = '0;
            make_addr[7:4] = target_ch[3:0];
            make_addr[3:0] = bank_value[3:0];
            make_addr[15:8] = src[7:0];
            make_addr[31:16] = seq[15:0];
        end
    endfunction

    function automatic [HBM3_HOST_DATA_BITS-1:0] make_data(input integer src,
                                                             input integer seq);
        make_data = {8{32'h8e000000 | (src << 16) | seq}};
    endfunction

    always @* begin
        host_valid = '0;
        host_addr = '0;
        host_wdata = '0;
        for (drive_lane = 0; drive_lane < HBM3_HOST_LANES; drive_lane = drive_lane + 1) begin
            if (drive_lane < ACTIVE_LANES && lane_seq[drive_lane] < TX_PER_LANE) begin
                host_valid[drive_lane] = 1'b1;
                host_addr[drive_lane*HBM3_ADDR_BITS +: HBM3_ADDR_BITS] =
                    make_addr(drive_lane, lane_seq[drive_lane]);
                host_wdata[drive_lane*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS] =
                    make_data(drive_lane, lane_seq[drive_lane]);
            end
        end
    end

    hbm3_800g_digital_full_top dut (
        .core_clk, .phy_clk, .core_rst_n, .phy_rst_n, .phy_cal_done, .core_flush,
        .host_valid, .host_ready, .host_addr, .host_wdata,
        .phy_valid, .phy_ready, .phy_mask, .phy_addr, .phy_wdata
    );

    always @(posedge core_clk) begin
        if (core_rst_n) begin
            core_cycles = core_cycles + 1;
            for (score_lane = 0; score_lane < HBM3_HOST_LANES; score_lane = score_lane + 1) begin
                if (host_valid[score_lane] && !host_ready[score_lane])
                    host_stall_observations = host_stall_observations + 1;
                if (host_valid[score_lane] && host_ready[score_lane]) begin
                    accepted_seen[score_lane][lane_seq[score_lane]] = 1'b1;
                    lane_seq[score_lane] <= lane_seq[score_lane] + 1;
                    accepted = accepted + 1;
                end
            end
            // The scheduler may legally reorder independent host lanes to
            // avoid bank conflicts. Capture its committed per-channel order;
            // the PHY side must reproduce this order exactly.
            for (score_ch = 0; score_ch < HBM3_CHANNELS; score_ch = score_ch + 1) begin
                if (dut.sched_valid[score_ch] && dut.sched_ready[score_ch]) begin
                    expected_addr[score_ch][write_count[score_ch]] =
                        dut.sched_addr[score_ch*HBM3_ADDR_BITS +: HBM3_ADDR_BITS];
                    expected_data[score_ch][write_count[score_ch]] =
                        dut.sched_wdata[score_ch*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS];
                    write_count[score_ch] = write_count[score_ch] + 1;
                end
            end
            if (accepted == TOTAL_TX)
                all_sent = 1'b1;
        end
    end

    always @(negedge phy_clk) begin
        if (!phy_cal_done)
            phy_ready = '0;
        else begin
            for (ready_ch = 0; ready_ch < HBM3_CHANNELS; ready_ch = ready_ch + 1) begin
                seed = seed * 1103515245 + 12345;
                phy_ready[ready_ch] = (seed[30:28] != 3'b000);
            end
        end
    end

    always @(posedge phy_clk) begin
        if (phy_rst_n)
            phy_cycles = phy_cycles + 1;
        if (!phy_cal_done && phy_valid != '0)
            $fatal(1, "Full top exposed PHY valid before calibration");
        if (phy_cal_done) begin
            for (score_ch = 0; score_ch < HBM3_CHANNELS; score_ch = score_ch + 1) begin
                if (phy_valid[score_ch] && phy_ready[score_ch]) begin
                    for (score_beat = 0; score_beat < HBM3_GEAR_RATIO; score_beat = score_beat + 1) begin
                        if (phy_mask[score_ch*HBM3_GEAR_RATIO + score_beat]) begin
                            if (first_phy_transfer == 0)
                                first_phy_transfer = $time;
                            last_phy_transfer = $time;
                            if (read_count[score_ch] >= write_count[score_ch])
                                $fatal(1, "PHY produced unaccepted data ch=%0d", score_ch);
                            if (phy_addr[(score_ch*HBM3_GEAR_RATIO+score_beat)*HBM3_ADDR_BITS +: HBM3_ADDR_BITS]
                                !== expected_addr[score_ch][read_count[score_ch]])
                                $fatal(1, "End-to-end address/order mismatch ch=%0d index=%0d got=%h expected=%h wr=%0d mask=%b",
                                       score_ch, read_count[score_ch],
                                       phy_addr[(score_ch*HBM3_GEAR_RATIO+score_beat)*HBM3_ADDR_BITS +: HBM3_ADDR_BITS],
                                       expected_addr[score_ch][read_count[score_ch]], write_count[score_ch],
                                       phy_mask[score_ch*HBM3_GEAR_RATIO +: HBM3_GEAR_RATIO]);
                            if (phy_wdata[score_ch*HBM3_PHY_DATA_BITS_PER_CHANNEL + score_beat*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS]
                                !== expected_data[score_ch][read_count[score_ch]])
                                $fatal(1, "End-to-end data mismatch ch=%0d index=%0d", score_ch, read_count[score_ch]);
                            decoded_lane = phy_addr[(score_ch*HBM3_GEAR_RATIO+score_beat)*HBM3_ADDR_BITS + 8 +: 8];
                            decoded_seq = phy_addr[(score_ch*HBM3_GEAR_RATIO+score_beat)*HBM3_ADDR_BITS + 16 +: 16];
                            if (decoded_lane >= ACTIVE_LANES || decoded_seq >= TX_PER_LANE ||
                                !accepted_seen[decoded_lane][decoded_seq])
                                $fatal(1, "PHY produced transaction not accepted by host lane=%0d seq=%0d",
                                       decoded_lane, decoded_seq);
                            if (received_seen[decoded_lane][decoded_seq])
                                $fatal(1, "PHY duplicated transaction lane=%0d seq=%0d",
                                       decoded_lane, decoded_seq);
                            received_seen[decoded_lane][decoded_seq] = 1'b1;
                            read_count[score_ch] = read_count[score_ch] + 1;
                            received = received + 1;
                        end
                    end
                end
            end
            if (all_sent && received == TOTAL_TX) begin
                for (score_ch = 0; score_ch < HBM3_CHANNELS; score_ch = score_ch + 1)
                    if (read_count[score_ch] != write_count[score_ch])
                        $fatal(1, "Channel conservation mismatch ch=%0d wr=%0d rd=%0d",
                               score_ch, write_count[score_ch], read_count[score_ch]);
                // Include one final PHY period so this is a closed observation
                // interval, not an optimistic first-to-last edge quotient.
                measured_gbps = (TOTAL_TX * HBM3_HOST_LINE_BYTES * 1000.0) /
                                ((last_phy_transfer - first_phy_transfer) + PHY_CLK_PS);
                measured_efficiency = measured_gbps / 1177.6 * 100.0;
                if (host_stall_observations == 0)
                    $fatal(1, "Ingress queues/backpressure were never exercised");
                if (measured_gbps < HBM3_PAYLOAD_TARGET_GBPS)
                    $fatal(1, "End-to-end payload target missed: %0.2f GB/s (%0.2f%%)",
                           measured_gbps, measured_efficiency);
                $display("HBM3_800G_FULL_TOP: PASS (%0d unique transactions, %0d host stalls, %0.2f GB/s, %0.2f%% of 1177.6 GB/s, randomized PHY backpressure, %0dps -> %0dps)",
                         received, host_stall_observations,
                         measured_gbps, measured_efficiency,
                         CORE_CLK_PS, PHY_CLK_PS);
                $finish;
            end
        end
    end

    initial begin
        for (init_lane = 0; init_lane < HBM3_HOST_LANES; init_lane = init_lane + 1)
            begin
                lane_seq[init_lane] = 0;
                for (decoded_seq = 0; decoded_seq < TX_PER_LANE; decoded_seq = decoded_seq + 1) begin
                    accepted_seen[init_lane][decoded_seq] = 1'b0;
                    received_seen[init_lane][decoded_seq] = 1'b0;
                end
            end
        for (init_ch = 0; init_ch < HBM3_CHANNELS; init_ch = init_ch + 1) begin
            write_count[init_ch] = 0;
            read_count[init_ch] = 0;
        end
        repeat (4) @(posedge core_clk);
        @(negedge core_clk);
        core_rst_n = 1;
        repeat (4) @(posedge phy_clk);
        @(negedge phy_clk);
        phy_rst_n = 1;
        repeat (8) @(posedge phy_clk);
        @(negedge phy_clk);
        phy_cal_done = 1;
        wait (all_sent);
        repeat (4) @(posedge core_clk);
        core_flush = '1;
        repeat (128) @(posedge core_clk);
        core_flush = '0;
        #(1000000);
        $fatal(1, "Full-top timeout: accepted=%0d received=%0d", accepted, received);
    end
endmodule
