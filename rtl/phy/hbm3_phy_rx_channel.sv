// Tek fiziksel kanalin PHY alici (RX) on-ucu: 64 DQ serit -> 512 bit.
//
// Her seride bir deserilestirici duser. `bitslip` SERIT BASINADIR: gercek bir
// baglantida seritler birbirine gore kayar (tel uzunlugu, pad gecikmesi),
// o yuzden hizalama serit basina aranmalidir. `align` ise GLOBALDIR --
// beat sinirini kurar ve tum seritler icin aynidir.
`include "hbm3_800g_defs.svh"

module hbm3_phy_rx_channel #(
    parameter int DQ_LANES  = HBM3_DQ_BITS_PER_CHANNEL,
    parameter int SER_RATIO = HBM3_PHY_DATA_BITS_PER_CHANNEL / HBM3_DQ_BITS_PER_CHANNEL
)(
    input  logic wck,
    input  logic rst_n,
    input  logic [DQ_LANES-1:0] dq_rise,
    input  logic [DQ_LANES-1:0] dq_fall,
    input  logic                align,        // beat sinirini kur (global)
    input  logic [DQ_LANES-1:0] bitslip,      // serit basina bir bit kaydir
    output logic [DQ_LANES*SER_RATIO-1:0] par_data,
    output logic                par_valid     // serit 0'in gecerli darbesi
);
    logic [DQ_LANES-1:0] lane_valid;

    genvar l;
    generate
        for (l = 0; l < DQ_LANES; l = l + 1) begin : g_lane
            hbm3_phy_deserializer #(.SER_RATIO(SER_RATIO)) u_des (
                .wck, .rst_n,
                .dq_rise (dq_rise[l]),
                .dq_fall (dq_fall[l]),
                .align,
                .bitslip (bitslip[l]),
                .pdata   (par_data[l*SER_RATIO +: SER_RATIO]),
                .pvalid  (lane_valid[l])
            );
        end
    endgenerate

    // Tum seritler ayni `align` ve ayni sayaci paylasir, yani pvalid'leri
    // ayni cevrimde yukselir. Serit 0 temsilcidir.
    assign par_valid = lane_valid[0];
endmodule
