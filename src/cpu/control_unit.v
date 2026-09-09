// control_unit.v
// -----------------------------------------------------------------------
// Control Unit: pure combinational decode from {opcode, funct} to every
// control signal the datapath needs. Deliberately takes ONLY opcode[3:0]
// and funct[2:0] as inputs - no rd/rs1/rs2/imm bits are ever needed to
// make any of these decisions, so nothing else is read from the
// instruction here (those fields are wired directly from the
// instruction register to the datapath elsewhere, per field-consistency;
// see the mux/signal list this module implements).
//
// flag_z is the one piece of live datapath state this unit consumes -
// BEQ/BNE's taken/not-taken decision depends on the ALU's Z output from
// the SUB-based comparison (Section 6), so it must come in as an input.
//
// This module does NOT contain: the muxes it selects, the dedicated
// branch-target adder, or the GIE flip-flop. Those are separate,
// not-yet-built datapath pieces; this unit only drives their selects/
// enables.
//
// NOP handling: opcode 0000 (R-type) with funct 000 is the reserved NOP
// encoding (ADD was moved to funct 101 specifically to free this up).
// rd_we and flags_we are explicitly suppressed for this exact
// {opcode,funct} pair - landing on the "unused funct -> safe zero" ALU
// output alone is not sufient for a true no-op, since without this
// explicit suppression the all-zero encoding would still write 0 into R0
// and assert Z=1/C=0/N=0 into the architectural flags register.
// -----------------------------------------------------------------------

module control_unit (
    input  wire [3:0] opcode,
    input  wire [2:0] funct,
    input  wire       flag_z,          // live ALU Z output, for BEQ/BNE

    output reg  [2:0] alu_funct,
    output reg        alu_src_b_sel,   // 0=rs2_rdata (R-type,B-type) 1=ext_value (LW,SW)
    output reg        rs2_addr_sel,    // 0=instr[5:3] (R-type)  1=instr[11:9] (B-type,SW,STORESP)
    output reg  [1:0] wb_sel,          // 00=ALU result 01=Data Memory rdata 10=SEU ext_value
    output reg        dmem_addr_sel,   // 0=ALU result (LW,SW)  1=SP unit sp_addr_out (STORESP,LOADSP)
    output reg        dmem_we,
    output reg        dmem_re,
    output reg        rd_we,
    output reg        flags_we,
    output reg        sp_we,
    output reg  [2:0] format_sel,      // routed to sign_extension_unit.v (same encoding)
    output reg        pc_redirect,
    output reg  [1:0] pc_target_sel,   // 00=branch target  01=jump target (SEU)  10=LR (RETI)
    output reg        shadow_restore,  // RETI
    output reg        gie_set,         // RETI

    // Reserved interface for future interrupt-entry hardware - no current
    // instruction drives these; tied off here per the spec's directive to
    // define the full port interface now even though the logic behind
    // these two is deliberately not built yet.
    output wire       lr_we,
    output wire       shadow_save
);

    // Opcodes (Section 4)
    localparam OPC_RTYPE   = 4'b0000;
    localparam OPC_LW      = 4'b0001;
    localparam OPC_SW      = 4'b0010;
    localparam OPC_LDI     = 4'b0011;
    localparam OPC_BNE     = 4'b0100;
    localparam OPC_BEQ     = 4'b0101;
    localparam OPC_JMP     = 4'b0110;
    localparam OPC_RETI    = 4'b0111;
    localparam OPC_ADDSP   = 4'b1000;
    localparam OPC_STORESP = 4'b1001;
    localparam OPC_LOADSP  = 4'b1010;
    // 1011-1111 reserved -> falls into `default`, all outputs stay inert.

    // ALU funct codes - ADD moved to 101, freeing 000 for NOP (alu.v must
    // match: FUNCT_ADD = 3'b101 there too).
    localparam FUNCT_ADD = 3'b101;
    localparam FUNCT_SUB = 3'b001;
    localparam FUNCT_NOP = 3'b000;

    // format_sel encoding - must exactly match sign_extension_unit.v's
    // FMT_* localparams.
    localparam FMT_ITYPE = 3'b000;
    localparam FMT_BTYPE = 3'b001;
    localparam FMT_LDI   = 3'b010;
    localparam FMT_SPMEM = 3'b011;
    localparam FMT_JTYPE = 3'b100;
    localparam FMT_SPIMM = 3'b101;

    assign lr_we       = 1'b0;
    assign shadow_save = 1'b0;

    wire is_r_nop = (opcode == OPC_RTYPE) && (funct == FUNCT_NOP);
    wire is_r_alu = (opcode == OPC_RTYPE) && !is_r_nop;

    always @(*) begin
        // Safe defaults every cycle - avoids inferred latches and makes
        // every non-applicable signal an inert, defined value for
        // whichever instruction doesn't use it.
        alu_funct      = 3'b000;
        alu_src_b_sel  = 1'b0;
        rs2_addr_sel   = 1'b0;
        wb_sel         = 2'b00;
        dmem_addr_sel  = 1'b0;
        dmem_we        = 1'b0;
        dmem_re        = 1'b0;
        rd_we          = 1'b0;
        flags_we       = 1'b0;
        sp_we          = 1'b0;
        format_sel     = 3'b000;
        pc_redirect    = 1'b0;
        pc_target_sel  = 2'b00;
        shadow_restore = 1'b0;
        gie_set        = 1'b0;

        case (opcode)

            OPC_RTYPE: begin
                alu_funct = funct;         // ADD/SUB/SHL/SHR/SHRA, or NOP's 000 (unused if suppressed below)
                rd_we     = is_r_alu;      // suppressed for the NOP encoding
                flags_we  = is_r_alu;      // suppressed for the NOP encoding
                // alu_src_b_sel=0, rs2_addr_sel=0 (defaults) are correct for R-type
            end

            OPC_LW: begin
                alu_funct     = FUNCT_ADD; // I-type has no funct field; force ADD for address calc
                alu_src_b_sel = 1'b1;      // ext_value = sign-extended imm6
                dmem_addr_sel = 1'b0;      // ALU result (rs1 + imm)
                dmem_re       = 1'b1;
                wb_sel        = 2'b01;     // Data Memory rdata
                rd_we         = 1'b1;
                format_sel    = FMT_ITYPE;
            end

            OPC_SW: begin
                alu_funct     = FUNCT_ADD;
                alu_src_b_sel = 1'b1;
                rs2_addr_sel  = 1'b1;      // read the "Rd" position as the value being stored
                dmem_addr_sel = 1'b0;
                dmem_we       = 1'b1;
                format_sel    = FMT_ITYPE;
            end

            OPC_LDI: begin
                wb_sel     = 2'b10;        // ext_value straight to writeback
                rd_we      = 1'b1;
                format_sel = FMT_LDI;
            end

            OPC_BNE, OPC_BEQ: begin
                alu_funct     = FUNCT_SUB;   // B-type has no funct field; force SUB for comparison
                rs2_addr_sel  = 1'b1;        // second compared register sits at instr[11:9]
                format_sel    = FMT_BTYPE;
                pc_target_sel = 2'b00;       // branch target adder
                pc_redirect   = (opcode == OPC_BEQ) ? flag_z : ~flag_z;
            end

            OPC_JMP: begin
                format_sel    = FMT_JTYPE;
                pc_target_sel = 2'b01;       // jump target: SEU pass-through, no adder
                pc_redirect   = 1'b1;
            end

            OPC_RETI: begin
                pc_target_sel  = 2'b10;      // LR
                pc_redirect    = 1'b1;
                shadow_restore = 1'b1;
                gie_set        = 1'b1;
            end

            OPC_ADDSP: begin
                format_sel = FMT_SPIMM;
                sp_we      = 1'b1;
            end

            OPC_STORESP: begin
                rs2_addr_sel  = 1'b1;        // read the "Rd" position as the value being stored
                format_sel    = FMT_SPMEM;
                dmem_addr_sel = 1'b1;        // SP unit's sp_addr_out
                dmem_we       = 1'b1;
            end

            OPC_LOADSP: begin
                format_sel    = FMT_SPMEM;
                dmem_addr_sel = 1'b1;
                dmem_re       = 1'b1;
                wb_sel        = 2'b01;       // Data Memory rdata
                rd_we         = 1'b1;
            end

            default: begin
                // Reserved opcodes 1011-1111: all outputs remain at the
                // safe defaults set above.
            end

        endcase
    end

endmodule