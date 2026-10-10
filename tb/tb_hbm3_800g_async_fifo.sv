`timescale 1ps/1ps

module tb_hbm3_800g_async_fifo #(
    parameter int WR_CLK_PS = 500,
    parameter int RD_CLK_PS = 870
);
    localparam int WORDS = 128;
    logic wr_clk = 0, rd_clk = 0, wr_rst_n = 0, rd_rst_n = 0;
    logic wr_valid = 0, wr_ready;
    logic [31:0] wr_data = '0;
    logic rd_valid, rd_ready = 1;
    logic [31:0] rd_data;
    integer sent = 0, received = 0;

    always #(WR_CLK_PS/2) wr_clk = ~wr_clk;
    always #(RD_CLK_PS/2) rd_clk = ~rd_clk;

    hbm3_800g_async_fifo #(.DATA_BITS(32), .ADDR_BITS(3)) dut (
        .wr_clk, .wr_rst_n, .wr_valid, .wr_ready, .wr_data,
        .rd_clk, .rd_rst_n, .rd_valid, .rd_ready, .rd_data
    );

    always @(negedge wr_clk) begin
        if (wr_rst_n && sent < WORDS) begin
            wr_valid = 1;
            wr_data = sent;
        end else begin
            wr_valid = 0;
        end
    end
    always @(posedge wr_clk)
        if (wr_rst_n && wr_valid && wr_ready) sent = sent + 1;

    always @(posedge rd_clk) begin
        if (rd_rst_n && rd_valid && rd_ready) begin
            if (rd_data !== received)
                $fatal(1, "CDC FIFO order failure: got %0d expected %0d", rd_data, received);
            received = received + 1;
        end
    end

    initial begin
        repeat (3) @(posedge wr_clk);
        wr_rst_n = 1;
        repeat (3) @(posedge rd_clk);
        rd_rst_n = 1;
        wait (received == WORDS);
        $display("HBM3_800G_ASYNC_FIFO: PASS (%0d ordered words, %0dps -> %0dps)",
                 WORDS, WR_CLK_PS, RD_CLK_PS);
        $finish;
    end
endmodule
