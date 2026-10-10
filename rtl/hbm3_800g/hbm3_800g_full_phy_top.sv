// KORPUS -- UCTAN UCA UST MODUL: host -> kuyruk -> zamanlayici -> gearbox
//           -> SERILESTIRICI -> DQ pinleri
//
// hbm3_800g_digital_full_top gearbox cikisinda duruyordu (512 bit @ phy_clk).
// Bu modul oradan devam eder: her fiziksel kanal icin bir PHY TX on-ucu
// baglar ve gercek DQ pin dalga formlarini disari verir.
//
// SINIR -- BURADAN SONRASI ANALOGDUR VE BU PROJEDE YOKTUR
//   dq_rise/dq_fall, analog surucunun DDR pad'inde birlestirecegi iki bit
//   akisidir. PLL (WCK uretimi), surucu, esitleme (EQ), sonlandirma (ODT),
//   ESD, TSV ve interposer BU MODULDE DEGILDIR ve acik kaynak akisla
//   uretilemez. Bkz. hbm3_phy_analog_model.sv ve docs/PLAN.md ADIM 5.
//
// SAAT SOZLESMESI
//   wck = SER_RATIO/2 x phy_clk, AYNI PLL'den (4.6 GHz = 4 x 1.15 GHz).
//   Mezokron -- asenkron degil. SDC'de `create_generated_clock` gerekir.
//
// HIZ ESLESMESI -- geri basinc NEDEN YOK
//   Gearbox phy_clk basina EN FAZLA bir 512-bit beat uretir.
//   TX on-ucu her SER_RATIO/2 wck cevriminde (= tam bir phy_clk) bir beat
//   tuketir. Hizlar YAPISAL OLARAK esittir, bu yuzden phy_ready sabit
//   yuksektir ve FIFO gerekmez. Bu bir VARSAYIM DEGIL, saat oraninin
//   sonucudur -- ama wck ile phy_clk ayni PLL'den gelmezse BOZULUR.
`include "hbm3_800g_defs.svh"

module hbm3_800g_full_phy_top (
    input  logic core_clk,
    input  logic phy_clk,
    input  logic wck,                       // PLL: SER_RATIO/2 x phy_clk
    input  logic core_rst_n,
    input  logic phy_rst_n,
    input  logic wck_rst_n,
    input  logic phy_cal_done,
    input  logic [HBM3_CHANNELS-1:0]   core_flush,
    input  logic [HBM3_HOST_LANES-1:0] host_valid,
    output logic [HBM3_HOST_LANES-1:0] host_ready,
    input  logic [HBM3_HOST_LANES*HBM3_ADDR_BITS-1:0]      host_addr,
    input  logic [HBM3_HOST_LANES*HBM3_HOST_DATA_BITS-1:0] host_wdata,

    // ---- GERCEK DQ PINLERI (analog surucunun girisi) ----
    output logic [HBM3_DQ_BITS-1:0]  dq_rise,   // 16 kanal x 64 pin = 1024
    output logic [HBM3_DQ_BITS-1:0]  dq_fall,
    output logic [HBM3_CHANNELS-1:0] dq_active, // kanal veri suruyor mu
    // ---- gozlem: adres/maske hala dijital tarafta ----
    output logic [HBM3_CHANNELS*HBM3_GEAR_RATIO-1:0] phy_mask,
    output logic [HBM3_CHANNELS*HBM3_GEAR_RATIO*HBM3_ADDR_BITS-1:0] phy_addr
);
    localparam int LANES_PC = HBM3_DQ_BITS_PER_CHANNEL;                       // 64
    localparam int SER      = HBM3_PHY_DATA_BITS_PER_CHANNEL / LANES_PC;      // 8

    initial
        if (LANES_PC * SER != HBM3_PHY_DATA_BITS_PER_CHANNEL)
            $fatal(1, "hbm3_800g_full_phy_top: %0d x %0d != %0d",
                   LANES_PC, SER, HBM3_PHY_DATA_BITS_PER_CHANNEL);

    logic [HBM3_CHANNELS-1:0] phy_valid, phy_ready;
    logic [HBM3_CHANNELS*HBM3_PHY_DATA_BITS_PER_CHANNEL-1:0] phy_wdata;

    hbm3_800g_digital_full_top u_digital (
        .core_clk, .phy_clk, .core_rst_n, .phy_rst_n, .phy_cal_done,
        .core_flush, .host_valid, .host_ready, .host_addr, .host_wdata,
        .phy_valid, .phy_ready, .phy_mask, .phy_addr, .phy_wdata
    );

    genvar c;
    generate
        for (c = 0; c < HBM3_CHANNELS; c = c + 1) begin : g_phy
            // Hizlar yapisal olarak esit (yukaridaki nota bak) -> geri basinc yok.
            assign phy_ready[c] = 1'b1;

            hbm3_phy_tx_channel #(
                .DQ_LANES (LANES_PC),
                .SER_RATIO(SER)
            ) u_tx (
                .wck,
                .rst_n     (wck_rst_n),
                .par_valid (phy_valid[c]),
                .par_ready (),                       // hiz esleseme sayesinde kullanilmaz
                .par_data  (phy_wdata[c*HBM3_PHY_DATA_BITS_PER_CHANNEL
                                      +: HBM3_PHY_DATA_BITS_PER_CHANNEL]),
                .dq_rise   (dq_rise[c*LANES_PC +: LANES_PC]),
                .dq_fall   (dq_fall[c*LANES_PC +: LANES_PC]),
                .dq_active (dq_active[c]),
                .beat_start()
            );
        end
    endgenerate
endmodule
