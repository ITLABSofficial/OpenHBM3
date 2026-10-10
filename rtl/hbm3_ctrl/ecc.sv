// ECC: 32 bit veri icin Hamming SECDED (39,32) -- Single Error Correct,
// Double Error Detect. Gercek HBM3 "PC basina 2 ECC pini" der ama o,
// DRAM CEKIRDEGI ICI (on-die) bir mekanizmadir -- yedek kolonlarla, RTL
// seviyesinde anlamli modellenemez. Burada onun yerine gercekten calisan,
// gercekten test edilen bir SOZ-SEVIYESI SECDED ECC uyguluyoruz: 32 veri
// biti + 7 kontrol biti = 39 bit. Bu, JEDEC'in 2-pin sayisindan farkli ama
// GERCEK bir hata duzeltme/tespit mekanizmasi -- bkz. docs/HATALAR.md.
//
// Hamming(39,32): kontrol bitleri p1,p2,p4,p8,p16,p32 (2^k pozisyonlarda)
// + genel parite (sendrom=0 ama genel parite tutmuyorsa CIFT hata).
`timescale 1ns/1ps

module ecc_encode (
    input  logic [31:0] din,
    output logic [6:0]  ecc      // [5:0]=Hamming kontrol, [6]=genel parite
);
    // NOT: `p`'yi `int` yerine `logic [5:0]` tut -- bir `int`'ten SABIT
    // aralik secmek (`p[5:0]`) Icarus'ta "constant selects" sessiz-yanlis-
    // hesaplama hatasini tetikliyor (bkz. HATALAR.md).
    function automatic logic [5:0] data_pos(input int i);
        logic [5:0] p;
        int cnt;
        begin
            p = 6'd0; cnt = -1;
            for (int pos = 1; pos <= 38; pos++) begin
                if ((pos & (pos-1)) != 0) begin
                    cnt++;
                    if (cnt == i) begin p = pos[5:0]; end
                end
            end
            data_pos = p;
        end
    endfunction

    // NOT: `din` (port) DOGRUDAN degisken indeksle (din[i], i dongu
    // degiskeni) bit-secilmez -- Icarus -g2012 always_comb icinde bunu
    // "constant selects ... all bits will be included" uyarisiyla
    // SESSIZCE YANLIS hesapliyor (port + degisken index kombinasyonu ayni
    // blokta baska sabit-index erisimleri de bozuyor). Once yerel
    // degiskene kopyala, TUM indekslemeyi yerelde yap, sonuncunda TEK
    // seferde porta ata. Bkz. HATALAR.md.
    logic [31:0] d;
    logic [6:0]  e;
    assign d = din;
    assign ecc = e;

    always_comb begin
        logic [5:0] p;
        p = '0;
        for (int b = 0; b < 6; b++) begin
            logic parity;
            parity = 1'b0;
            for (int i = 0; i < 32; i++) begin
                logic [5:0] pos;
                pos = data_pos(i);
                if (pos[b]) parity ^= d[i];
            end
            p[b] = parity;
        end
        e[5:0] = p;
        e[6]   = ^d ^ ^p;
    end
endmodule

module ecc_decode (
    input  logic [31:0] din,
    input  logic [6:0]  ecc,
    output logic [31:0] dout,
    output logic        err_corrected,     // tek bit hata: duzeltildi
    output logic        err_uncorrectable  // cift bit hata: TESPIT edildi, DUZELTILEMEZ
);
    // NOT: `p`'yi `int` yerine `logic [5:0]` tut -- bir `int`'ten SABIT
    // aralik secmek (`p[5:0]`) Icarus'ta "constant selects" sessiz-yanlis-
    // hesaplama hatasini tetikliyor (bkz. HATALAR.md).
    function automatic logic [5:0] data_pos(input int i);
        logic [5:0] p;
        int cnt;
        begin
            p = 6'd0; cnt = -1;
            for (int pos = 1; pos <= 38; pos++) begin
                if ((pos & (pos-1)) != 0) begin
                    cnt++;
                    if (cnt == i) begin p = pos[5:0]; end
                end
            end
            data_pos = p;
        end
    endfunction

    // ayni neden: portlari once yerele kopyala (bkz. ecc_encode yorumu)
    logic [31:0] d;
    logic [6:0]  e;
    assign d = din;
    assign e = ecc;

    logic [5:0] syndrome;
    logic       overall_parity_err;
    logic [31:0] corrected;

    always_comb begin
        logic [5:0] p_calc;
        for (int b = 0; b < 6; b++) begin
            logic parity;
            parity = e[b];
            for (int i = 0; i < 32; i++) begin
                logic [5:0] pos;
                pos = data_pos(i);
                if (pos[b]) parity ^= d[i];
            end
            p_calc[b] = parity;
        end
        syndrome = p_calc;
        overall_parity_err = ^d ^ ^e[5:0] ^ e[6];

        corrected = d;
        if (syndrome != 6'd0) begin
            for (int i = 0; i < 32; i++) begin
                logic [5:0] pos;
                pos = data_pos(i);
                if (pos == syndrome) corrected[i] = ~d[i];
            end
        end
    end

    assign dout = corrected;
    assign err_corrected     = (syndrome != 6'd0) &&  overall_parity_err;
    assign err_uncorrectable = (syndrome != 6'd0) && !overall_parity_err;
endmodule
