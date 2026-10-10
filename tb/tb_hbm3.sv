// HBM3 top testbench: sirali yaz->oku dogrulama (tek outstanding)
// DBI en-kotu durum, DBI siniri (=4), refresh girisimi, coklu PC
`timescale 1ns/1ps
`include "hbm3_defs.svh"

module tb_hbm3;
    logic clk = 0, rst_n;
    always #5 clk = ~clk;

    localparam int NUM_PC = 4;
    localparam int AW     = $clog2(NUM_PC) + ROWBITS + NBANK_AW + COLBITS;
    localparam int NBA    = NBANK_AW;

    logic        req_valid = 0, req_ready, req_write;
    logic [AW-1:0]   req_addr;
    logic [255:0]    req_wdata;
    logic        rsp_valid;
    logic [255:0]    rsp_rdata;
    logic [$clog2(NUM_PC)-1:0] rsp_pc;

    hbm3_top #(.NUM_PC(NUM_PC)) dut (
        .clk, .rst_n,
        .fault_valid('0), .fault_key('0), .fault_flip('0),
        .req_valid, .req_ready, .req_write, .req_addr, .req_wdata,
        .rsp_valid, .rsp_rdata, .rsp_pc,
        .cmd_valid (), .cmd_type (), .cmd_bank (), .cmd_row (),
        .cmd_col (), .cmd_wdata (), .cmd_rdata ()
    );

    wck_div u_wck (.clk, .rst_n, .wck(), .wck_ce());

    int errors = 0;
    int checks = 0;
    int timeout_watch;

    // tek istek + cevap bekle (oku ise veriyi dogrula)
    task automatic do_op(input bit wr,
                         input logic [AW-1:0] a,
                         input logic [255:0] wd,
                         input logic [255:0] exp);
        req_valid = 1; req_write = wr; req_addr = a; req_wdata = wd;
        do @(posedge clk); while (!req_ready);
        // #1: kenardan hemen sonra ama RTL'in AYNI kenari islemesinden
        // SONRA dusur -- yoksa testbench'in blocking atamasi RTL'in ayni
        // kenardaki degerlendirmesiyle YARIŞIR (kabul edilen istek kaybolur/
        // bozulur). Bir cevrim TAM beklemek ise req_valid'i bir fazla
        // cevrim yuksekte tutup AYNI istegi IKINCI kez kuyruga sokar
        // (cift-enqueue). #1 ikisini de onler.
        #1;
        req_valid = 0;

        if (!wr) begin
            timeout_watch = 0;
            while (!rsp_valid && timeout_watch < 5000) begin
                @(posedge clk);
                timeout_watch++;
            end
            if (!rsp_valid) begin
                $display("[HATA-T] %0t cevap gelmedi adr=%h", $time, a);
                errors++;
            end else begin
                checks++;
                if (rsp_rdata !== exp) begin
                    $display("[HATA] adr=%h alinan=%h beklenen=%h", a, rsp_rdata, exp);
                    errors++;
                end
            end
        end else begin
            timeout_watch = 0;
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // 1) DBI en-kotu durum: hepsi sifir -> tum byte'lar invert edilmeli
        do_op(1, AW'(20'h00000), 256'h0, 'x);
        do_op(0, AW'(20'h00000), 'x, 256'h0);

        // 2) DBI siniri: byte basina TAM 4 sifir -> invert EDILMEZ
        do_op(1, AW'(20'h00004),
              {8'h0F,8'h0F,8'h33,8'hCC, 8'h55,8'hAA,8'h81,8'h7E,
               8'hE1,8'h1E,8'hC3,8'h3C, 8'h99,8'h66,8'hF0,8'h0F}, 'x);
        do_op(0, AW'(20'h00004), 'x,
              {8'h0F,8'h0F,8'h33,8'hCC, 8'h55,8'hAA,8'h81,8'h7E,
               8'hE1,8'h1E,8'hC3,8'h3C, 8'h99,8'h66,8'hF0,8'h0F});

        // 3) coklu PC + refresh girisimi (T_REFI kucuk -> araya girer)
        for (int i = 0; i < 24; i++) begin
            logic [AW-1:0] a;
            logic [255:0] d;
            a  = AW'(i % NUM_PC) << (AW - $clog2(NUM_PC));
            a |= (AW'(i * 3 % NBANKS)) << COLBITS;
            a |= (AW'(((i * 13) + 1))) << (COLBITS + NBA);
            a |= AW'((i * 11) % 32);
            d  = 256'hDEADBEEFCAFEBABE_123456789ABCDEF0_FFFF0000111122223333444455556666 + 256'(i);
            do_op(1, a, d, 'x);
            do_op(0, a, 'x, d);
        end

        $display("TB_HBM3: checks=%0d", checks);
        if (errors == 0 && checks == 26) $display("TB_HBM3: BASARILI");
        else                             $display("TB_HBM3: BASARISIZ (%0d hata)", errors);
        $finish;
    end

    initial begin
        #600000;
        $display("TB_HBM3: ZAMAN ASIMI");
        $finish;
    end

endmodule
