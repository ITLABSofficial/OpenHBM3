// HBM3 SIMULASYON KOSUMU (test harness) -- SENTEZLENEBILIR DEGILDIR.
//
// hbm3_ctrl (gercek IP cekirdegi) + NUM_PC adet davranissal dram_model'i
// birbirine baglar. Gercek silikonda DRAM ayri istiflenmis kaliplardadir;
// bu sarmalayici sadece testbench'lerin tek bir modul ornekleyip uctan uca
// yaz/oku dogrulamasi yapabilmesi icindir.
//
// Sentez / OpenLane hedefi: hbm3_ctrl.sv  (bkz. docs/ARCHITECTURE.md)
`timescale 1ns/1ps
`include "hbm3_defs.svh"

module hbm3_top #(
    parameter int NUM_PC = NUM_PC_DEFAULT,
    parameter int AW     = $clog2(NUM_PC) + ROWBITS +
                           NBANK_AW + COLBITS
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [AW-1:0]   req_addr,
    input  logic [255:0]    req_wdata,
    output logic        rsp_valid,
    output logic [255:0]    rsp_rdata,
    output logic [$clog2(NUM_PC)-1:0] rsp_pc,
    output logic        busy,
    output logic [NUM_PC-1:0] ecc_corrected_sticky,
    output logic [NUM_PC-1:0] ecc_uncorrectable_sticky,

    // SADECE SIMULASYON: hata enjeksiyonu (bkz. tb/tb_ecc_fault.sv).
    // PC basina: fault_valid[g], fault_key[15*g +: 15], fault_flip[39*g +: 39]
    input  logic [NUM_PC-1:0]         fault_valid,
    input  logic [15*NUM_PC-1:0]      fault_key,
    input  logic [39*NUM_PC-1:0]      fault_flip,

    // gozlem taps'i: asil veri yolu hbm3_ctrl <-> dram_model arasinda
    // ic wire'lar uzerinden gider; bunlar dalga formu/hata ayiklama icindir
    output logic [NUM_PC-1:0]         cmd_valid,
    output logic [2*NUM_PC-1:0]       cmd_type,
    output logic [4*NUM_PC-1:0]       cmd_bank,
    output logic [ROWBITS*NUM_PC-1:0] cmd_row,
    output logic [COLBITS*NUM_PC-1:0] cmd_col,
    output logic [32*NUM_PC-1:0]      cmd_wdata,
    output logic [4*NUM_PC-1:0]       cmd_wdbi,
    output logic [7*NUM_PC-1:0]       cmd_wecc,
    output logic [NUM_PC-1:0]         cmd_allbanks,
    output logic [32*NUM_PC-1:0]      cmd_rdata,
    output logic [4*NUM_PC-1:0]       cmd_rdbi,
    output logic [2*NUM_PC-1:0]       cmd_recc_stat
);

    // B alt-kanali (GERCEK DDR): sadece hbm3_ctrl<->dram_model arasi ic
    // baglanti -- hbm3_top'un KENDI disaridan gorunen port listesine
    // eklenmedi (mevcut testbench'ler degismeden calismaya devam eder).
    logic [COLBITS*NUM_PC-1:0] cmd_col_b_i;
    logic [32*NUM_PC-1:0]      cmd_wdata_b_i;
    logic [4*NUM_PC-1:0]       cmd_wdbi_b_i;
    logic [7*NUM_PC-1:0]       cmd_wecc_b_i;
    logic [32*NUM_PC-1:0]      cmd_rdata_b_i;
    logic [4*NUM_PC-1:0]       cmd_rdbi_b_i;
    logic [2*NUM_PC-1:0]       cmd_recc_stat_b_i;

    hbm3_ctrl #(.NUM_PC(NUM_PC)) u_ctrl (
        .clk, .rst_n,
        .req_valid, .req_ready, .req_write, .req_addr, .req_wdata,
        .rsp_valid, .rsp_rdata, .rsp_pc, .busy,
        .ecc_corrected_sticky, .ecc_uncorrectable_sticky,
        .cmd_valid, .cmd_type, .cmd_bank, .cmd_row, .cmd_col,
        .cmd_wdata, .cmd_wdbi, .cmd_wecc, .cmd_allbanks,
        .cmd_rdata (cmd_rdata),
        .cmd_rdbi  (cmd_rdbi),
        .cmd_recc_stat(cmd_recc_stat),
        .cmd_col_b  (cmd_col_b_i),
        .cmd_wdata_b(cmd_wdata_b_i),
        .cmd_wdbi_b (cmd_wdbi_b_i),
        .cmd_wecc_b (cmd_wecc_b_i),
        .cmd_rdata_b(cmd_rdata_b_i),
        .cmd_rdbi_b (cmd_rdbi_b_i),
        .cmd_recc_stat_b(cmd_recc_stat_b_i)
    );

    // PC basina davranissal DRAM (sadece simulasyon)
    genvar g;
    generate for (g = 0; g < NUM_PC; g++) begin : g_dram
        dram_model u_dram (
            .clk, .rst_n,
            .cmd_valid   (cmd_valid[g]),
            .cmd_type    (cmd_type[2*g +: 2]),
            .cmd_bank    (cmd_bank[4*g +: 4]),
            .cmd_row     (cmd_row[g*ROWBITS +: ROWBITS]),
            .cmd_col     (cmd_col[g*COLBITS +: COLBITS]),
            .cmd_wdata   (cmd_wdata[32*g +: 32]),
            .cmd_wdbi    (cmd_wdbi[4*g +: 4]),
            .cmd_wecc    (cmd_wecc[7*g +: 7]),
            .cmd_allbanks(cmd_allbanks[g]),
            .cmd_rdata   (cmd_rdata[32*g +: 32]),
            .cmd_rdbi    (cmd_rdbi[4*g +: 4]),
            .cmd_recc_stat(cmd_recc_stat[2*g +: 2]),
            .cmd_col_b   (cmd_col_b_i[g*COLBITS +: COLBITS]),
            .cmd_wdata_b (cmd_wdata_b_i[32*g +: 32]),
            .cmd_wdbi_b  (cmd_wdbi_b_i[4*g +: 4]),
            .cmd_wecc_b  (cmd_wecc_b_i[7*g +: 7]),
            .cmd_rdata_b (cmd_rdata_b_i[32*g +: 32]),
            .cmd_rdbi_b  (cmd_rdbi_b_i[4*g +: 4]),
            .cmd_recc_stat_b(cmd_recc_stat_b_i[2*g +: 2]),
            .fault_valid (fault_valid[g]),
            .fault_key   (fault_key[15*g +: 15]),
            .fault_flip  (fault_flip[39*g +: 39])
        );
    end endgenerate

endmodule
