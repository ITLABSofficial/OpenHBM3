`timescale 1ns/1ps
// NEGATIF TEST: dram_model'daki adres-cakismasi (aliasing) dedektorunun
// GERCEKTEN atesledigini kanitlar.
//
// dram_model satir alanini RSTOR=6 bite keser (Icarus'ta tam ROWBITS
// pratik degil). Yani ust bitleri farkli iki satir AYNI depo gozune duser.
// Bu test bilerek boyle bir cift kullanir: satir 1 ve satir 1+64 -- ikisi de
// alt 6 bitte 1 eder. Ayni bank/kolona once birine, sonra digerine yazip
// dedektorun uyari verdigini bekler.
//
// BASARI KOSULU: en az bir [DRAM-HATA] ... ADRES CAKISMASI satiri gorulmesi.
// (Dedektor sessiz kalirsa TEST BASARISIZ -- yani "yesil" cikti burada
//  dedektorun ISE YARAMADIGI anlamina gelir.)
`include "hbm3_defs.svh"

module tb_alias;
    logic clk = 0, rst_n;
    always #5 clk = ~clk;

    localparam int NUM_PC = 4;
    localparam int AW     = $clog2(NUM_PC) + ROWBITS + NBANK_AW + COLBITS;
    localparam int RSTOR  = 6;      // dram_model ile ayni olmali

    logic        req_valid = 0, req_ready, req_write;
    logic [AW-1:0]   req_addr;
    logic [255:0]    req_wdata;
    logic        rsp_valid, busy;
    logic [255:0]    rsp_rdata;
    logic [$clog2(NUM_PC)-1:0] rsp_pc;

    hbm3_top #(.NUM_PC(NUM_PC)) dut (
        .clk, .rst_n,
        .fault_valid('0), .fault_key('0), .fault_flip('0),
        .req_valid, .req_ready, .req_write, .req_addr, .req_wdata,
        .rsp_valid, .rsp_rdata, .rsp_pc, .busy,
        .cmd_valid(), .cmd_type(), .cmd_bank(), .cmd_row(), .cmd_col(),
        .cmd_wdata(), .cmd_wdbi(), .cmd_allbanks(), .cmd_rdata(), .cmd_rdbi()
    );

    function automatic logic [AW-1:0] addr_of(input int bank, input int row);
        logic [AW-1:0] a;
        a  = '0;
        a |= (AW'(bank)) << COLBITS;
        a |= (AW'(row))  << (COLBITS + NBANK_AW);
        return a;
    endfunction

    task automatic wr(input int bank, input int row, input logic [255:0] d);
        req_valid = 1; req_write = 1;
        req_addr = addr_of(bank, row); req_wdata = d;
        do @(posedge clk); while (!req_ready);
        #1; req_valid = 0;
        while (busy) @(posedge clk);
    endtask

    initial begin
        rst_n = 0; repeat(4) @(posedge clk); rst_n = 1; repeat(2) @(posedge clk);

        // ayni bank + ayni kolon, alt RSTOR bitleri AYNI iki FARKLI satir
        $display("TB_ALIAS: satir %0d ve %0d ayni depo gozune dusuyor (RSTOR=%0d)",
                 1, 1 + (1<<RSTOR), RSTOR);
        wr(3, 1,              256'hAAAA_AAAA);
        wr(3, 1 + (1<<RSTOR), 256'hBBBB_BBBB);   // <- cakisma burada

        repeat(20) @(posedge clk);
        $display("TB_ALIAS: bitti (yukarida ADRES CAKISMASI satiri BEKLENIR)");
        $finish;
    end

    initial begin
        #500_000;
        $display("TB_ALIAS: ZAMAN ASIMI");
        $finish;
    end
endmodule
