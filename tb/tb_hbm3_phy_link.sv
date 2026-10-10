// UCTAN UCA PHY link testi: TX -> SERIT BASINA KAYMA -> RX + EGITIM.
//
// Gercek bir baglantida seritler birbirine gore kayar (tel uzunlugu, pad
// gecikmesi). Bu tezgah bunu BILEREK enjekte eder ve egitimin hizalamayi
// bulup bulamadigini olcer. Egitim basarili olduktan SONRA gercek veri
// gonderilir ve bit-birebirlik dogrulanir.
`timescale 1ns/1ps
`include "hbm3_800g_defs.svh"
module tb_hbm3_phy_link;
    localparam int LANES = HBM3_DQ_BITS_PER_CHANNEL;                  // 64
    localparam int SER   = HBM3_PHY_DATA_BITS_PER_CHANNEL / LANES;    // 8
    localparam int WIDTH = LANES*SER;                                 // 512
    // Iki beat'lik egitim dizisi: (A,B),(A,B),...
    // Tek desen YETMEZ -- periyodu SER_RATIO oldugu icin tam-beat
    // kaymasini gizler (bu tezgah tam olarak onu yakaladi).
    localparam logic [7:0] PAT_A = 8'hA5;
    localparam logic [7:0] PAT_B = 8'h39;
    localparam int HIST  = 4*SER;                                     // 32 bit

    logic wck = 0, rst_n = 0;
    always #0.108 wck = ~wck;

    // ---- verici ----
    logic             par_valid = 1, par_ready;
    logic [WIDTH-1:0] par_data;
    logic [LANES-1:0] tx_rise, tx_fall;
    logic             dq_active, beat_start;
    logic             tx_pattern_en;

    logic [SER-1:0] pat_ctr;
    logic           beat_par;      // egitim beat pariteligi: 0=A, 1=B
    always_ff @(posedge wck or negedge rst_n)
        if (!rst_n) beat_par <= 1'b0;
        else if (par_ready && par_valid && tx_pattern_en) beat_par <= ~beat_par;
    integer li;
    always_ff @(posedge wck or negedge rst_n)
        if (!rst_n) pat_ctr <= '0;
        else if (par_ready && par_valid && !tx_pattern_en) pat_ctr <= pat_ctr + 1'b1;
    always_comb begin
        par_data = '0;
        for (li = 0; li < LANES; li = li + 1)
            par_data[li*SER +: SER] = tx_pattern_en
                                    ? (beat_par ? SER'(PAT_B) : SER'(PAT_A))
                                    : (pat_ctr + SER'(li));
    end

    hbm3_phy_tx_channel u_tx (
        .wck, .rst_n, .par_valid, .par_ready, .par_data,
        .dq_rise(tx_rise), .dq_fall(tx_fall), .dq_active, .beat_start);

    // ---- SERIT BASINA KAYMA (kanal modeli) ----
    // Serit l, (l % SER) bit gecikir. hist[0] en eski bit.
    logic [HIST-1:0] hist [0:LANES-1];
    logic [LANES-1:0] rx_rise, rx_fall;
    integer hi;
    always_ff @(posedge wck or negedge rst_n) begin
        for (hi = 0; hi < LANES; hi = hi + 1) begin
            if (!rst_n) hist[hi] <= '0;
            else        hist[hi] <= {tx_fall[hi], tx_rise[hi], hist[hi][HIST-1:2]};
        end
    end
    genvar gl;
    generate for (gl = 0; gl < LANES; gl = gl + 1) begin : g_skew
        localparam int D = gl % 3;                    // 0..2 bit kayma
        assign rx_rise[gl] = hist[gl][HIST-2-D];
        assign rx_fall[gl] = hist[gl][HIST-1-D];
    end endgenerate

    // ---- alici + egitim ----
    logic [WIDTH-1:0] rx_data;
    logic             rx_valid, align, done, ok;
    logic [LANES-1:0] bitslip, locked;
    logic             start = 0;

    hbm3_phy_rx_channel u_rx (
        .wck, .rst_n, .dq_rise(rx_rise), .dq_fall(rx_fall),
        .align, .bitslip, .par_data(rx_data), .par_valid(rx_valid));

    hbm3_phy_training #(.TRAIN_PAT_A(PAT_A), .TRAIN_PAT_B(PAT_B)) u_tr (
        .wck, .rst_n, .start, .rx_valid, .rx_data,
        .align, .bitslip, .tx_pattern_en, .done, .ok, .locked);

    int nlock, err = 0, dchk = 0, synced = 0;
    logic [SER-1:0] prev0;
    integer ci, q;
    always_comb begin
        nlock = 0;
        for (ci = 0; ci < LANES; ci = ci + 1) if (locked[ci]) nlock++;
    end

    // egitimden SONRA veri dogrulama
    always_ff @(posedge wck) begin
        if (rst_n && done && ok && !tx_pattern_en && rx_valid) begin
            dchk <= dchk + 1;
            if (dchk > 4) begin
                for (ci = 0; ci < LANES; ci = ci + 1)
                    if (rx_data[ci*SER +: SER] !== (rx_data[0 +: SER] + SER'(ci))) begin
                        err <= err + 1;
                        if (err < 3) $display("  SERIT %0d: %02h (beklenen %02h)", ci,
                            rx_data[ci*SER +: SER], rx_data[0 +: SER] + SER'(ci));
                    end
                if (!synced) begin synced <= 1; prev0 <= rx_data[0 +: SER]; end
                else begin
                    if (rx_data[0 +: SER] !== (prev0 + 1'b1)) begin
                        err <= err + 1;
                        if (err < 3) $display("  SIRA: %02h -> %02h", prev0, rx_data[0 +: SER]);
                    end
                    prev0 <= rx_data[0 +: SER];
                end
            end
        end
    end

    initial begin
        repeat (10) @(posedge wck);
        rst_n = 1;
        repeat (8) @(posedge wck);
        $display("HBM3_PHY_LINK: egitim baslatiliyor (%0d serit, serit basina 0..%0d bit kayma)",
                 LANES, SER-1);
        @(negedge wck); start = 1; @(posedge wck); @(negedge wck); start = 0;
        wait (done);
        if (ok) begin
            $display("HBM3_PHY_LINK: EGITIM BASARILI -- %0d/%0d serit kilitlendi", nlock, LANES);
            $display("  serit:kayma->kilitlenen_sel  0:0->%0d 1:1->%0d 2:2->%0d 3:3->%0d 4:4->%0d 5:5->%0d 6:6->%0d 7:7->%0d",
                u_rx.g_lane[0].u_des.sel, u_rx.g_lane[1].u_des.sel,
                u_rx.g_lane[2].u_des.sel, u_rx.g_lane[3].u_des.sel,
                u_rx.g_lane[4].u_des.sel, u_rx.g_lane[5].u_des.sel,
                u_rx.g_lane[6].u_des.sel, u_rx.g_lane[7].u_des.sel);
        end
        else begin
            $display("HBM3_PHY_LINK: EGITIM BASARISIZ -- yalnizca %0d/%0d serit", nlock, LANES);
            $fatal(1, "");
        end
        wait (dchk >= 40);
        if (err == 0)
            $display("HBM3_PHY_LINK: EGITIM SONRASI VERI PASS -- %0d beat x %0d bit = %0d bit bit-birebir",
                     dchk, WIDTH, dchk*WIDTH);
        else begin
            $display("HBM3_PHY_LINK: veri BASARISIZ -- %0d hata", err); $fatal(1, "");
        end
        $display("HBM3_PHY_LINK: BITTI");
        $finish;
    end
    initial begin #6000; $display("HBM3_PHY_LINK: ZAMAN ASIMI (done=%0b ok=%0b kilitli=%0d dchk=%0d)",
                                  done, ok, nlock, dchk); $fatal(1,""); end
endmodule
