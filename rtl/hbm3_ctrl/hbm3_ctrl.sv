// HBM3 KONTROLCU (sentezlenebilir IP cekirdegi).
//
// Bu modul gercek silikonda yer alacak kismin TAMAMIDIR: host arayuzu,
// adres cozme, NUM_PC adet pseudo-channel kontrolcusu, DBI, refresh ve
// banka zamanlayici. DRAM'in KENDISI burada YOKTUR -- gercek HBM3'te DRAM
// ayri, istiflenmis kaliplardadir ve TSV/PHY uzerinden erisilir. Bu yuzden
// cmd_* sinyalleri burada GERCEK PORTLARDIR (gozlem taps'i degil):
//   cmd_* (out) -> PHY -> DRAM      cmd_rdata/cmd_rdbi (in) <- PHY <- DRAM
//
// Simulasyon icin davranissal DRAM'i baglayan sarmalayici: hbm3_top.sv
`timescale 1ns/1ps
`include "hbm3_defs.svh"

module hbm3_ctrl #(
    parameter int NUM_PC = NUM_PC_DEFAULT,
    parameter int AW     = $clog2(NUM_PC) + ROWBITS +
                           NBANK_AW + COLBITS
)(
    input  logic        clk,
    input  logic        rst_n,

    // ---- host istek/yanit arayuzu ----
    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [AW-1:0]   req_addr,
    input  logic [255:0]    req_wdata,
    output logic        rsp_valid,
    output logic [255:0]    rsp_rdata,
    output logic [$clog2(NUM_PC)-1:0] rsp_pc,
    // islenmemis is var mi (drain / guc yonetimi). Yazmalarin cevabi
    // olmadigindan "hepsi bitti mi" baska turlu gozlenemez.
    output logic        busy,

    // ---- DRAM/PHY komut arayuzu (PC basina, duzlestirilmis) ----
    output logic [NUM_PC-1:0]         cmd_valid,
    output logic [2*NUM_PC-1:0]       cmd_type,
    output logic [4*NUM_PC-1:0]       cmd_bank,
    output logic [ROWBITS*NUM_PC-1:0] cmd_row,
    output logic [COLBITS*NUM_PC-1:0] cmd_col,
    output logic [32*NUM_PC-1:0]      cmd_wdata,
    output logic [4*NUM_PC-1:0]       cmd_wdbi,
    output logic [7*NUM_PC-1:0]       cmd_wecc,       // ECC (Hamming SECDED)
    output logic [NUM_PC-1:0]         cmd_allbanks,   // PRE ile: PREA
    // ---- DRAM/PHY okuma verisi (gercek GIRIS) ----
    input  logic [32*NUM_PC-1:0]      cmd_rdata,
    input  logic [4*NUM_PC-1:0]       cmd_rdbi,
    input  logic [2*NUM_PC-1:0]       cmd_recc_stat,  // ECC durumu (PC basina 2 bit)
    // yapiskan ECC hata bayraklari (PC basina), host tarafindan okunur
    output logic [NUM_PC-1:0]         ecc_corrected_sticky,
    output logic [NUM_PC-1:0]         ecc_uncorrectable_sticky,

    // ---- B alt-kanali: GERCEK DDR (bkz. pc_channel.sv basligindaki yorum) ----
    output logic [COLBITS*NUM_PC-1:0] cmd_col_b,
    output logic [32*NUM_PC-1:0]      cmd_wdata_b,
    output logic [4*NUM_PC-1:0]       cmd_wdbi_b,
    output logic [7*NUM_PC-1:0]       cmd_wecc_b,
    input  logic [32*NUM_PC-1:0]      cmd_rdata_b,
    input  logic [4*NUM_PC-1:0]       cmd_rdbi_b,
    input  logic [2*NUM_PC-1:0]       cmd_recc_stat_b
);

    localparam PCIW = $clog2(NUM_PC);
    localparam CAW  = AW - PCIW;

    logic [NUM_PC-1:0]  ch_ready, ch_rspv, ch_busy;
    logic [255:0]       ch_rdata [NUM_PC];
    logic [NUM_PC-1:0]  rspv_d;

    wire [PCIW-1:0] in_pc = req_addr[AW-1 -: PCIW];

    assign req_ready = ch_ready[in_pc];
    // herhangi bir kanal mesgulse ya da bir yanit yolda ise
    assign busy      = (ch_busy != '0) || (ch_rspv != '0) || (rspv_d != '0);

    genvar g;
    generate for (g = 0; g < NUM_PC; g++) begin : g_pc
        wire        c_valid, c_allbanks;
        wire [1:0]  c_type;
        wire [3:0]  c_bank;
        wire [ROWBITS-1:0] c_row;
        wire [COLBITS-1:0] c_col;
        wire [31:0] c_wdata;
        wire [3:0]  c_wdbi;
        wire [6:0]  c_wecc;
        wire [COLBITS-1:0] c_col_b;
        wire [31:0] c_wdata_b;
        wire [3:0]  c_wdbi_b;
        wire [6:0]  c_wecc_b;

        assign cmd_valid[g]                  = c_valid;
        assign cmd_type[2*g +: 2]            = c_type;
        assign cmd_bank[4*g +: 4]            = c_bank;
        assign cmd_row[g*ROWBITS +: ROWBITS] = c_row;
        assign cmd_col[g*COLBITS +: COLBITS] = c_col;
        assign cmd_wdata[32*g +: 32]         = c_wdata;
        assign cmd_wdbi[4*g +: 4]            = c_wdbi;
        assign cmd_wecc[7*g +: 7]            = c_wecc;
        assign cmd_allbanks[g]               = c_allbanks;
        assign cmd_col_b[g*COLBITS +: COLBITS] = c_col_b;
        assign cmd_wdata_b[32*g +: 32]       = c_wdata_b;
        assign cmd_wdbi_b[4*g +: 4]          = c_wdbi_b;
        assign cmd_wecc_b[7*g +: 7]          = c_wecc_b;

        wire kick = req_valid && req_ready && (in_pc == PCIW'(g));

        pc_channel #(.AW(CAW)) u_ch (
            .clk, .rst_n,
            .req_valid (kick),
            .req_ready (ch_ready[g]),
            .req_write (req_write),
            .req_addr  (req_addr[CAW-1:0]),
            .req_wdata (req_wdata),
            .rsp_valid (ch_rspv[g]),
            .rsp_rdata (ch_rdata[g]),
            .cmd_valid (c_valid),
            .cmd_type  (c_type),
            .cmd_bank  (c_bank),
            .cmd_row   (c_row),
            .cmd_col   (c_col),
            .cmd_wdata (c_wdata),
            .cmd_wdbi  (c_wdbi),
            .cmd_wecc  (c_wecc),
            .cmd_allbanks(c_allbanks),
            .cmd_rdata (cmd_rdata[32*g +: 32]),
            .cmd_rdbi  (cmd_rdbi[4*g +: 4]),
            .cmd_recc_stat(cmd_recc_stat[2*g +: 2]),
            .ecc_corrected_sticky    (ecc_corrected_sticky[g]),
            .ecc_uncorrectable_sticky(ecc_uncorrectable_sticky[g]),
            .cmd_col_b  (c_col_b),
            .cmd_wdata_b(c_wdata_b),
            .cmd_wdbi_b (c_wdbi_b),
            .cmd_wecc_b (c_wecc_b),
            .cmd_rdata_b(cmd_rdata_b[32*g +: 32]),
            .cmd_rdbi_b (cmd_rdbi_b[4*g +: 4]),
            .cmd_recc_stat_b(cmd_recc_stat_b[2*g +: 2]),
            .refreshing(),
            .busy      (ch_busy[g])
        );
    end endgenerate

    // yanit toplama: kanal NBA ile verir -> bir cycle sonra yakala (HATA 2)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rspv_d <= '0;
            rsp_valid <= 0; rsp_rdata <= '0; rsp_pc <= '0;
        end else begin
            rspv_d    <= ch_rspv;
            rsp_valid <= 0;
            for (int i = 0; i < NUM_PC; i++) begin
                if (rspv_d[i]) begin
                    rsp_valid <= 1;
                    rsp_rdata <= ch_rdata[i];
                    rsp_pc    <= PCIW'(i);
`ifdef DEBUG
                    $display("[TOP] %0t pc=%0d rdata=%h", $time, i, ch_rdata[i]);
`endif
                end
            end
        end
    end

endmodule
