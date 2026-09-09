// mux4to1.v
// -----------------------------------------------------------------------
// Generic width-parameterized 4:1 mux. Used for the two 3-input muxes in
// this datapath (WB mux, PC-target mux) - both only need 3 real inputs,
// but their select signals are already 2 bits wide (wb_sel, pc_target_sel
// from the Control Unit), so a 4:1 mux with the unused 4th input tied to
// 0 is the natural fit rather than building a bespoke 3:1 primitive.
// -----------------------------------------------------------------------

module mux4to1 #(
    parameter WIDTH = 8
) (
    input  wire [1:0]       sel,
    input  wire [WIDTH-1:0] in0,
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [WIDTH-1:0] in3,
    output reg  [WIDTH-1:0] out
);

    always @(*) begin
        case (sel)
            2'b00: out = in0;
            2'b01: out = in1;
            2'b10: out = in2;
            2'b11: out = in3;
        endcase
    end

endmodule