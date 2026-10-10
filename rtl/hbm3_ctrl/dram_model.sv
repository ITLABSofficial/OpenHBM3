// Davranissal HBM3 DRAM modeli: bank/row acma, kolon RD/WR (32B chunk)
// Veri {bank,row,col} ile kalici saklanir; ACT/PRE kitaplik islemleridir.
// DBI: yazma yonunu cozer (ham veriyi saklar), okuma yonunu kodlar --
// gercek DRAM cekirdegi DBI'dan habersizdir, kodlama sadece DQ hatti icindir.
//
// GERCEK DDR: her cevrimde IKI kolon (A ve B, ardisik) PARALEL islenir --
// gercek DRAM'in "prefetch mimarisi" (bir array erisiminde N bit getirip
// DDR pinlerinden serilestirme) ile ayni prensip. Burada literal 2x'lik
// bir WCK saat alani (gercek PLL/saat-katlayici gerektirirdi, bu projede
// yok ve inandirici sekilde eklenemez) yerine, AYNI saat cevriminde IKI
// bagimsiz 32-bit alt-kanal (A/B) kullanildi -- veri hareketi acisindan
// GERCEK bir 2x kazanc (olcumle dogrulandi), ama pin-seviyesi kenar-kenar
// sinyallemeyi (edge-toggled DDR I/O) TEMSIL ETMEZ. Bkz. README.md.
`timescale 1ns/1ps
`include "hbm3_defs.svh"


module dram_model (
    input  logic        clk,
    input  logic        rst_n,
    input  logic              cmd_valid,
    input  logic [1:0]        cmd_type,
    input  logic [NBANK_AW-1:0]    cmd_bank,
    input  logic [ROWBITS-1:0] cmd_row,
    input  logic [COLBITS-1:0] cmd_col,
    input  logic [31:0]       cmd_wdata,
    input  logic [3:0]        cmd_wdbi,
    input  logic [6:0]        cmd_wecc,      // yazma ECC (HAM veri uzerinden, bkz. pc_channel.sv)
    input  logic              cmd_allbanks,  // PRE ile: PREA (tum bankalar)
    output logic [31:0]       cmd_rdata,
    output logic [3:0]        cmd_rdbi,
    // okumada on-die ECC durumu: 00=temiz, 01=tek-bit duzeltildi,
    // 10=cift-bit TESPIT edildi (duzeltilemedi -- rdata GUVENILMEZ olabilir)
    output logic [1:0]        cmd_recc_stat,

    // ---- B alt-kanali: gercek DDR (ayni cevrimde ikinci kolon) ----
    input  logic [COLBITS-1:0] cmd_col_b,
    input  logic [31:0]       cmd_wdata_b,
    input  logic [3:0]        cmd_wdbi_b,
    input  logic [6:0]        cmd_wecc_b,
    output logic [31:0]       cmd_rdata_b,
    output logic [3:0]        cmd_rdbi_b,
    output logic [1:0]        cmd_recc_stat_b,

    // ---- SADECE SIMULASYON: hata enjeksiyonu (bkz. tb_ecc_fault.sv) ----
    // Bu modul zaten sentez hedefi DEGIL (hbm3_top simulasyon kosumu),
    // bu yuzden test-amacli bir "kalici depoda bit cevir" portu eklemek
    // gercek IP'yi kirletmez. ECC dedektorunun GERCEKTEN calistigini
    // kanitlamanin tek yolu budur (bkz. HATA 14'teki negatif test dersi).
    input  logic               fault_valid,
    // NOT: RSTOR (=6) burada literal yazilir -- port listesi, RSTOR
    // localparam'inin asagida tanimlandigi modul govdesinden ONCE
    // derlenir, sembole burada erisilemez.
    input  logic [NBANK_AW+6+COLBITS-1:0] fault_key,   // skey ile AYNI genislik
    input  logic [38:0]        fault_flip     // 1 olan her bit STORED {ecc,data}'da cevrilir
);

    logic [NBANKS-1:0]                 open;
    logic [NBANKS*ROWBITS-1:0] open_row;

    wire [NBANK_AW-1:0] rb = cmd_bank;
    logic [ROWBITS-1:0] r_row;
    assign r_row = open_row[rb*ROWBITS +: ROWBITS];

    // yazma yonu DBI cozucu: DQ hattindaki kodlanmis veriyi ham hale getirir
    logic [31:0] wdata_raw, wdata_raw_b;
    dbi_dec #(.BYTES(4)) u_wdec   (.din(cmd_wdata),   .dbi(cmd_wdbi),   .dout(wdata_raw));
    dbi_dec #(.BYTES(4)) u_wdec_b (.din(cmd_wdata_b), .dbi(cmd_wdbi_b), .dout(wdata_raw_b));

    // seyrek bellek: anahtar = bank | row'un alt RSTOR biti | col
    // Tam ROWBITS genisligi Icarus'ta pratik degil (4 kanal x 512K kelime
    // simulasyonu dakikalar suruyor), bu yuzden satir alani KESILIR.
    // BU BIR ADRES CAKISMASI (aliasing) TEHLIKESIDIR: ust bitleri farkli iki
    // satir ayni depoya duser. Sessiz kalmamasi icin her girdide TAM satir
    // bir etiket (tag) olarak saklanir ve okuma/yazmada karsilastirilir --
    // cakisma olursa [DRAM-HATA] ile bildirilir (bkz. HATA 4: sessiz
    // aliasing en zor bulunan hata sinifiydi).
    localparam int RSTOR = 6;
    logic [31:0]        mem     [0:(NBANKS*(1<<RSTOR)*(1<<COLBITS))-1];
    logic [6:0]         mem_ecc [0:(NBANKS*(1<<RSTOR)*(1<<COLBITS))-1];
    logic [ROWBITS-1:0] mem_tag [0:(NBANKS*(1<<RSTOR)*(1<<COLBITS))-1];
    logic               mem_vld [0:(NBANKS*(1<<RSTOR)*(1<<COLBITS))-1];
    wire [NBANK_AW+RSTOR+COLBITS-1:0] skey   = {cmd_bank, r_row[RSTOR-1:0], cmd_col};
    wire [NBANK_AW+RSTOR+COLBITS-1:0] skey_b = {cmd_bank, r_row[RSTOR-1:0], cmd_col_b};

    // okuma yonu: depodan HAM veri + ECC cikarilir, on-die ECC ile
    // duzeltilir/tespit edilir (gercek HBM3'te bu adim DRAM CEKIRDEGI
    // ICINDE olur, kontrolcu gormez -- rdata_raw zaten duzeltilmis cikar).
    // Sonra DBI kodlayici DQ hattina kodlar (ECC'den BAGIMSIZ, ayri kat).
    logic [31:0] rdata_stored, rdata_corrected, rdata_stored_b, rdata_corrected_b;
    logic [6:0]  ecc_stored, ecc_stored_b;
    logic        ecc_corr, ecc_uncorr, ecc_corr_b, ecc_uncorr_b;
    ecc_decode u_ecc_dec  (.din(rdata_stored),   .ecc(ecc_stored),   .dout(rdata_corrected),
                            .err_corrected(ecc_corr),   .err_uncorrectable(ecc_uncorr));
    ecc_decode u_ecc_dec_b(.din(rdata_stored_b), .ecc(ecc_stored_b), .dout(rdata_corrected_b),
                            .err_corrected(ecc_corr_b), .err_uncorrectable(ecc_uncorr_b));

    logic [31:0] rdata_raw, rdata_raw_b;
    dbi_enc #(.BYTES(4)) u_renc   (.din(rdata_raw),   .dout(cmd_rdata),   .dbi(cmd_rdbi));
    dbi_enc #(.BYTES(4)) u_renc_b (.din(rdata_raw_b), .dout(cmd_rdata_b), .dbi(cmd_rdbi_b));

    // NOT: her okuma-yolu sinyali (A, B) KENDI `assign`inde -- HATA 16'da
    // bulunan Icarus sinirini bir daha tetiklememek icin AYNI always_comb
    // icinde BIRDEN FAZLA buyuk dizi (mem[]/mem_ecc[]) okunmuyor.
    wire rd_now = cmd_valid && cmd_type == CMD_RD;
    assign rdata_stored   = rd_now ? mem[skey]       : 32'd0;
    assign ecc_stored     = rd_now ? mem_ecc[skey]   : 7'd0;
    assign rdata_stored_b = rd_now ? mem[skey_b]     : 32'd0;
    assign ecc_stored_b   = rd_now ? mem_ecc[skey_b] : 7'd0;
    assign rdata_raw      = rd_now ? rdata_corrected   : 32'd0;
    assign rdata_raw_b    = rd_now ? rdata_corrected_b : 32'd0;
    assign cmd_recc_stat   = rd_now ? (ecc_uncorr   ? 2'b10 : (ecc_corr   ? 2'b01 : 2'b00)) : 2'b00;
    assign cmd_recc_stat_b = rd_now ? (ecc_uncorr_b ? 2'b10 : (ecc_corr_b ? 2'b01 : 2'b00)) : 2'b00;

    // okumada etiket denetimi: istenen satir ile depodaki satir ayni mi?
    // (A ve B ayri always_ff'te -- yine HATA 16 dersi: guvenli olan da
    // budur, ikisini birlestirmeye gerek yok, denetim mantigi zaten hafif.)
    always_ff @(posedge clk) begin
        if (cmd_valid && cmd_type == CMD_RD && mem_vld[skey] &&
            mem_tag[skey] !== r_row)
            $display("[DRAM-HATA] %0t ADRES CAKISMASI (aliasing) okumada: b=%0d col=%0d, satir %0d istendi ama depoda %0d var",
                     $time, rb, cmd_col, r_row, mem_tag[skey]);
    end
    always_ff @(posedge clk) begin
        if (cmd_valid && cmd_type == CMD_RD && mem_vld[skey_b] &&
            mem_tag[skey_b] !== r_row)
            $display("[DRAM-HATA] %0t ADRES CAKISMASI (aliasing) okumada (B): b=%0d col=%0d, satir %0d istendi ama depoda %0d var",
                     $time, rb, cmd_col_b, r_row, mem_tag[skey_b]);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            open <= '0; open_row <= '0;
            for (int i = 0; i < NBANKS*(1<<RSTOR)*(1<<COLBITS); i++)
                mem_vld[i] <= 0;
        end else if (cmd_valid) begin
`ifdef DEBUG
            if (cmd_type == CMD_ACT)
                $display("[DMA] %0t b=%0d row=%0d", $time, rb, cmd_row);
            else if (cmd_type == CMD_RD || cmd_type == CMD_WR) begin
                $display("[DM] %0t t=%s b=%0d row=%0d col=%0d/%0d wd=%h/%h", $time,
                         (cmd_type==CMD_WR?"WR":"RD"), rb, r_row, cmd_col, cmd_col_b,
                         wdata_raw, wdata_raw_b);
                $display("[DMR] %0t rdata=%h/%h", $time, rdata_raw, rdata_raw_b);
            end
`endif
            case (cmd_type)
                CMD_ACT: begin
                    open[rb] <= 1;
                    open_row[rb*ROWBITS +: ROWBITS] <= cmd_row;
                end
                CMD_PRE: if (cmd_allbanks) open <= '0;  // PREA
                         else               open[rb] <= 0;
                CMD_WR: begin
                    mem[skey]     <= wdata_raw;
                    mem_ecc[skey] <= cmd_wecc;
                    mem_tag[skey] <= r_row;
                    mem_vld[skey] <= 1;
                    if (mem_vld[skey] && mem_tag[skey] !== r_row)
                        $display("[DRAM-HATA] %0t ADRES CAKISMASI (aliasing): b=%0d col=%0d, satir %0d uzerine %0d yaziliyor (RSTOR=%0d yetersiz)",
                                 $time, rb, cmd_col, mem_tag[skey], r_row, RSTOR);
                    // B alt-kanali: AYNI cevrimde, farkli kolon
                    mem[skey_b]     <= wdata_raw_b;
                    mem_ecc[skey_b] <= cmd_wecc_b;
                    mem_tag[skey_b] <= r_row;
                    mem_vld[skey_b] <= 1;
                    if (mem_vld[skey_b] && mem_tag[skey_b] !== r_row)
                        $display("[DRAM-HATA] %0t ADRES CAKISMASI (aliasing, B): b=%0d col=%0d, satir %0d uzerine %0d yaziliyor (RSTOR=%0d yetersiz)",
                                 $time, rb, cmd_col_b, mem_tag[skey_b], r_row, RSTOR);
                end
                default: ;
            endcase
        end
        // hata enjeksiyonu (SADECE SIMULASYON): {ecc,data} 39 bitinden
        // fault_flip'te 1 olan her biti cevirir -- gercek DRAM'de retention/
        // kozmik-isin bit bozulmasini modellemenin tek yolu budur, cunku
        // bu davranissal modelde analog sarj kaybi yok. Yazma komutuyla
        // AYNI cevrimde CAKISMAMASI icin ayri bir if (cmd_valid'den
        // bagimsiz) -- test kontrollu, ust FSM'in gormedigi bir yoldur.
        if (fault_valid) begin
            mem[fault_key]     <= mem[fault_key]     ^ fault_flip[31:0];
            mem_ecc[fault_key] <= mem_ecc[fault_key] ^ fault_flip[38:32];
        end
    end

    // kapali bankaya erisim denetimi (dogrulama icin) -- bank duzeyinde,
    // A/B ayni bankayi paylastigindan tek kontrol yeterli.
    logic err_closed;
    always_ff @(posedge clk) begin
        err_closed <= cmd_valid &&
                      (cmd_type == CMD_RD || cmd_type == CMD_WR) &&
                      !open[rb];
        if (err_closed)
            $display("[DRAM-HATA] %0t kapali bankaya kolon erisimi! bank=%0d",
                     $time, rb);
    end

    // acik bankaya ikinci ACT (PRE'siz) denetimi -- gercek DRAM'de yasak
    // komut sirasi; kontrolcu-tarafi bank defteri (b_open) fiili DRAM
    // durumundan (bu modul) saparsa burada yakalanir.
    logic err_react;
    always_ff @(posedge clk) begin
        err_react <= cmd_valid && cmd_type == CMD_ACT && open[rb];
        if (err_react)
            $display("[DRAM-HATA] %0t acik bankaya ikinci ACT (PRE'siz)! bank=%0d",
                     $time, rb);
    end

    // ---- zamanlama kisiti denetleyicileri (tRRD / tRTP) ----
    // tRRD: ardisik ACT komutlari arasinda (farkli bankalar dahil) en az
    //       T_RRD cevrim olmali -- satir aktivasyonu ani akim cektigi icin
    //       gercek DRAM'de zorunlu.
    // tRTP: bir bankaya RD yapildiysa, o bankaya PRE gonderilmeden once
    //       en az T_RTP cevrim gecmeli (okuma verisi cekirdekten cikana dek).
    // (Bank-duzeyinde zamanlama, A/B'nin ikisi de ayni bankayi/cevrimi
    //  paylastigi icin tek bir zamanlayici yeterli.)
    logic [15:0] cyc, last_act_cyc;
    logic        act_seen;
    logic [15:0] last_rd_cyc [NBANKS];
    logic [NBANKS-1:0] rd_since_act;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cyc <= 0; last_act_cyc <= 0; act_seen <= 0; rd_since_act <= '0;
            for (int i = 0; i < NBANKS; i++) last_rd_cyc[i] <= 0;
        end else begin
            cyc <= cyc + 1;
            if (cmd_valid && cmd_type == CMD_ACT) begin
                if (act_seen && (cyc - last_act_cyc) < 16'(T_RRD))
                    $display("[DRAM-HATA] %0t tRRD ihlali: onceki ACT'ten %0d cevrim sonra ACT (min %0d) bank=%0d",
                             $time, cyc - last_act_cyc, T_RRD, rb);
                last_act_cyc    <= cyc;
                act_seen        <= 1;
                rd_since_act[rb] <= 0;
            end
            if (cmd_valid && cmd_type == CMD_RD) begin
                last_rd_cyc[rb]  <= cyc;
                rd_since_act[rb] <= 1;
            end
            if (cmd_valid && cmd_type == CMD_PRE) begin
                if (cmd_allbanks) begin
                    for (int i = 0; i < NBANKS; i++)
                        if (rd_since_act[i] && (cyc - last_rd_cyc[i]) < 16'(T_RTP))
                            $display("[DRAM-HATA] %0t tRTP ihlali (PREA): bank=%0d son RD'den %0d cevrim sonra (min %0d)",
                                     $time, i, cyc - last_rd_cyc[i], T_RTP);
                    rd_since_act <= '0;
                end else begin
                    if (rd_since_act[rb] && (cyc - last_rd_cyc[rb]) < 16'(T_RTP))
                        $display("[DRAM-HATA] %0t tRTP ihlali: bank=%0d son RD'den %0d cevrim sonra PRE (min %0d)",
                                 $time, rb, cyc - last_rd_cyc[rb], T_RTP);
                    rd_since_act[rb] <= 0;
                end
            end
        end
    end

endmodule
