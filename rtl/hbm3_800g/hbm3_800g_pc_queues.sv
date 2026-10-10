// One independent, synthesizable request FIFO per HBM pseudo-channel.
// These queues are in CK domain.  They are deliberately *before* the
// CK-to-WCK CDC/gearbox boundary: a production PHY owns that boundary.
`include "hbm3_800g_defs.svh"

module hbm3_800g_pc_queues #(
    parameter int QUEUE_DEPTH = 4,
    parameter int PTR_BITS = $clog2(QUEUE_DEPTH)
) (
    input  logic clk_ck,
    input  logic rst_n,
    input  logic [HBM3_PSEUDO_CHANNELS-1:0] in_valid,
    output logic [HBM3_PSEUDO_CHANNELS-1:0] in_ready,
    input  logic [HBM3_PSEUDO_CHANNELS*HBM3_ADDR_BITS-1:0] in_addr,
    input  logic [HBM3_PSEUDO_CHANNELS*HBM3_HOST_DATA_BITS-1:0] in_wdata,

    output logic [HBM3_PSEUDO_CHANNELS-1:0] out_valid,
    input  logic [HBM3_PSEUDO_CHANNELS-1:0] out_ready,
    output logic [HBM3_PSEUDO_CHANNELS*HBM3_ADDR_BITS-1:0] out_addr,
    output logic [HBM3_PSEUDO_CHANNELS*HBM3_HOST_DATA_BITS-1:0] out_wdata
);
    // verilator lint_off MULTIDRIVEN
    // GEREKCE: asagidaki diziler PC BASINA bolunmustur (g_q generate); her
    // ornek YALNIZCA kendi indeksini surer, gercek cok-suruculu sinyal yok.
    // Arac diziyi tek sinyal sayip "farkli clocking" diyor, cunku her ornegin
    // reset'i rst_fan[grq]. Kasitlidir: tek reset registeri 10,483 flip-flop
    // suruyordu (ASAP7 sentezinde olculdu).
    // (NOT: bu yorumun hicbir satiri "V-e-r-i-l-a-t-o-r" ile BASLAMAMALI.)
    logic [PTR_BITS-1:0] wr_ptr [0:HBM3_PSEUDO_CHANNELS-1];
    logic [PTR_BITS-1:0] rd_ptr [0:HBM3_PSEUDO_CHANNELS-1];
    logic [PTR_BITS:0] count [0:HBM3_PSEUDO_CHANNELS-1];
    // verilator lint_on MULTIDRIVEN
    localparam logic [PTR_BITS:0] QUEUE_DEPTH_COUNT = QUEUE_DEPTH[PTR_BITS:0];
    logic [HBM3_PSEUDO_CHANNELS-1:0] push, pop;
    integer comb_pc, seq_pc;

    // KUYRUK BASI KAYITLI KOPYASI
    // out_addr/out_wdata ONCEDEN `mem[pc][rd_ptr[pc]]` ile KOMBINASYONEL
    // suruluyordu: 32 kanal x 256-bit x QUEUE_DEPTH:1 mux, dogrudan cikis
    // portunda. Ayni orüntü gt2n_fork/pc_channel.sv'de olculen kritik yolun
    // uzerindeydi ve orada `head_wd` register'i ile cozulmustu.
    // Burada da kuyruk basi surekli bir register'da tutulur; cikislar
    // dogrudan o register'dan surulur, mux artik cikis yolunda degil.
    // GECIKME DEGISMEZ: head, bir onceki kenarda `rd_nxt` ile yuklendigi
    // icin out_* ayni cevrimde ayni degeri tasir (asagida dogrulandi).
    // verilator lint_off MULTIDRIVEN
    logic [HBM3_ADDR_BITS-1:0]      head_addr [0:HBM3_PSEUDO_CHANNELS-1];
    logic [HBM3_HOST_DATA_BITS-1:0] head_data [0:HBM3_PSEUDO_CHANNELS-1];
    logic [PTR_BITS-1:0]            rd_nxt       [0:HBM3_PSEUDO_CHANNELS-1];
    // verilator lint_on MULTIDRIVEN
    logic                           push_to_head [0:HBM3_PSEUDO_CHANNELS-1];

    initial begin
        if (QUEUE_DEPTH < 2 || (QUEUE_DEPTH & (QUEUE_DEPTH - 1)) != 0)
            $error("QUEUE_DEPTH must be a power of two and at least 2");
    end

    always_comb begin
        for (comb_pc = 0; comb_pc < HBM3_PSEUDO_CHANNELS; comb_pc = comb_pc + 1) begin
            out_valid[comb_pc] = (count[comb_pc] != 0);
            pop[comb_pc] = out_valid[comb_pc] && out_ready[comb_pc];
            // Permit a push while a full queue pops: sustained one line/CK/PC.
            // RESET PENCERESI: ic reset kopyalari (rst_fan) ham rst_n'den BIR
            // CEVRIM SONRA serbest kalir. O tek cevrimde count=0 goruldugu icin
            // in_ready YUKSEK cikar; host veri gonderir ve veri DUSER.
            // tb_hbm3_800g_full_top bunu yakaladi: accepted=640 received=608.
            // (Ayni hata gearbox'ta da yasandi -- bkz. o dosyadaki not.)
            in_ready[comb_pc] = rst_fan[comb_pc] &&
                                ((count[comb_pc] < QUEUE_DEPTH_COUNT) || pop[comb_pc]);
            push[comb_pc] = in_valid[comb_pc] && in_ready[comb_pc];
            out_addr[comb_pc*HBM3_ADDR_BITS +: HBM3_ADDR_BITS] = head_addr[comb_pc];
            out_wdata[comb_pc*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS] = head_data[comb_pc];
        end
    end

    // Kuyruk basi register'i icin bir sonraki okuma slotu ve bypass kosulu.
    // AYRI surekli atamalar olarak yazildi (always_comb icinde DEGIL):
    // lint araci cok sinyalli bir always_comb blogunu tek parca sayip
    // out_valid -> scheduler -> out_ready -> pop zincirini yanlislikla
    // dairesel gorebiliyordu. Eleman bazinda assign ile bu belirsizlik yok.
    // (NOT: bu yorum satiri "V-e-r-i-l-a-t-o-r" kelimesiyle BASLAMAMALI --
    //  arac onu pragma sanip BADVLTPRAGMA hatasi veriyor.)
    genvar gpc;
    generate for (gpc = 0; gpc < HBM3_PSEUDO_CHANNELS; gpc = gpc + 1) begin : g_head_ctl
        assign rd_nxt[gpc]       = pop[gpc] ? (rd_ptr[gpc] + 1'b1) : rd_ptr[gpc];
        assign push_to_head[gpc] = push[gpc] && (wr_ptr[gpc] == rd_nxt[gpc]);
    end endgenerate

    // RESET FANOUT: 32 pseudo-channel'in TAMAMI tek reset registerinden
    // suruluyordu. ASAP7 sentezinde olculdu: 10,483 yuk, 49,854 ps -- gearbox
    // duzeltildikten SONRA en kotu yol buraya tasindi. Ayni recete: her PC
    // kendi (* keep_hierarchy *) reset kopyasini kullanir, hepsi AYNI
    // CEVRIMDE serbest kalir (bkz. hbm3_800g_rst_buf.sv, HATALAR.md HATA 21).
    logic [HBM3_PSEUDO_CHANNELS-1:0] rst_fan;
    genvar grq;
    generate for (grq = 0; grq < HBM3_PSEUDO_CHANNELS; grq = grq + 1) begin : g_qrst
        hbm3_800g_rst_buf u_rb (.clk(clk_ck), .arst_n(rst_n),
                                .rst_n_in(rst_n), .rst_n_out(rst_fan[grq]));
    end endgenerate

    // verilator lint_off MULTIDRIVEN
    // GEREKCE: asagidaki diziler PC BASINA bolunmustur; her generate ornegi
    // YALNIZCA kendi indeksini surer. Arac diziyi tek sinyal sayip "farkli
    // clocking" diyor (her ornegin reset'i rst_fan[grq]). Kasitlidir.
    // (NOT: bu yorumun hicbir satiri "V-e-r-i-l-a-t-o-r" ile BASLAMAMALI.)
    generate for (grq = 0; grq < HBM3_PSEUDO_CHANNELS; grq = grq + 1) begin : g_q
        logic [HBM3_ADDR_BITS-1:0] addr_mem [0:QUEUE_DEPTH-1];
        logic [HBM3_HOST_DATA_BITS-1:0] data_mem [0:QUEUE_DEPTH-1];

        always_ff @(posedge clk_ck or negedge rst_fan[grq]) begin
            if (!rst_fan[grq]) begin
                wr_ptr[grq] <= '0;
                rd_ptr[grq] <= '0;
                count[grq] <= '0;
                head_addr[grq] <= '0;
                head_data[grq] <= '0;
            end else begin
                // kuyruk basi kopyasini bir sonraki okuma slotuna gore guncelle;
                // ayni cevrimde gelen push TAM O slota yaziyorsa gelen veriyi al
                if (push_to_head[grq]) begin
                    head_addr[grq] <= in_addr[grq*HBM3_ADDR_BITS +: HBM3_ADDR_BITS];
                    head_data[grq] <= in_wdata[grq*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS];
                end else begin
                    head_addr[grq] <= addr_mem[rd_nxt[grq]];
                    head_data[grq] <= data_mem[rd_nxt[grq]];
                end
                case ({push[grq], pop[grq]})
                    2'b10: begin
                        addr_mem[wr_ptr[grq]] <= in_addr[grq*HBM3_ADDR_BITS +: HBM3_ADDR_BITS];
                        data_mem[wr_ptr[grq]] <= in_wdata[grq*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS];
                        wr_ptr[grq] <= wr_ptr[grq] + 1'b1;
                        count[grq] <= count[grq] + 1'b1;
                    end
                    2'b01: begin
                        rd_ptr[grq] <= rd_ptr[grq] + 1'b1;
                        count[grq] <= count[grq] - 1'b1;
                    end
                    2'b11: begin
                        addr_mem[wr_ptr[grq]] <= in_addr[grq*HBM3_ADDR_BITS +: HBM3_ADDR_BITS];
                        data_mem[wr_ptr[grq]] <= in_wdata[grq*HBM3_HOST_DATA_BITS +: HBM3_HOST_DATA_BITS];
                        wr_ptr[grq] <= wr_ptr[grq] + 1'b1;
                        rd_ptr[grq] <= rd_ptr[grq] + 1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end endgenerate
    // verilator lint_on MULTIDRIVEN

endmodule
