`timescale 1ps/1ps
`include "hbm3_800g_defs.svh"

module tb_hbm3_800g_gearbox;
    parameter int CORE_CLK_PS = 500;
    parameter int PHY_CLK_PS = 870;
    localparam int WORDS_PER_CHANNEL = 17; // odd count exercises masked flush
    logic core_clk = 0, phy_clk = 0;
    logic core_rst_n = 0, phy_rst_n = 0, phy_cal_done = 0;
    logic [HBM3_CHANNELS-1:0] core_valid, core_ready, core_flush = '0;
    logic [HBM3_CHANNELS*HBM3_ADDR_BITS-1:0] core_addr;
    logic [HBM3_CHANNELS*HBM3_HOST_DATA_BITS-1:0] core_wdata;
    logic [HBM3_CHANNELS-1:0] phy_valid, phy_ready = '1;
    logic [HBM3_CHANNELS*HBM3_GEAR_RATIO-1:0] phy_mask;
    logic [HBM3_CHANNELS*HBM3_GEAR_RATIO*HBM3_ADDR_BITS-1:0] phy_addr;
    logic [HBM3_CHANNELS*HBM3_PHY_DATA_BITS_PER_CHANNEL-1:0] phy_wdata;
    integer tx_count [0:HBM3_CHANNELS-1];
    integer rx_count [0:HBM3_CHANNELS-1];
    integer ch, beat, received = 0;

    always #(CORE_CLK_PS/2) core_clk = ~core_clk;
    always #(PHY_CLK_PS/2) phy_clk = ~phy_clk;

    function automatic [HBM3_ADDR_BITS-1:0] make_addr(input integer channel,
                                                        input integer seq);
        begin
            make_addr = '0;
            make_addr[7:4] = channel[3:0];
            make_addr[3:0] = seq[3:0];
            make_addr[23:8] = seq[15:0];
        end
    endfunction

    function automatic [HBM3_HOST_DATA_BITS-1:0] make_data(input integer channel,
                                                             input integer seq);
        make_data = {8{32'h6b000000 | (channel << 16) | seq}};
    endfunction

    always @* begin
        core_valid = '0;
        core_addr = '0;
        core_wdata = '0;
        for (ch = 0; ch < HBM3_CHANNELS; ch = ch + 1) begin
            if (tx_count[ch] < WORDS_PER_CHANNEL) begin
                core_valid[ch] = 1'b1;
                core_addr[ch*HBM3_ADDR_BITS +: HBM3_ADDR_BITS] = make_addr(ch, tx_count[ch]);
                core_wdata[ch*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS] = make_data(ch, tx_count[ch]);
            end
        end
    end

    hbm3_800g_gearbox_2to1_cdc #(.FIFO_ADDR_BITS(3)) dut (
        .core_clk, .phy_clk, .core_rst_n, .phy_rst_n, .phy_cal_done,
        .core_valid, .core_ready, .core_flush, .core_addr, .core_wdata,
        .phy_valid, .phy_ready, .phy_mask, .phy_addr, .phy_wdata
    );

    always @(posedge core_clk) begin
        if (core_rst_n)
            for (ch = 0; ch < HBM3_CHANNELS; ch = ch + 1)
                if (core_valid[ch] && core_ready[ch])
                    tx_count[ch] <= tx_count[ch] + 1;
    end

    always @(posedge phy_clk) begin
        if (!phy_cal_done && phy_valid != '0)
            $fatal(1, "PHY valid asserted before calibration");
        if (phy_cal_done) begin
            for (ch = 0; ch < HBM3_CHANNELS; ch = ch + 1) begin
                if (phy_valid[ch] && phy_ready[ch]) begin
                    for (beat = 0; beat < HBM3_GEAR_RATIO; beat = beat + 1) begin
                        if (phy_mask[ch*HBM3_GEAR_RATIO + beat]) begin
                            if (phy_addr[(ch*HBM3_GEAR_RATIO+beat)*HBM3_ADDR_BITS +: HBM3_ADDR_BITS]
                                !== make_addr(ch, rx_count[ch]))
                                $fatal(1, "Gearbox address/order mismatch ch=%0d seq=%0d", ch, rx_count[ch]);
                            if (phy_wdata[ch*HBM3_PHY_DATA_BITS_PER_CHANNEL + beat*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS]
                                !== make_data(ch, rx_count[ch]))
                                $fatal(1, "Gearbox data mismatch ch=%0d seq=%0d", ch, rx_count[ch]);
                            rx_count[ch] = rx_count[ch] + 1;
                            received = received + 1;
                        end
                    end
                end
            end
            if (received == HBM3_CHANNELS*WORDS_PER_CHANNEL) begin
                $display("HBM3_800G_GEARBOX: PASS (%0d words, %0dps -> %0dps, odd flush/mask checked)",
                         received, CORE_CLK_PS, PHY_CLK_PS);
                $display("  PHY stream contract: 16 x 512 bits x 1.15 GHz = 1177.6 GB/s raw");
                $finish;
            end
        end
    end

    initial begin
        for (ch = 0; ch < HBM3_CHANNELS; ch = ch + 1) begin
            tx_count[ch] = 0;
            rx_count[ch] = 0;
        end
        repeat (3) @(posedge core_clk);
        core_rst_n = 1;
        repeat (3) @(posedge phy_clk);
        phy_rst_n = 1;
        repeat (6) @(posedge phy_clk);
        phy_cal_done = 1;
        wait (tx_count[0] == WORDS_PER_CHANNEL);
        repeat (2) @(posedge core_clk);
        core_flush = '1;
        // Flush is a level handshake, not a pulse: at faster core clocks the
        // async FIFO can be full until the PHY side drains a slot.
        repeat (64) @(posedge core_clk);
        core_flush = '0;
        #(500000);
        $fatal(1, "Gearbox timeout: received %0d/%0d", received,
               HBM3_CHANNELS*WORDS_PER_CHANNEL);
    end
endmodule
