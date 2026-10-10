`timescale 1ns/1ps
// Bant genisligi olcumu: TEK kanala, FARKLI bankalara/satirlara, ardisik
// (istekler birbirini BEKLEMEDEN, sadece req_ready ile) M yazma, sonra M
// PIPELINE'LI okuma gonderilir. tb_hbm3.sv'nin aksine (tek-outstanding,
// her istek bir oncekinin TAM cevabini bekler) burada trafik gercekci
// sekilde ust uste bindirilir -- banka onceden-acma (pf_*) mekanizmasinin
// gecikmeyi gercekten gizleyip gizlemedigini bu ortaya cikarir.
`include "hbm3_defs.svh"

module tb_bandwidth;
    logic clk = 0, rst_n;
    always #5 clk = ~clk;

    localparam int NUM_PC = 4;
    localparam int AW     = $clog2(NUM_PC) + ROWBITS + NBANK_AW + COLBITS;
    localparam int M      = 64;   // yon basina istek sayisi

    logic        req_valid = 0, req_ready, req_write;
    logic [AW-1:0]   req_addr;
    logic [255:0]    req_wdata;
    logic        rsp_valid;
    logic [255:0]    rsp_rdata;
    logic [$clog2(NUM_PC)-1:0] rsp_pc;
    logic        busy;

    hbm3_top #(.NUM_PC(NUM_PC)) dut (
        .clk, .rst_n,
        .fault_valid('0), .fault_key('0), .fault_flip('0),
        .req_valid, .req_ready, .req_write, .req_addr, .req_wdata,
        .rsp_valid, .rsp_rdata, .rsp_pc, .busy,
        .cmd_valid(), .cmd_type(), .cmd_bank(), .cmd_row(), .cmd_col(),
        .cmd_wdata(), .cmd_wdbi(), .cmd_rdata(), .cmd_rdbi()
    );

    // PC=0 sabit, banka round-robin, HER SEFERINDE FARKLI satir -> gercek
    // ACT gerektirir, "sayfa acik" kisayolunu KULLANMAZ (en kotu/dogru durum).
    function automatic logic [AW-1:0] mk_addr(input int i);
        logic [AW-1:0] a;
        a  = '0;
        a |= (AW'(i % NBANKS))            << COLBITS;
        a |= (AW'(i + 1))                 << (COLBITS+NBANK_AW);
        return a;
    endfunction

    logic [255:0] expect_q [M];
    int errors = 0;

    task automatic issue(input bit wr, input int i);
        logic [255:0] d;
        d = 256'hDEADBEEF_CAFEBABE_12345678_9ABCDEF0_FFFF0000_11112222_33334444_5555 + 256'(i);
        if (wr) expect_q[i] = d;
        req_valid = 1; req_write = wr; req_addr = mk_addr(i);
        req_wdata = wr ? d : 256'hx;
        do @(posedge clk); while (!req_ready);
        #1; req_valid = 0;
    endtask

    // okuma cevaplarini paralel toplayan surec: FIFO sirasiyla gelir
    // (bu protokolde etiket yok -- kanal ici tek slot + prefetch sadece
    // gecikmeyi gizler, TAMAMLANMA SIRASINI degistirmez)
    int rd_recv = 0;
    always @(posedge clk) begin
        if (rsp_valid) begin
            if (rsp_rdata !== expect_q[rd_recv]) begin
                $display("[BW-HATA] i=%0d alinan=%h beklenen=%h", rd_recv, rsp_rdata, expect_q[rd_recv]);
                errors++;
            end
            rd_recv++;
        end
    end

    int tw_start, tw_end, tr_start, tr_end;

    initial begin
        rst_n = 0; repeat(4) @(posedge clk); rst_n = 1; repeat(2) @(posedge clk);

        // ADIL OLCUM: her iki yon de "ilk istek -> SON ISLEM TAMAMLANDI"
        // araligini olcer. Yazmalarin cevabi olmadigi icin tamamlanma
        // ancak dut.busy dusunce gozlenebilir; sadece gonderim suresini
        // olcmek (eski surum) kuyrukta kalan son istekleri saymadigi icin
        // yazmayi okumaya gore HAKSIZ yere iyi gosteriyordu.
        tw_start = $time;
        for (int i = 0; i < M; i++) issue(1, i);
        while (busy) @(posedge clk);
        tw_end = $time;

        tr_start = $time;
        for (int i = 0; i < M; i++) issue(0, i);
        while (rd_recv < M) @(posedge clk);
        tr_end = $time;

        begin
            real wns, rns, wbytes, rbytes, wgbps, rgbps, peak_gbps;
            wns = real'(tw_end - tw_start); rns = real'(tr_end - tr_start);
            wbytes = real'(M) * real'(BURST_B); rbytes = real'(M) * real'(BURST_B);
            wgbps = wbytes / wns; rgbps = rbytes / rns;
            // GERCEK DDR: S_BEAT artik BL degil BL/2 cevrimde bitiyor (ayni
            // cevrimde 2 alt-kanal/A+B), yani ideal tavan da 2 katina cikti
            // (8B/cevrim). Bunu eski (BL bazli) sayiyla kiyaslamak yaniltici
            // olurdu -- YENI gercek tavana gore yuzde hesapla.
            peak_gbps = 32.0 / (real'(BL/2) * 10.0); // 8B/cevrim ideal (DDR), tek yon, 10ns/cevrim
            $display("=== BANT GENISLIGI SONUCU (M=%0d, pipeline'li) ===", M);
            $display("  YAZMA: %0t (%.0f cevrim) -> %.3f GB/s (ideal tavanin %%%.1f'i)",
                      (tw_end-tw_start), wns/10.0, wgbps, 100.0*wgbps/peak_gbps);
            $display("  OKUMA: %0t (%.0f cevrim) -> %.3f GB/s (ideal tavanin %%%.1f'i)",
                      (tr_end-tr_start), rns/10.0, rgbps, 100.0*rgbps/peak_gbps);
            $display("  Ideal tavan (veri yolu %0d-bit, BL%0d, tek yon): %.3f GB/s", DW, BL, peak_gbps);
        end

        if (errors == 0 && rd_recv == M) $display("TB_BANDWIDTH: BASARILI");
        else                             $display("TB_BANDWIDTH: BASARISIZ (%0d hata, rd_recv=%0d)", errors, rd_recv);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("TB_BANDWIDTH: ZAMAN ASIMI (rd_recv=%0d)", rd_recv);
        $finish;
    end
endmodule
