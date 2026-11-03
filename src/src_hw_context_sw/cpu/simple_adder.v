// simple_adder.v
// -----------------------------------------------------------------------
// Dedicated branch-target adder for BEQ/BNE: target = PC + sign-extended
// offset. Kept separate from the main ALU because the main ALU is
// simultaneously busy doing the SUB-based comparison (Section 6) that
// decides whether the branch is even taken - both need to happen the
// same cycle, so they can't share one adder.
//
// No shift: PC is already word-addressed (one PC unit = one 16-bit
// instruction, confirmed by pc_register.v's PC+1 per-instruction
// increment), so the offset is already in the same units as PC - adding
// a MIPS-style shift here would double-count the granularity.
//
// Purely combinational - no clock, no state.
// -----------------------------------------------------------------------

module simple_adder (
    input  wire [7:0] pc_in,
    input  wire [7:0] offset,   // sign-extended 8-bit B-type offset (from the SEU)
    output wire [7:0] branch_target
);

    assign branch_target = pc_in + offset;

endmodule