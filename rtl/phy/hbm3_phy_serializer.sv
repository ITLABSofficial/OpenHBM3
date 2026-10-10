// Tek serit N:1 serilestirici, DDR cikisli.
//
// Bu, hbm3_1024_phy_blackbox'in YAZILABILIR yarisidir: saf standart-hucre
// mantigi. Analog yari (PLL, surucu, esitleme, ESD) bu modulde DEGILDIR ve
// yazilamaz -- bkz. hbm3_phy_analog_model.sv.
//
// ZAMANLAMA SOZLESMESI (hbm3_800g_defs.svh ile tutarli):
//   512 bit/kanal / 64 DQ pin = pin basina 8 bit
//   8 bit / 2 (DDR)           = 4 WCK cevrimi
//   4 / 4.6 GHz = 0.87 ns     = 1 PHY_CK periyodu (1/1.15 GHz)
//
// BIT SIRASI (sozlesme -- deserilestirici bunun TERSINI yapar):
//   WCK cevrimi 0: rise=d[0] fall=d[1]
//   WCK cevrimi 1: rise=d[2] fall=d[3]
//   WCK cevrimi 2: rise=d[4] fall=d[5]
//   WCK cevrimi 3: rise=d[6] fall=d[7]
//
// `load` her SER_RATIO/2 cevrimde BIR kez yuksek olmalidir. Ust modul
// (hbm3_phy_tx_channel) bunu uretir.
module hbm3_phy_serializer #(
    parameter int SER_RATIO = 8            // cift olmali (DDR)
)(
    input  logic                 wck,
    input  logic                 rst_n,
    input  logic                 load,     // paralel veriyi yakala
    input  logic [SER_RATIO-1:0] pdata,
    output logic                 dq_rise,  // WCK yukselen kenarinda surulur
    output logic                 dq_fall   // WCK dusen kenarinda surulur
);
    initial
        if (SER_RATIO % 2 != 0)
            $fatal(1, "hbm3_phy_serializer: SER_RATIO cift olmali (%0d)", SER_RATIO);

    // Kaydirma yazmaci: her WCK cevriminde IKI bit tuketilir (DDR).
    logic [SER_RATIO-1:0] shift;

    always_ff @(posedge wck or negedge rst_n) begin
        if (!rst_n)
            shift <= '0;
        else if (load)
            shift <= pdata;
        else
            shift <= {2'b00, shift[SER_RATIO-1:2]};
    end

    // Cikislar KAYITLI bir yazmactan gelir; ek kombinasyonel derinlik yok.
    assign dq_rise = shift[0];
    assign dq_fall = shift[1];
endmodule
