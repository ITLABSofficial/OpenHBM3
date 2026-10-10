`timescale 1ps/1ps
`include "hbm3_800g_defs.svh"

// Integration test: sixteen independently clocked packet FIFOs, including
// a PHY-calibration holdoff and an ordering/data scoreboard per channel.
module tb_hbm3_800g_dfi_cdc;
    localparam int WORDS_PER_CHANNEL = 12;
    localparam int CORE_CLK_PS = 500;
    localparam int PHY_CLK_PS = 870;
    logic core_clk = 0, phy_clk = 0;
    logic core_rst_n = 0, phy_rst_n = 0, phy_cal_done = 0;
    logic [HBM3_CHANNELS-1:0] core_valid, core_ready, dfi_valid;
    logic [HBM3_CHANNELS-1:0] dfi_ready = '1;
    logic [HBM3_CHANNELS*HBM3_ADDR_BITS-1:0] core_addr, dfi_addr;
    logic [HBM3_CHANNELS*HBM3_HOST_DATA_BITS-1:0] core_wdata, dfi_wdata;
    integer tx_count [0:HBM3_CHANNELS-1];
    integer rx_count [0:HBM3_CHANNELS-1];
    integer ch;
    integer completed = 0;

    always #(CORE_CLK_PS/2) core_clk = ~core_clk;
    always #(PHY_CLK_PS/2) phy_clk = ~phy_clk;

    function automatic [HBM3_ADDR_BITS-1:0] expected_addr(input integer channel,
                                                            input integer seq);
        expected_addr = {23'(seq), 4'(channel), 4'(seq)};
    endfunction

    function automatic [HBM3_HOST_DATA_BITS-1:0] expected_data(input integer channel,
                                                                 input integer seq);
        expected_data = {8{32'(32'hc0de0000 | (channel << 8) | seq)}};
    endfunction

    always @* begin
        core_valid = '0;
        core_addr = '0;
        core_wdata = '0;
        for (ch = 0; ch < HBM3_CHANNELS; ch = ch + 1) begin
            if (tx_count[ch] < WORDS_PER_CHANNEL) begin
                core_valid[ch] = 1'b1;
                core_addr[ch*HBM3_ADDR_BITS +: HBM3_ADDR_BITS] = expected_addr(ch, tx_count[ch]);
                core_wdata[ch*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS] = expected_data(ch, tx_count[ch]);
            end
        end
    end

    hbm3_800g_dfi_cdc #(.FIFO_ADDR_BITS(2)) dut (
        .core_clk_2ghz(core_clk), .phy_ck_1150mhz(phy_clk),
        .core_rst_n, .phy_rst_n, .phy_cal_done,
        .core_valid, .core_ready, .core_addr, .core_wdata,
        .dfi_valid, .dfi_ready, .dfi_addr, .dfi_wdata
    );

    always @(posedge core_clk) begin
        if (core_rst_n)
            for (ch = 0; ch < HBM3_CHANNELS; ch = ch + 1)
                if (core_valid[ch] && core_ready[ch])
                    tx_count[ch] <= tx_count[ch] + 1;
    end

    always @(posedge phy_clk) begin
        if (!phy_cal_done && (dfi_valid != '0))
            $fatal(1, "DFI valid asserted before PHY calibration");
        if (phy_cal_done) begin
            for (ch = 0; ch < HBM3_CHANNELS; ch = ch + 1) begin
                if (dfi_valid[ch] && dfi_ready[ch]) begin
                    if (dfi_addr[ch*HBM3_ADDR_BITS +: HBM3_ADDR_BITS] !== expected_addr(ch, rx_count[ch]))
                        $fatal(1, "Address/order mismatch on channel %0d word %0d", ch, rx_count[ch]);
                    if (dfi_wdata[ch*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS] !== expected_data(ch, rx_count[ch]))
                        $fatal(1, "Data mismatch on channel %0d word %0d", ch, rx_count[ch]);
                    rx_count[ch] = rx_count[ch] + 1;
                    if (rx_count[ch] == WORDS_PER_CHANNEL)
                        completed = completed + 1;
                end
            end
            if (completed == HBM3_CHANNELS) begin
                $display("HBM3_800G_DFI_CDC: PASS (16 channels x %0d ordered packets; calibration gating checked)", WORDS_PER_CHANNEL);
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
        #(300000);
        $fatal(1, "DFI CDC timed out: only %0d/%0d channels completed", completed, HBM3_CHANNELS);
    end
endmodule
