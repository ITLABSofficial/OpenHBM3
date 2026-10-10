// Synthesizable dual-clock asynchronous FIFO (Cummings-style Gray pointers).
// This is digital CDC logic only; metastability MTBF and implementation
// constraints remain signoff responsibilities for the target PHY/process.
module hbm3_800g_async_fifo #(
    parameter int DATA_BITS = 64,
    parameter int ADDR_BITS = 2
) (
    input  logic                 wr_clk,
    input  logic                 wr_rst_n,
    input  logic                 wr_valid,
    output logic                 wr_ready,
    input  logic [DATA_BITS-1:0] wr_data,
    input  logic                 rd_clk,
    input  logic                 rd_rst_n,
    output logic                 rd_valid,
    input  logic                 rd_ready,
    output logic [DATA_BITS-1:0] rd_data
);
    localparam int PTR_BITS = ADDR_BITS + 1;
    logic [DATA_BITS-1:0] mem [0:(1<<ADDR_BITS)-1];
    logic [PTR_BITS-1:0] wr_bin, wr_gray, rd_bin, rd_gray;
    // Preserve the two-flop synchronizer chains through synthesis/P&R. This
    // attribute is understood by common ASIC/FPGA tools; target-specific CDC
    // constraints and MTBF analysis are still required for signoff.
    (* ASYNC_REG = "TRUE" *) logic [PTR_BITS-1:0] rd_gray_wr1, rd_gray_wr2;
    (* ASYNC_REG = "TRUE" *) logic [PTR_BITS-1:0] wr_gray_rd1, wr_gray_rd2;
    logic wr_full, rd_empty, wr_full_next, rd_empty_next;
    logic [PTR_BITS-1:0] wr_bin_next, wr_gray_next, rd_bin_next, rd_gray_next;

    function automatic [PTR_BITS-1:0] bin_to_gray(input [PTR_BITS-1:0] value);
        bin_to_gray = (value >> 1) ^ value;
    endfunction

    always_comb begin
        wr_bin_next = wr_bin + (wr_valid && !wr_full);
        wr_gray_next = bin_to_gray(wr_bin_next);
        // Invert the two MSBs of the synchronized read pointer for full test.
        wr_full_next = (wr_gray_next == {~rd_gray_wr2[PTR_BITS-1:PTR_BITS-2],
                                         rd_gray_wr2[PTR_BITS-3:0]});
        rd_bin_next = rd_bin + (!rd_empty && rd_ready);
        rd_gray_next = bin_to_gray(rd_bin_next);
        rd_empty_next = (rd_gray_next == wr_gray_rd2);
    end

    assign wr_ready = !wr_full;
    assign rd_valid = !rd_empty;
    assign rd_data = mem[rd_bin[ADDR_BITS-1:0]];

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin <= '0;
            wr_gray <= '0;
            rd_gray_wr1 <= '0;
            rd_gray_wr2 <= '0;
            wr_full <= 1'b0;
        end else begin
            rd_gray_wr1 <= rd_gray;
            rd_gray_wr2 <= rd_gray_wr1;
            if (wr_valid && wr_ready)
                mem[wr_bin[ADDR_BITS-1:0]] <= wr_data;
            wr_bin <= wr_bin_next;
            wr_gray <= wr_gray_next;
            wr_full <= wr_full_next;
        end
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin <= '0;
            rd_gray <= '0;
            wr_gray_rd1 <= '0;
            wr_gray_rd2 <= '0;
            rd_empty <= 1'b1;
        end else begin
            wr_gray_rd1 <= wr_gray;
            wr_gray_rd2 <= wr_gray_rd1;
            rd_bin <= rd_bin_next;
            rd_gray <= rd_gray_next;
            rd_empty <= rd_empty_next;
        end
    end
endmodule
