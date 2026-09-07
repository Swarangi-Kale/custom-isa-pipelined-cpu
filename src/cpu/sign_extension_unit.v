// sign_extension_unit.v
// -----------------------------------------------------------------------
// Opcode/width-driven mux (per Section 5) that produces an 8-bit value
// from whichever instruction field is relevant to the current format.
// NOT a single fixed-width extractor - two genuinely different
// operations happen here, selected by format_sel:
//
//   1. Real sign-extension (6-bit source, narrower than 8 bits):
//        I-type imm[6]     - instr[5:0]
//        B-type offset[6]  - instr[5:0]
//      Both sit at the identical bit position, so both share the same
//      extraction: replicate bit 5 up through bits [7:6].
//
//   2. Plain 8-bit pass-through (9-bit or 12-bit source, wider than
//      8 bits - only the low 8 bits are ever architecturally meaningful,
//      per the ADDSP/LDI discussion: no real ambiguity exists once you
//      note SP/GPR data width is 8 bits, so the "extra" bits above [7:0]
//      are simply ignored/grounded, not extended):
//        LDI-type imm[9]      - instr[8:0], bit 8 ignored
//        SP-mem offset[9]     - instr[8:0], bit 8 ignored
//        J-type addr[12]      - instr[11:0], bits [11:8] ignored
//        SP-imm imm[12] (ADDSP) - instr[11:0], bits [11:8] ignored
//      All four reduce to the exact same slice: instr[7:0].
//
// format_sel is driven by the Control Unit (stubbed for now, per Section
// 5's build order - this unit does not decode the opcode itself, it just
// acts on whatever format the Control Unit says is active).
//
// R-type is deliberately absent from format_sel: it has no immediate/
// offset field, so this unit is simply unused on R-type instructions.
// -----------------------------------------------------------------------

module sign_extension_unit (
    input  wire [15:0] instr,       // full 16-bit instruction
    input  wire [2:0]  format_sel,  // which format is currently active
    output reg  [7:0]  ext_value
);

    localparam FMT_ITYPE = 3'b000;  // I-type imm[6]      -> sign-extend
    localparam FMT_BTYPE = 3'b001;  // B-type offset[6]    -> sign-extend
    localparam FMT_LDI   = 3'b010;  // LDI imm[9]          -> low 8 bits
    localparam FMT_SPMEM = 3'b011;  // SP-mem offset[9]    -> low 8 bits
    localparam FMT_JTYPE = 3'b100;  // J-type addr[12]     -> low 8 bits
    localparam FMT_SPIMM = 3'b101;  // SP-imm imm[12] (ADDSP) -> low 8 bits

    always @(*) begin
        case (format_sel)
            FMT_ITYPE, FMT_BTYPE:
                ext_value = {{2{instr[5]}}, instr[5:0]};

            FMT_LDI, FMT_SPMEM, FMT_JTYPE, FMT_SPIMM:
                ext_value = instr[7:0];

            default:
                ext_value = 8'b0;
        endcase
    end

endmodule