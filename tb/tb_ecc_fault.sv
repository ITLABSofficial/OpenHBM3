`timescale 1ns/1ps
// UCTAN UCA ECC dogrulamasi: gercek bir yazma yap, dram_model'in
// FAULT_INJECT portundan depoya BILEREK 1 ve sonra 2 bit hata enjekte et,
// okuyup dogru davranisi kanitla:
//   1 bit  -> veri SESSIZCE duzeltilir, host DOGRU veriyi gorur,
//             pc_channel'in "corrected" yapiskan bayragi yukselir
//   2 bit  -> veri DUZELTILEMEZ, "uncorrectable" yapiskan bayragi yukselir
// (dram_model tb_ecc.sv'de zaten izole test edildi -- bu, GERCEK veri
// yolunda uctan uca bagli oldugunu kanitlayan negatif testtir, HATA 7/14
// dersiyle ayni: baglanmamis/dogrulanmamis bir mekanizma yok sayilir.)
`include "hbm3_defs.svh"

module tb_ecc_fault;
    logic clk = 0, rst_n;
    always #5 clk = ~clk;

    localparam int NUM_PC = 4;
    localparam int AW     = $clog2(NUM_PC) + ROWBITS + NBANK_AW + COLBITS;

    logic        req_valid = 0, req_ready, req_write;
    logic [AW-1:0]   req_addr;
    logic [255:0]    req_wdata;
    logic        rsp_valid, busy;
    logic [255:0]    rsp_rdata;
    logic [$clog2(NUM_PC)-1:0] rsp_pc;
    logic [NUM_PC-1:0] ecc_corrected_sticky, ecc_uncorrectable_sticky;

    logic [NUM_PC-1:0]    fault_valid = 0;
    logic [15*NUM_PC-1:0] fault_key   = 0;
    logic [39*NUM_PC-1:0] fault_flip  = 0;

    hbm3_top #(.NUM_PC(NUM_PC)) dut (
        .clk, .rst_n,
        .fault_valid, .fault_key, .fault_flip,
        .req_valid, .req_ready, .req_write, .req_addr, .req_wdata,
        .rsp_valid, .rsp_rdata, .rsp_pc, .busy,
        .ecc_corrected_sticky, .ecc_uncorrectable_sticky,
        .cmd_valid(), .cmd_type(), .cmd_bank(), .cmd_row(), .cmd_col(),
        .cmd_wdata(), .cmd_wdbi(), .cmd_wecc(), .cmd_allbanks(),
        .cmd_rdata(), .cmd_rdbi(), .cmd_recc_stat()
    );

    // PC=0, bank=1, row=1 -- skey = {bank(4b), row alt 6 bit(6b), col(5b)}
    // = {4'd1, 6'd1, col} -- HER ZAMAN ayni banka/satira yazip okuyacagiz.
    localparam int BANK = 1, ROW = 1;
    function automatic logic [AW-1:0] addr_of(input int col);
        logic [AW-1:0] a;
        a = '0;
        a |= (AW'(BANK)) << COLBITS;
        a |= (AW'(ROW))  << (COLBITS+NBANK_AW);
        a |= (AW'(col));
        return a;
    endfunction

    task automatic wr(input logic [255:0] d);
        req_valid = 1; req_write = 1; req_addr = addr_of(0); req_wdata = d;
        do @(posedge clk); while (!req_ready);
        #1; req_valid = 0;
        while (busy) @(posedge clk);
    endtask

    logic [255:0] rd_result;
    task automatic rd();
        req_valid = 1; req_write = 0; req_addr = addr_of(0); req_wdata = 'x;
        do @(posedge clk); while (!req_ready);
        #1; req_valid = 0;
        wait (rsp_valid);
        rd_result = rsp_rdata;
        @(posedge clk);
    endtask

    // skey PC=0 icin: {bank[3:0], row[5:0], col[4:0]} = {4'd1,6'd1,5'd0}
    localparam logic [14:0] SKEY0 = {4'(BANK), 6'(ROW), 5'd0};

    int errors = 0;

    initial begin
        rst_n = 0; repeat(4) @(posedge clk); rst_n = 1; repeat(2) @(posedge clk);

        // 1) gercek bir yazma yap (beat0 = bit[31:0])
        wr(256'hCAFEBABE_00000000_00000000_00000000_00000000_00000000_00000000_11223344);
        if (ecc_corrected_sticky[0] || ecc_uncorrectable_sticky[0]) begin
            $display("[ECCF-HATA] yazmadan hemen sonra bayrak zaten yukseldi!");
            errors++;
        end

        // 2) TEK bit hata enjekte et (beat0'in ilk kelimesindeki bit 3)
        fault_valid[0] = 1;
        fault_key[14:0] = SKEY0;
        fault_flip[38:0] = 39'h0000000008;  // data biti 3
        @(posedge clk); fault_valid[0] = 0;
        repeat(2) @(posedge clk);

        rd();
        if (rd_result[31:0] !== 32'h11223344) begin
            $display("[ECCF-HATA] tek-bit sonrasi veri YANLIS! beklenen=11223344 alinan=%h", rd_result[31:0]);
            errors++;
        end
        if (!ecc_corrected_sticky[0]) begin
            $display("[ECCF-HATA] tek-bit duzeltildi bayragi YUKSELMEDI!");
            errors++;
        end
        if (ecc_uncorrectable_sticky[0]) begin
            $display("[ECCF-HATA] tek-bit hatada YANLISLIKLA 'duzeltilemez' bayragi yukseldi!");
            errors++;
        end
        $display("TB_ECC_FAULT: tek-bit -> veri=%h corrected=%b uncorrectable=%b",
                  rd_result[31:0], ecc_corrected_sticky[0], ecc_uncorrectable_sticky[0]);

        // 3) yeni bir yazma (bayraklari sifirlamaz -- yapiskan kalmali,
        //    ama yeni deger dogru okunmali) + CIFT bit hata
        wr(256'hCAFEBABE_00000000_00000000_00000000_00000000_00000000_00000000_AABBCCDD);
        fault_valid[0] = 1;
        fault_key[14:0] = SKEY0;
        fault_flip[38:0] = 39'h0000000003;  // data bit 0 VE bit 1 (cift)
        @(posedge clk); fault_valid[0] = 0;
        repeat(2) @(posedge clk);

        rd();
        if (!ecc_uncorrectable_sticky[0]) begin
            $display("[ECCF-HATA] cift-bit sonrasi 'duzeltilemez' bayragi YUKSELMEDI!");
            errors++;
        end
        $display("TB_ECC_FAULT: cift-bit -> veri=%h (bozuk olabilir, BEKLENIYOR) uncorrectable=%b",
                  rd_result[31:0], ecc_uncorrectable_sticky[0]);

        if (errors == 0) $display("TB_ECC_FAULT: BASARILI");
        else              $display("TB_ECC_FAULT: BASARISIZ (%0d hata)", errors);
        $finish;
    end

    initial begin
        #500_000;
        $display("TB_ECC_FAULT: ZAMAN ASIMI");
        $finish;
    end
endmodule
