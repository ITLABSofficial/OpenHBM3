// WCK ureteci: CK'ya oranla 1:2 bolus (WCK 2x hiz simülasyonu: ce her 2 CK'da)
// Gercek HBM3: CK<=1.6GHz, WCK<=3.2GHz DDR -> 6.4Gbps
`timescale 1ns/1ps

module wck_div (
    input  logic clk,
    input  logic rst_n,
    output logic wck,
    output logic wck_ce      // veri beat hizalamasi icin enable
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) wck <= 0;
        else wck <= ~wck;
    end
    assign wck_ce = 1'b1; // simülasyonda her CK'da bir beat (DDR modeli davranissal)
endmodule
