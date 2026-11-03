// mux2to1.v
// -----------------------------------------------------------------------
// Generic width-parameterized 2:1 mux. Every 2-way mux in this datapath
// (ALU-B, rs2_addr, Data Memory address) is an instance of this at the
// appropriate WIDTH - 8 for data/address values, 3 for register indices.
// -----------------------------------------------------------------------

module mux2to1 #(
    parameter WIDTH = 8
) (
    input  wire             sel,
    input  wire [WIDTH-1:0] in0,
    input  wire [WIDTH-1:0] in1,
    output wire [WIDTH-1:0] out
);

    assign out = sel ? in1 : in0;

endmodule