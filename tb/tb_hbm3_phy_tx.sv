// Kanal seviyesi TX testi: 512 bit -> 64 serit -> 64 deserilestirici -> 512 bit.
// Bit-birebir ve sira dogrulanir. Artan desen kullanilir (gecikme bilinmeden).
`timescale 1ns/1ps
`include "hbm3_800g_defs.svh"
module tb_hbm3_phy_tx;
    localparam int LANES = HBM3_DQ_BITS_PER_CHANNEL;                       // 64
    localparam int SER   = HBM3_PHY_DATA_BITS_PER_CHANNEL / LANES;         // 8
    localparam int HALF  = SER/2;
    localparam int WIDTH = LANES*SER;                                      // 512
    localparam int N     = 48;

    logic wck = 0, rst_n = 0;
    always #0.108 wck = ~wck;

    logic              par_valid = 0, par_ready;
    logic [WIDTH-1:0]  par_data;
    logic [LANES-1:0]  dq_rise, dq_fall;
    logic              dq_active, beat_start;

    hbm3_phy_tx_channel u_tx (
        .wck, .rst_n, .par_valid, .par_ready, .par_data,
        .dq_rise, .dq_fall, .dq_active, .beat_start);

    // alici: serit basina bir deserilestirici
    logic [WIDTH-1:0] rx_data;
    logic [LANES-1:0] rx_valid;
    logic             align, align_arm;
    assign align = beat_start && align_arm;
    always_ff @(posedge wck or negedge rst_n)
        if (!rst_n)           align_arm <= 1'b1;
        else if (beat_start)  align_arm <= 1'b0;

    genvar l;
    generate for (l = 0; l < LANES; l = l + 1) begin : g_rx
        hbm3_phy_deserializer #(.SER_RATIO(SER)) u_des (
            .wck, .rst_n, .dq_rise(dq_rise[l]), .dq_fall(dq_fall[l]),
            .align, .bitslip(1'b0),
            .pdata(rx_data[l*SER +: SER]), .pvalid(rx_valid[l]));
    end endgenerate

    // artan desen: her serit AYNI sayaci tasir -> tum 512 bit ongorulebilir
    logic [SER-1:0] pat;
    integer li;
    always_ff @(posedge wck or negedge rst_n) begin
        if (!rst_n) begin
            pat <= '0; par_valid <= 1'b0;
        end else begin
            par_valid <= 1'b1;
            if (par_ready && par_valid) pat <= pat + 1'b1;
        end
    end
    always_comb begin
        par_data = '0;
        for (li = 0; li < LANES; li = li + 1)
            par_data[li*SER +: SER] = pat + SER'(li);
    end

    int got = 0, err = 0, synced = 0;
    logic [SER-1:0] prev0;
    integer ci;
    always_ff @(posedge wck) begin
        if (rst_n && rx_valid[0]) begin
            got <= got + 1;
            if (got >= 6) begin
                // 1) tum seritler birbirine gore dogru ofsette mi
                for (ci = 0; ci < LANES; ci = ci + 1)
                    if (rx_data[ci*SER +: SER] !== (rx_data[0 +: SER] + SER'(ci))) begin
                        err <= err + 1;
                        if (err < 3) $display("  SERIT %0d hatali: %02h (beklenen %02h)",
                            ci, rx_data[ci*SER +: SER], rx_data[0 +: SER] + SER'(ci));
                    end
                // 2) beat'ler sirali mi
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
        repeat (8) @(posedge wck);
        rst_n = 1;
        wait (got >= N);
        if (err == 0)
            $display("HBM3_PHY_TX: PASS -- %0d beat x %0d serit x %0d bit = %0d bit, bit-birebir",
                     got, LANES, SER, got*WIDTH);
        else begin
            $display("HBM3_PHY_TX: BASARISIZ -- %0d hata", err); $fatal(1, "");
        end
        $display("HBM3_PHY_TX: veri yolu sozlesmesi: %0d bit @ PHY_CK -> %0d serit x %0d bit",
                 WIDTH, LANES, SER);
        $finish;
    end
    initial begin #4000; $display("HBM3_PHY_TX: ZAMAN ASIMI (got=%0d)", got); $fatal(1,""); end
endmodule
