// Serilestirici -> deserilestirici geri dongusu.
//
// ARTAN DESEN kullanilir (0,1,2,...): boylece boru hatti gecikmesini ONCEDEN
// BILMEYE GEREK KALMADAN hem BIT-BIREBIRLIK hem SIRA dogrulanabilir --
// senkronizasyon sonrasi her beat bir oncekinin +1'i olmalidir.
`timescale 1ns/1ps
module tb_hbm3_phy_serdes;
    localparam int SER  = 8;
    localparam int HALF = SER/2;
    localparam int N    = 80;

    logic wck = 0, rst_n = 0;
    always #0.108 wck = ~wck;             // ~4.6 GHz

    logic           load, align, align_arm, bitslip = 0;
    logic [SER-1:0] pdata;
    logic           dq_rise, dq_fall;
    logic [SER-1:0] rdata;
    logic           rvalid;

    hbm3_phy_serializer #(.SER_RATIO(SER)) u_ser (
        .wck, .rst_n, .load, .pdata, .dq_rise, .dq_fall);
    hbm3_phy_deserializer #(.SER_RATIO(SER)) u_des (
        .wck, .rst_n, .dq_rise, .dq_fall, .align, .bitslip,
        .pdata(rdata), .pvalid(rvalid));

    logic [$clog2(HALF)-1:0] lcnt;
    always_ff @(posedge wck or negedge rst_n)
        if (!rst_n) lcnt <= '0; else lcnt <= (lcnt == HALF-1) ? '0 : lcnt + 1'b1;
    assign load  = (lcnt == 0);
    assign align = load && align_arm;
    always_ff @(posedge wck or negedge rst_n)
        if (!rst_n)    align_arm <= 1'b1;
        else if (load) align_arm <= 1'b0;   // sinir SADECE bir kez kurulur

    // artan desen
    always_ff @(posedge wck or negedge rst_n)
        if (!rst_n)    pdata <= '0;
        else if (load) pdata <= pdata + 1'b1;

    int got = 0, err = 0, synced = 0;
    logic [SER-1:0] prev;

    always_ff @(posedge wck) begin
        if (rst_n && rvalid) begin
            got <= got + 1;
            if (got >= 6) begin              // boru hatti dolsun
                if (!synced) begin
                    synced <= 1; prev <= rdata;
                end else begin
                    if (rdata !== (prev + 1'b1)) begin
                        err <= err + 1;
                        if (err < 4)
                            $display("  SIRA HATASI beat %0d: %02h -> %02h (beklenen %02h)",
                                     got, prev, rdata, prev + 1'b1);
                    end
                    prev <= rdata;
                end
            end
        end
    end

    initial begin
        repeat (8) @(posedge wck);
        rst_n = 1;
        wait (got >= N);
        if (err == 0)
            $display("HBM3_PHY_SERDES: geri dongu PASS -- %0d beat, bit-birebir, sira dogru", got);
        else begin
            $display("HBM3_PHY_SERDES: BASARISIZ -- %0d sira/icerik hatasi", err);
            $fatal(1, "");
        end

        // bitslip gercekten kaydiriyor mu: bir darbe sonrasi dizi BOZULMALI
        begin
            int e0; e0 = err;
            @(negedge wck); bitslip = 1; @(posedge wck); @(negedge wck); bitslip = 0;
            repeat (6*HALF) @(posedge wck);
            if (err > e0)
                $display("HBM3_PHY_SERDES: bitslip pencereyi kaydirdi PASS (dizi bozuldu)");
            else
                $display("HBM3_PHY_SERDES: UYARI bitslip etkisiz gorundu");
        end

        // 2*SER bitslip -> tam tur, hizalama GERI GELMELI
        begin
            int e1;
            for (int i = 0; i < 2*SER - 1; i++) begin
                @(negedge wck); bitslip = 1; @(posedge wck); @(negedge wck); bitslip = 0;
                repeat (HALF) @(posedge wck);
            end
            synced = 0; repeat (4*HALF) @(posedge wck);
            e1 = err; repeat (20*HALF) @(posedge wck);
            if (err == e1)
                $display("HBM3_PHY_SERDES: 2x%0d bitslip sonrasi hizalama GERI GELDI PASS", SER);
            else
                $display("HBM3_PHY_SERDES: UYARI tam tur sonrasi %0d hata", err - e1);
        end
        $display("HBM3_PHY_SERDES: BITTI");
        $finish;
    end

    initial begin
        #3000;
        $display("HBM3_PHY_SERDES: ZAMAN ASIMI (got=%0d err=%0d)", got, err);
        $fatal(1, "");
    end
endmodule
