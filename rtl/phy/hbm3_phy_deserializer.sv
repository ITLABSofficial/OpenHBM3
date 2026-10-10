// Tek serit N:1 deserilestirici, DDR girisli, BIT-SLIP hizalamali.
//
// Serilestiricinin tersi. Gercek bir baglantida alici, gonderenin beat
// sinirinin NEREDE oldugunu bilmez (kablo gecikmesi, PLL fazi). Iki
// mekanizma bunu cozer ve IKISI DE burada:
//
//   `align`   -- beat SINIRINI kurar (kac cevrimde bir yayinlanacagi).
//                Egitim FSM'i bilinen deseni gonderirken bunu darbeler.
//                Gercek PHY'de bu "read leveling"in dijital karsiligidir.
//   `bitslip` -- ornekleme penceresini BIR BIT kaydirir. Egitim, eslesene
//                kadar darbeler.
//
// PENCERE -- NOMINAL `sel` DEGERI PENCERE GENISLIGINE BAGLIDIR
//   window WIN = 3*SER_RATIO bit; her WCK cevriminde iki bit MSB'den girer.
//   Bir beat tam toplandiginda EN USTTE durur: window[WIN-1 : WIN-SER_RATIO].
//   Dolayisiyla hizali secim ofseti WIN-SER_RATIO = 2*SER_RATIO'dur.
//
//   BU BIR HATA KAYNAGI OLDU: pencere 2*SER_RATIO'dan 3*SER_RATIO'ya
//   genisletilirken nominal `sel` guncellenmedi (SER_RATIO'da kaldi) ve
//   deserilestirici SUREKLI BIR BEAT GERIDEN okudu. Birim testi bunu
//   YAKALAYAMADI cunku artan desende sabit bir beat gecikmesi de "her deger
//   bir oncekinin +1'i" kontrolunu gecer. Link testi (serit basina farkli
//   kayma) yakaladi. Ders: sabit ofset hatalari ancak SERITLER BIRBIRINDEN
//   FARKLI kaydiginda gorunur.
//
//   `sel` 0..WIN-SER_RATIO araligindadir; bitslip tum bu uzayi tarar.
//
//   ARALIK NE KADAR OLMALI -- IKINCI HATA BURADAN CIKTI
//   Ilk denemede WIN=3*SER_RATIO, sel araligi 0..16 idi. Link testi (serit
//   basina 0..7 bit kayma) sunu gosterdi:
//       serit 0..4 (kayma 0..4) -> sel 12,13,14,15,16   DOGRU
//       serit 5..7 (kayma 5..7) -> sel  9,10,11         SARMIS, BIR BEAT GERI
//   Dogru sel = 12 + kayma, yani kayma 5 icin 17 gerekiyordu ama ust sinir
//   16'ydi. Arama sarip bir beat asagida kilitlendi ve egitim "basarili"
//   dedi -- cunku (A,B) dizisi orada da gorunuyordu.
//
//   Ayrica NOMINAL sel 12 cikti, 16 degil: kanalin boru hatti derinligine
//   bagli. TAM DA BU YUZDEN egitim vardir -- nominal sabit degildir.
//
//   Bu yuzden WIN = 4*SER_RATIO, sel araligi 0..3*SER_RATIO. Bedeli serit
//   basina 8 flip-flop; kazanci nominal +/- tam bir beat kayma butcesi.
//
// BIT SIRASI: dq_rise once gonderilir, yani stream'de daha ESKIdir ve
// pencerede daha ASAGIDA durur. SER_RATIO=8 icin hizali durumda
// d0 -> window[8] ... d7 -> window[15].
module hbm3_phy_deserializer #(
    parameter int SER_RATIO = 8
)(
    input  logic                 wck,
    input  logic                 rst_n,
    input  logic                 dq_rise,
    input  logic                 dq_fall,
    input  logic                 align,     // beat sinirini kur (bir cevrim)
    input  logic                 bitslip,   // pencereyi bir bit kaydir
    output logic [SER_RATIO-1:0] pdata,
    output logic                 pvalid
);
    localparam int HALF     = SER_RATIO / 2;
    localparam int WIN      = 4 * SER_RATIO;
    localparam int CNT_BITS = (HALF > 1) ? $clog2(HALF) : 1;
    localparam int SEL_MAX  = WIN - SER_RATIO;   // = 3*SER_RATIO
    localparam int SEL_BITS = $clog2(SEL_MAX + 1);

    logic [WIN-1:0]      window;
    logic [CNT_BITS-1:0] cnt;
    logic [SEL_BITS-1:0] sel;
    logic [WIN-1:0]      window_nxt;

    // Bu cevrimde giren iki bit DAHIL edilmis pencere. pdata'yi bundan
    // secmek gerekir; `window` NBA ile guncellendigi icin henuz eskidir.
    assign window_nxt = {dq_fall, dq_rise, window[WIN-1:2]};

    always_ff @(posedge wck or negedge rst_n) begin
        if (!rst_n) begin
            window <= '0;
            cnt    <= '0;
            sel    <= SEL_BITS'(SEL_MAX);
            pdata  <= '0;
            pvalid <= 1'b0;
        end else begin
            window <= window_nxt;

            if (bitslip)
                sel <= (sel == '0) ? SEL_BITS'(SEL_MAX) : (sel - 1'b1);

            if (align) begin
                // Sinir yeniden kuruluyor: sayaci sifirla, bu cevrim yayinlama.
                cnt    <= '0;
                pvalid <= 1'b0;
            end else if (cnt == CNT_BITS'(HALF - 1)) begin
                cnt    <= '0;
                pvalid <= 1'b1;
                pdata  <= window_nxt[sel +: SER_RATIO];
            end else begin
                cnt    <= cnt + 1'b1;
                pvalid <= 1'b0;
            end
        end
    end
endmodule
