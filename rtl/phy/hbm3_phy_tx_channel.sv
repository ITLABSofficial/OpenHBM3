// Tek fiziksel kanalin PHY verici (TX) on-ucu: 512 bit -> 64 DQ serit.
//
// hbm3_1024_phy_blackbox'in YAZILABILIR yarisi. Saf standart-hucre mantigi;
// PLL, surucu, esitleme, ESD burada DEGILDIR (bkz. hbm3_phy_analog_model.sv).
//
// SAAT ILISKISI -- ONEMLI
//   wck, phy_clk'in PLL ile TURETILMIS SER_RATIO/2 kati saatidir
//   (4.6 GHz = 4 x 1.15 GHz). Bu yuzden ASENKRON DEGIL, mezokronedir ve
//   async FIFO GEREKMEZ; SER_RATIO/2'lik bir sayac beat sinirini uretir.
//   Bu, hem gercek PHY yapisidir hem de kanal basina ~2048 flip-flop'luk
//   bir FIFO'dan kacinir (16 kanalda 32,768 FF ederdi).
//
//   SDC tarafinda wck bir `create_generated_clock` olarak tanimlanmalidir.
//   Bu bir entegrasyon sartidir, RTL burada zorlayamaz.
//
// SERIT HARITASI (sozlesme)
//   serit L, par_data[L*SER_RATIO +: SER_RATIO] bitlerini tasir.
//   Bitisik (interleave DEGIL) -- basit ve dokumante.
`include "hbm3_800g_defs.svh"

module hbm3_phy_tx_channel #(
    parameter int DQ_LANES  = HBM3_DQ_BITS_PER_CHANNEL,   // 64
    parameter int SER_RATIO = HBM3_PHY_DATA_BITS_PER_CHANNEL / HBM3_DQ_BITS_PER_CHANNEL  // 8
)(
    input  logic wck,
    input  logic rst_n,

    // paralel taraf -- `par_ready` yalnizca beat sinirinda yuksektir
    input  logic                           par_valid,
    output logic                           par_ready,
    input  logic [DQ_LANES*SER_RATIO-1:0]  par_data,

    // seri taraf -- DDR: rise WCK yukselen, fall dusen kenarda surulur
    output logic [DQ_LANES-1:0]            dq_rise,
    output logic [DQ_LANES-1:0]            dq_fall,
    output logic                           dq_active,   // bu beat gercek veri
    output logic                           beat_start   // egitim/hizalama icin
);
    localparam int HALF     = SER_RATIO / 2;
    localparam int CNT_BITS = (HALF > 1) ? $clog2(HALF) : 1;

    initial begin
        if (SER_RATIO % 2 != 0)
            $fatal(1, "hbm3_phy_tx_channel: SER_RATIO cift olmali (%0d)", SER_RATIO);
        if (DQ_LANES * SER_RATIO != HBM3_PHY_DATA_BITS_PER_CHANNEL)
            $fatal(1, "hbm3_phy_tx_channel: %0d serit x %0d = %0d, beklenen %0d",
                   DQ_LANES, SER_RATIO, DQ_LANES*SER_RATIO,
                   HBM3_PHY_DATA_BITS_PER_CHANNEL);
    end

    logic [CNT_BITS-1:0] cnt;
    logic                load;   // KAYITLI (asagidaki nota bak)

    always_ff @(posedge wck or negedge rst_n)
        if (!rst_n) cnt <= '0;
        else        cnt <= (cnt == CNT_BITS'(HALF - 1)) ? '0 : cnt + 1'b1;

    // `load` 64 serit x SER_RATIO = 512 flip-flop surer. Kombinasyonel
    // uretilirse kritik yol "cnt -> karsilastirici -> tampon agaci -> 512 FF"
    // olur ve karsilastirici (AND3) o agacin ONUNDE durur -- olculdu, ~42 ps.
    // Cozum: karsilastirmayi BIR CEVRIM ONCE yap ve KAYITLI cikisi dagit.
    // (cnt == HALF-1) sinyali, cnt'nin 0'a donmesinden tam bir cevrim once
    // yuksektir; kaydedilince load tam olarak cnt==0 aninda yuksek olur.
    always_ff @(posedge wck or negedge rst_n)
        if (!rst_n) load <= 1'b1;      // reset sonrasi ilk cevrim beat sinriridir
        else        load <= (cnt == CNT_BITS'(HALF - 1));

    assign par_ready  = load;          // yalnizca beat sinirinda kabul
    assign beat_start = load;

    // Bosluk beat'i: veri yoksa sifir surulur ve dq_active dusuk kalir.
    // Gercek PHY'de bu, surucunun yuksek empedansa gecmesine karsilik gelir.
    logic [DQ_LANES*SER_RATIO-1:0] beat_data;
    always_comb beat_data = (par_valid) ? par_data : '0;

    always_ff @(posedge wck or negedge rst_n)
        if (!rst_n)     dq_active <= 1'b0;
        else if (load)  dq_active <= par_valid;

    genvar l;
    generate
        for (l = 0; l < DQ_LANES; l = l + 1) begin : g_lane
            hbm3_phy_serializer #(.SER_RATIO(SER_RATIO)) u_ser (
                .wck, .rst_n, .load,
                .pdata   (beat_data[l*SER_RATIO +: SER_RATIO]),
                .dq_rise (dq_rise[l]),
                .dq_fall (dq_fall[l])
            );
        end
    endgenerate
endmodule
