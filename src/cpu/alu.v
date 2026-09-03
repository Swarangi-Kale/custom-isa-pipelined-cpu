// alu.v
// -----------------------------------------------------------------------
// Combinational ALU for the custom 16-bit pipelined processor.
// Implements ADD, SUB, SHL, SHR, SHRA, selected by alu_funct (matches the
// funct[2:0] field of R-type instructions in the ISA spec).
//
// Shift amount comes from alu_in_b (the rs2 register value), not an
// immediate field, per the spec. Only the low 3 bits of alu_in_b are used
// since operands are 8-bit wide (shift amounts 0-7 cover the full range).
//
// Port names are chosen to be instantiation-friendly for the datapath:
//   alu_in_a  <- rs1 read data (or forwarded value, once forwarding exists)
//   alu_in_b  <- rs2 read data / shift-amount source (or forwarded value)
//   alu_funct <- instr[2:0] funct field, from control unit / decode
// -----------------------------------------------------------------------

module alu (
    input  wire [7:0] alu_in_a,
    input  wire [7:0] alu_in_b,
    input  wire [2:0] alu_funct,
    output reg  [7:0] alu_result,
    output wire       flag_z,
    output wire       flag_c,
    output wire       flag_n
);

    localparam FUNCT_ADD  = 3'b000;
    localparam FUNCT_SUB  = 3'b001;
    localparam FUNCT_SHL  = 3'b010;
    localparam FUNCT_SHR  = 3'b011;
    localparam FUNCT_SHRA = 3'b100;

    reg carry_out;

    // Only the low 3 bits of alu_in_b matter for an 8-bit shift (0-7).
    wire [2:0] shamt = alu_in_b[2:0];

    always @(*) begin
        carry_out  = 1'b0;
        alu_result = 8'b0;
        case (alu_funct)
            FUNCT_ADD: begin
                {carry_out, alu_result} = {1'b0, alu_in_a} + {1'b0, alu_in_b};
            end

            FUNCT_SUB: begin
                // C = 1 means "no borrow" (a >= b). Backs BEQ/BNE via
                // SUB's Z flag, and gives a usable unsigned-compare carry.
                {carry_out, alu_result} = {1'b1, alu_in_a} - {1'b0, alu_in_b};
            end

            FUNCT_SHL: begin
                alu_result = alu_in_a << shamt;
                carry_out  = (shamt == 3'd0) ? 1'b0 : alu_in_a[8 - shamt];
            end

            FUNCT_SHR: begin
                alu_result = alu_in_a >> shamt;
                carry_out  = (shamt == 3'd0) ? 1'b0 : alu_in_a[shamt - 1];
            end

            FUNCT_SHRA: begin
                alu_result = $signed(alu_in_a) >>> shamt;
                carry_out  = (shamt == 3'd0) ? 1'b0 : alu_in_a[shamt - 1];
            end

            default: begin
                alu_result = 8'b0;
                carry_out  = 1'b0;
            end
        endcase
    end

    assign flag_z = (alu_result == 8'b0);
    assign flag_c = carry_out;
    assign flag_n = alu_result[7];

endmodule