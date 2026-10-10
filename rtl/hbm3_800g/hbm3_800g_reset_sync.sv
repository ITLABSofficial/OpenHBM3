// Asynchronous assertion, synchronous deassertion reset conditioner.
// Each clock domain must use its own instance.
//
// FANOUT AGACI (2026-08-26, HATA 21 sonrasi yeniden yazildi):
// ASAP7 sentez olcumunde bu modulun cikisi TEK bir minimum boyutlu kapi
// uzerinden binlerce flip-flop suruyordu (Korpus'ta 14,816 yuk, 71,924 ps).
//
// ILK DENEME BASARISIZDI: kopyalar `(* keep = "true" *)` ile korunmaya
// calisildi, ama yosys'in `opt_merge` pass'i `keep` niteligini HUCREDE arar,
// SystemVerilog'daki nitelik ise WIRE'a yapisir. Dort kopya tek registera
// indi ve replikasyon netliste HIC OLUSMADI (bkz. HATALAR.md HATA 21).
//
// IKINCI DENEME DE BASARISIZDI -- ve bu daha ogreticiydi: kopyalar bir
// KAYDIRMA ZINCIRINE cevrildi (her D girisi farkli oldugu icin `opt_merge`
// gercekten birlestiremedi; 4 kopya icin 6 FF hayatta kaldi, olculdu).
// Ama zincir, her kopyayi bir oncekinden BIR CEVRIM SONRA serbest birakir ve
// tb_hbm3_800g_full_top BUNU YAKALADI:
//     FATAL: PHY duplicated transaction lane=5 seq=0
// Iki farkli baglama sirasi denendi, ikisi de ayni hatayi verdi -- yani sorun
// sira degil, KADEMELENDIRMENIN KENDISI. Ayni saat alanindaki bloklar reset'ten
// AYNI CEVRIMDE cikmak zorundadir; aksi halde kuyruk<->scheduler el sikismasi
// tutarsiz bir pencerede calisir. (Bu kural zaten bu dosyanin ilk surumunde
// yaziliydi; zincir onu ihlal ediyordu.)
//
// SIMDIKI COZUM: fanout tamponlama FIZIKSEL SENTEZIN isidir, RTL'in degil.
// Tum kopyalar ayni cevrimde serbest kalir (sentez bunlari tek registera
// indirebilir, sorun degil); yuk dagitimini SDC'deki `set_max_fanout` ile
// OpenROAD `repair_design` yapar. Bu ayni mekanizma gt2n_fork'ta zaten
// 206 MHz -> 1,260 MHz toparlamasi saglamisti.
module hbm3_800g_reset_sync #(
    parameter int FANOUT = 1
)(
    input  logic clk,
    input  logic async_rst_n,
    output logic sync_rst_n,                   // ana cikis (geriye uyum)
    output logic [FANOUT-1:0] sync_rst_n_fan   // kayitli dagitim kopyalari
);
    (* ASYNC_REG = "TRUE" *) logic [1:0] release_pipe;

    always_ff @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n)
            release_pipe <= 2'b00;
        else
            release_pipe <= {release_pipe[0], 1'b1};
    end

    assign sync_rst_n = release_pipe[1];

    // fan_q captures release_pipe[0] on the same clock edge that release_pipe[1]
    // is updated, ensuring that sync_rst_n and all sync_rst_n_fan replicas
    // deassert synchronously on the EXACT SAME clock cycle (cycle 2).
    logic [FANOUT-1:0] fan_q;
    always_ff @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) fan_q <= '0;
        else              fan_q <= {FANOUT{release_pipe[0]}};
    end

    assign sync_rst_n_fan = fan_q;
endmodule
