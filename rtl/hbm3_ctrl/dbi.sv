// DBIac (Data Bus Inversion) - byte basina: sifir sayisi >4 ise invert
// Giris cikislari ayni genislikte; her byte icin 1 bit DBI.
`timescale 1ns/1ps

module dbi_enc #(
    parameter int BYTES = 4
)(
    input  logic [BYTES*8-1:0] din,
    output logic [BYTES*8-1:0] dout,
    output logic [BYTES-1:0]   dbi        // 1 = byte tersine cevrildi
);
    for (genvar b = 0; b < BYTES; b++) begin : g_byte
        logic [7:0] raw;
        logic [3:0] zeros;   // 0..8 sigmasi icin EN AZ 4 bit sart (3 bit 7'de sarar!)
        assign raw = din[b*8 +: 8];
        // sifir sayici (popcount of ~raw)
        always_comb begin
            zeros = 4'd0;
            for (int i = 0; i < 8; i++)
                if (!raw[i]) zeros = zeros + 4'd1;
        end
        assign dbi[b]  = (zeros > 4'd4);
        assign dout[b*8 +: 8] = dbi[b] ? ~raw : raw;
    end
endmodule

module dbi_dec #(
    parameter int BYTES = 4
)(
    input  logic [BYTES*8-1:0] din,
    input  logic [BYTES-1:0]   dbi,
    output logic [BYTES*8-1:0] dout
);
    for (genvar b = 0; b < BYTES; b++) begin : g_byte
        assign dout[b*8 +: 8] = dbi[b] ? ~din[b*8 +: 8] : din[b*8 +: 8];
    end
endmodule
