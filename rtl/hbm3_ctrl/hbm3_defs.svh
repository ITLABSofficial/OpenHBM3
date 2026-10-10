`ifndef HBM3_DEFS_SVH
`define HBM3_DEFS_SVH
// HBM3 parametreleri (JEDEC JESD238 temelli egitim degerleri)

    localparam int DW        = 32;    // PC veri genisligi
    localparam int BL        = 8;     // burst length (beat) -> 32B paket
    // BURST_B yalnizca testbench'lerde (bant genisligi hesabi) kullanilir,
    // sentezlenebilir RTL'de degil. Uyari SADECE bunun icin susturulur --
    // UNUSEDPARAM'i toptan kapatmak yanlis olurdu: "kullanilmayan sabit"
    // cogu zaman standardin bir kuralinin HIC UYGULANMADIGI anlamina gelir
    // (tRRD/tRTP tam boyle yakalandi, bkz. HATALAR.md HATA 13).
    /* verilator lint_off UNUSEDPARAM */
    localparam int BURST_B   = BL*DW/8;  // 32 byte
    /* verilator lint_on UNUSEDPARAM */
    localparam int NBANKS    = 16;    // PC basina banka
    localparam int NBANK_AW  = $clog2(NBANKS);      // 4
    localparam int ROWBITS   = 10;
    localparam int COLBITS   = 5;     // sayfa = 2^5 * 32B = 1KB
    // Modul parametresi ile AYNI ISMI TASIMAMALI: `parameter int NUM_PC =
    // NUM_PC` yazilirsa parametre bu localparam'i golgeler ve varsayilani
    // KENDISINE referans verir (dairesel). Verilator bunu hata sayar, Icarus
    // sessizce gecer -- bkz. HATALAR.md HATA 11.
    localparam int NUM_PC_DEFAULT = 4;     // simulasyonda 4 (gercek: 32)

    // timing (clock cycle)
    localparam int T_RCD = 4;   // ACT -> RD/WR
    localparam int T_RP  = 4;   // PRE -> ACT
    localparam int T_RRD = 2;   // bank-bank ACT arasi
    localparam int T_RTP = 2;   // RD -> PRE
    // Refresh araligi. Test gorunurlugu icin KASITLI olarak kucuk tutuldu:
    // gercek HBM3 tREFI ~3.9us, 1.6GHz CK'de ~6240 cevrim -- yani buradaki
    // 200 degeri ~31x daha agresif ve refresh yukunu o oranda ABARTIR.
    // Refresh maliyetini olcumden ayirmak icin derlerken override edilebilir:
    //   make bandwidth REFI=100000     (refresh'i fiilen kapatir)
    `ifndef T_REFI_VAL
      `define T_REFI_VAL 200
    `endif
    localparam int T_REFI = `T_REFI_VAL;
    localparam int T_RFC  = 8;   // REF suresi

    localparam logic [1:0] CMD_ACT = 2'b00, CMD_RD = 2'b01, CMD_WR = 2'b10, CMD_PRE = 2'b11;

    
`endif
