// PHY link egitimi (training) -- serit basina bit hizalama araması.
//
// GERCEK PHY'DE NE OLUR
//   Alici, gonderenin beat sinirinin ve her seridin faz kaymasinin nerede
//   oldugunu BILMEZ (tel uzunlugu, pad gecikmesi, PLL fazi). Bu yuzden link
//   acilirken BILINEN bir desen gonderilir; alici her seridi eslesene kadar
//   birer bit kaydirir. Bu, "write/read leveling"in dijital karsiligidir.
//
// DOGRULANMIS ZARF -- SINIR BURADA, OKUMADAN KULLANMAYIN
//   Bu egitim BIT seviyesinde hizalar. tb_hbm3_phy_link ile olculdu:
//       serit basina kayma 0..4 bit  -> GECER (bit-birebir)
//       serit basina kayma 5..7 bit  -> egitim "basarili" der AMA o seritler
//                                       BIR BEAT GERIDEN okur
//   Sebep: beat pencerenin en ustunde durur, yani nominal sel pencere
//   genisligiyle BIRLIKTE yukselir (olculdu: WIN=24'te 12, WIN=32'de 20).
//   Pencereyi buyutmek bu yuzden YARDIM ETMEZ; kayma nominalin uzerine
//   cikinca arama sarar ve bir beat asagida gecerli gorunen bir noktaya
//   kilitlenir.
//
//   EKSIK PARCA: serit basina BEAT SEVIYESI DESKEW (elastik tampon +
//   cerceve isaretcisi). Gercek PHY'lerde bit hizalama ve beat deskew AYRI
//   iki mekanizmadir; burada yalnizca birincisi vardir.
//   Bkz. docs/PLAN.md ADIM 1.
//
// ALGORITMA (serit basina bagimsiz)
//   1. `align` darbelenir -> beat siniri kurulur, sayaclar sifirlanir
//   2. Her gecerli beat'te serit verisi TRAIN_PATTERN ile karsilastirilir
//   3. Eslesen serit KILITLENIR ve bir daha kaydirilmaz
//   4. Eslemeyen serit icin `bitslip` darbelenir, deneme sayaci artar
//   5. Kaydirmadan sonra SETTLE beat beklenir (boru hatti bosalsin)
//   6. Tum seritler kilitlenirse basari; herhangi biri 2*SER_RATIO denemeyi
//      asarsa basarisizlik (o serit fiziksel olarak bozuk demektir)
//
// DESEN SECIMI -- BURADA GERCEK BIR TUZAK VAR
//   Ilk surumde TEK bir desen her beat gonderiliyordu. Test bunu yakaladi:
//   egitim "basarili" dedi ama kayma >= 5 bit olan seritler BIR BEAT GERIDEN
//   okuyordu. Sebep: tek desenin periyodu tam olarak SER_RATIO bittir, yani
//   SER_RATIO'nun KATI kadar kaymis bir pencere de AYNI deseni gorur ve
//   egitim ilk (yanlis) eslesmede kilitlenir.
//
//   Bu, gercek PHY tasariminda bilinen bir tuzaktir: BEAT-DEGISMEZ bir desen
//   yalnizca BIT konumunu pinler, BEAT sinirini pinleyemez.
//
//   COZUM: IKI beat'lik bir dizi (PAT_A, PAT_B) gonderilir ve alici ARDISIK
//   IKI beat'te (PAT_A, PAT_B) gormeden kilitlenmez. Boylece arama uzayi
//   2*SER_RATIO bit olur ve tam-beat kaymasi da yakalanir.
//   Ikisi de donme simetrisiz ve birbirinden farkli secilmelidir.
`include "hbm3_800g_defs.svh"

module hbm3_phy_training #(
    parameter int DQ_LANES  = HBM3_DQ_BITS_PER_CHANNEL,
    parameter int SER_RATIO = HBM3_PHY_DATA_BITS_PER_CHANNEL / HBM3_DQ_BITS_PER_CHANNEL,
    parameter logic [7:0] TRAIN_PAT_A = 8'hA5,   // cift beat
    parameter logic [7:0] TRAIN_PAT_B = 8'h39,   // tek beat
    parameter int SETTLE   = 3                    // kaydirma sonrasi bekleme
)(
    input  logic wck,
    input  logic rst_n,
    input  logic start,                            // egitimi baslat (darbe)
    input  logic rx_valid,                         // alicidan gecerli beat
    input  logic [DQ_LANES*SER_RATIO-1:0] rx_data,
    output logic                align,             // aliciya: siniri kur
    output logic [DQ_LANES-1:0] bitslip,           // aliciya: serit kaydir
    output logic                tx_pattern_en,     // vericiye: deseni gonder
    output logic                done,
    output logic                ok,                // tum seritler kilitlendi
    output logic [DQ_LANES-1:0] locked             // teshis icin
);
    // Deserilestiricinin sel araligi 0..3*SER_RATIO'dur (bkz. o dosyadaki
    // "ARALIK NE KADAR OLMALI" notu). Tum uzayi taramak icin bir fazla.
    localparam int MAX_TRY   = 3 * SER_RATIO + 1;
    localparam int TRY_BITS  = $clog2(MAX_TRY + 1);
    localparam int SET_BITS  = $clog2(SETTLE + 1);

    typedef enum logic [2:0] {
        S_IDLE, S_ALIGN, S_SETTLE, S_CHECK, S_SLIP, S_DONE
    } state_t;
    state_t st;

    logic [TRY_BITS-1:0] tries [0:DQ_LANES-1];
    logic [SET_BITS-1:0] settle_cnt;
    logic [DQ_LANES-1:0] mismatch;
    logic                any_over;
    logic                phase_try;
    integer i;

    wire [SER_RATIO-1:0] exp_a = SER_RATIO'(TRAIN_PAT_A);
    wire [SER_RATIO-1:0] exp_b = SER_RATIO'(TRAIN_PAT_B);

    // Bir onceki gecerli beat -- (A,B) ARDISIKLIGINI aramak icin sart.
    logic [SER_RATIO-1:0] prev_beat [0:DQ_LANES-1];
    logic [DQ_LANES-1:0]  seq_hit;

    always_comb begin
        for (i = 0; i < DQ_LANES; i = i + 1) begin
            seq_hit[i]  = (prev_beat[i] === exp_a) &&
                          (rx_data[i*SER_RATIO +: SER_RATIO] === exp_b);
            mismatch[i] = !locked[i] && !seq_hit[i];
        end
    end

    always_comb begin
        any_over = 1'b0;
        for (i = 0; i < DQ_LANES; i = i + 1)
            if (!locked[i] && tries[i] >= TRY_BITS'(MAX_TRY)) any_over = 1'b1;
    end

    always_ff @(posedge wck or negedge rst_n) begin
        if (!rst_n) begin
            st            <= S_IDLE;
            locked        <= '0;
            bitslip       <= '0;
            align         <= 1'b0;
            tx_pattern_en <= 1'b0;
            done          <= 1'b0;
            ok            <= 1'b0;
            settle_cnt    <= '0;
            phase_try     <= 1'b0;
            for (i = 0; i < DQ_LANES; i = i + 1) begin
                tries[i] <= '0; prev_beat[i] <= '0;
            end
        end else begin
            bitslip <= '0;                 // varsayilan: tek cevrimlik darbe
            align   <= 1'b0;
            case (st)
                S_IDLE: begin
                    done <= 1'b0; ok <= 1'b0;
                    if (start) begin
                        locked        <= '0;
                        tx_pattern_en <= 1'b1;
                        for (i = 0; i < DQ_LANES; i = i + 1) tries[i] <= '0;
                        st <= S_ALIGN;
                    end
                end
                S_ALIGN: begin
                    align      <= 1'b1;    // beat sinirini kur
                    settle_cnt <= '0;
                    phase_try  <= 1'b0;
                    st         <= S_SETTLE;
                end
                S_SETTLE: begin
                    // Kaydirmanin/hizalamanin boru hattindan gecmesini bekle.
                    // prev_beat BURADA DA guncellenmeli; aksi halde S_CHECK'e
                    // girildiginde elde bayat bir "onceki beat" olur ve
                    // (A,B) ardisikligi hic yakalanamaz.
                    if (rx_valid) begin
                        for (i = 0; i < DQ_LANES; i = i + 1)
                            prev_beat[i] <= rx_data[i*SER_RATIO +: SER_RATIO];
                        if (settle_cnt == SET_BITS'(SETTLE)) st <= S_CHECK;
                        else settle_cnt <= settle_cnt + 1'b1;
                    end
                end
                S_CHECK: begin
                    if (rx_valid) begin
                        for (i = 0; i < DQ_LANES; i = i + 1) begin
                            prev_beat[i] <= rx_data[i*SER_RATIO +: SER_RATIO];
                            if (!locked[i] && seq_hit[i]) locked[i] <= 1'b1;
                        end
                        if (mismatch == '0) begin
                            st <= S_DONE; ok <= 1'b1;
                        end else if (any_over) begin
                            st <= S_DONE; ok <= 1'b0;
                        end else begin
                            // (A,B) fazini kacirmis olabiliriz: kaydirmadan
                            // ONCE bir beat daha bak. phase_try bunu sayar.
                            if (phase_try == 1'b1) begin
                                phase_try <= 1'b0;
                                st        <= S_SLIP;
                            end else begin
                                phase_try <= 1'b1;
                            end
                        end
                    end
                end
                S_SLIP: begin
                    // Yalnizca kilitlenmemis seritleri kaydir.
                    bitslip <= mismatch;
                    for (i = 0; i < DQ_LANES; i = i + 1)
                        if (mismatch[i]) tries[i] <= tries[i] + 1'b1;
                    settle_cnt <= '0;
                    phase_try  <= 1'b0;
                    st         <= S_SETTLE;
                end
                S_DONE: begin
                    done          <= 1'b1;
                    tx_pattern_en <= 1'b0;
                    if (start) st <= S_IDLE;   // yeniden egitim
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
