`timescale 1ns/1ps
// ECC birim testi: rastgele veriler + bilerek 0, 1 ve 2 bit hata enjekte
// ederek Hamming(39,32) SECDED'in gercekten calistigini kanitlar.
module tb_ecc;
    logic [31:0] din, dout;
    logic [6:0]  ecc;
    logic        corrected, uncorrectable;
    logic [38:0] corrupt;  // enjekte edilecek hata biti maskesi (din++ecc uzerinde)

    ecc_encode u_enc(.din(din), .ecc(ecc));

    logic [31:0] rx_din;
    logic [6:0]  rx_ecc;
    ecc_decode u_dec(.din(rx_din), .ecc(rx_ecc), .dout(dout),
                      .err_corrected(corrected), .err_uncorrectable(uncorrectable));

    int errors = 0, n = 0;

    task automatic check(input logic [31:0] d, input int flip_a, input int flip_b);
        logic [38:0] combo, combo_rx;
        n++;
        din = d;
        #1;
        combo = {ecc, din};              // [38:32]=ecc, [31:0]=din
        combo_rx = combo;
        if (flip_a >= 0) combo_rx[flip_a] = ~combo_rx[flip_a];
        if (flip_b >= 0) combo_rx[flip_b] = ~combo_rx[flip_b];
        rx_ecc = combo_rx[38:32];
        rx_din = combo_rx[31:0];
        #1;
        if (flip_b >= 0) begin
            // cift bit hata: TESPIT edilmeli (duzeltilemez), veri
            // duzeltilmis olmak ZORUNDA DEGIL (SECDED garantisi budur)
            if (!uncorrectable) begin
                $display("[ECC-HATA] %0d: cift bit (a=%0d b=%0d) TESPIT EDILMEDI! din=%h",
                          n, flip_a, flip_b, d);
                errors++;
            end
        end else if (flip_a == 38) begin
            // ozel durum: bit 38 = genel parite (P) bitinin KENDISI.
            // P, Hamming sendromuna KATILMAZ (sadece 0..37 sendroma girer)
            // -- P tek basina cevrilirse sendrom 0 KALIR, yani "duzeltildi"
            // bayragi hic YUKSELMEZ (duzeltilecek bir VERI biti yok zaten).
            // Bu, klasik SECDED'de BEKLENEN davranistir: veri her halukarda
            // dogru kalir, sadece P hatasi "veri acisindan onemsiz" sayilir.
            if (dout !== d) begin
                $display("[ECC-HATA] %0d: P-biti tek basina cevrilince veri BOZULDU! din=%h dout=%h",
                          n, d, dout);
                errors++;
            end
            if (corrected || uncorrectable) begin
                $display("[ECC-HATA] %0d: P-biti tek basina cevrilince YANLIS bayrak yukseldi! c=%b u=%b",
                          n, corrected, uncorrectable);
                errors++;
            end
        end else if (flip_a >= 0) begin
            // tek bit hata: DUZELTILMELI, cikan veri orijinalle AYNI olmali
            if (!corrected || dout !== d) begin
                $display("[ECC-HATA] %0d: tek bit (pos=%0d) duzeltilemedi! din=%h dout=%h corrected=%b",
                          n, flip_a, d, dout, corrected);
                errors++;
            end
            if (uncorrectable) begin
                $display("[ECC-HATA] %0d: tek bit hata YANLISLIKLA 'duzeltilemez' dendi!", n);
                errors++;
            end
        end else begin
            // hatasiz: hem corrected hem uncorrectable dusuk olmali, veri ayni
            if (corrected || uncorrectable || dout !== d) begin
                $display("[ECC-HATA] %0d: hatasiz veri yanlis bayrak/veri! din=%h dout=%h c=%b u=%b",
                          n, d, dout, corrected, uncorrectable);
                errors++;
            end
        end
    endtask

    initial begin
        // hatasiz yol
        check(32'h0000_0000, -1, -1);
        check(32'hFFFF_FFFF, -1, -1);
        check(32'hDEAD_BEEF, -1, -1);
        check(32'hA5A5_5A5A, -1, -1);

        // her tek bit pozisyonu (0..38: 32 veri + 7 ecc) icin TEK bit hata
        for (int p = 0; p < 39; p++)
            check(32'h1234_5678 ^ (32'h9ABC_DEF0 * p), p, -1);

        // rastgele cift bit hata kombinasyonlari (farkli pozisyon ciftleri)
        for (int a = 0; a < 39; a += 3)
            for (int b = a+1; b < 39; b += 5)
                check(32'hC0FF_EE00 + a*7 + b, a, b);

        $display("TB_ECC: n=%0d hata=%0d", n, errors);
        if (errors == 0) $display("TB_ECC: BASARILI");
        else              $display("TB_ECC: BASARISIZ");
        $finish;
    end
endmodule
