// Reset dagitim tamponu -- YUKSEK FANOUT'U KIRMAK ICIN.
//
// NEDEN AYRI BIR MODUL
//   Yosys'in `opt_merge` pass'i ozdes registerlari birlestirir. Reset
//   kopyalarini korumak icin IKI yol denendi ve IKISI DE BASARISIZ OLDU
//   (bkz. HATALAR.md HATA 21):
//     1) `(* keep = "true" *)`  -> nitelik WIRE'a yapisir, opt_merge HUCREDE
//        arar. Kopyalar sessizce tek registera indi.
//     2) Kaydirma zinciri      -> opt_merge'u GERCEKTEN yendi, ama her kopyayi
//        bir cevrim SONRA serbest biraktigi icin kuyruk<->scheduler el
//        sikismasi bozuldu; tb_hbm3_800g_full_top cift-gonderim yakaladi.
//
//   UCUNCU yol calisiyor: `(* keep_hierarchy *)` ile AYRI BIR MODUL.
//   Yosys bu modulu duzlestirmez, dolayisiyla ornekler ayri kalir ve
//   opt_merge onlari birlestiremez. Olculdu: 4 ornek -> 4 register hayatta.
//
//   VE EN ONEMLISI: tum kopyalar AYNI CEVRIMDE serbest kalir (hepsi ayni
//   kaynaktan, ayni saatle). Kademeli birakma sorunu YOKTUR.
//
// MALIYET: kopya basina bir flip-flop ve BIR CEVRIM ek reset gecikmesi
// (tum kopyalarda esit oldugu icin zararsiz).
(* keep_hierarchy *)
module hbm3_800g_rst_buf (
    input  logic clk,
    input  logic arst_n,      // asenkron reset kaynagi (dogrudan)
    input  logic rst_n_in,    // senkronize birakma sinyali
    output logic rst_n_out
);
    always_ff @(posedge clk or negedge arst_n)
        if (!arst_n) rst_n_out <= 1'b0;
        else         rst_n_out <= rst_n_in;
endmodule
