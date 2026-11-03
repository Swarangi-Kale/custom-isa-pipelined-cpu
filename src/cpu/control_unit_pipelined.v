// -----------------------------------------------------------------------
// control_unit_pipelined.v (PIPELINED VERSION - interface change from single-cycle)
//
// CHANGE FROM SINGLE-CYCLE: this module no longer takes flag_z as an
// input, and no longer outputs a final pc_redirect. In the single-cycle
// design, decode and the ALU's branch comparison happened in the same
// cycle, so control_unit could combine flag_z with the opcode right here.
// In the pipeline, decode happens in ID but the ALU comparison for
// BEQ/BNE doesn't resolve until EX, two stages later. So this module now
// only emits br_type (which kind of control-flow instruction this is,
// decodable from opcode alone) and pc_target_sel (which target to steer
// toward). The actual redirect enable - combining br_type with the live
// ALU flag_z - is computed in processor.v's EX stage, where flag_z
// actually exists.
// -----------------------------------------------------------------------
module control_unit_pipelined (
    input  wire [3:0] opcode,
    input  wire [2:0] funct,
    input wire instr8,   // NEW: instr[8], direction bit for merged STORESP/LOADSP

    output reg  [2:0] alu_funct,
    output reg        alu_src_b_sel,   // 0=rs2_rdata  1=ext_value
    output reg        rs1_addr_sel,    // 0=instr[8:6] 1=instr[11:9] (ADDI self-reference)
    output reg        rs2_addr_sel,    // 0=instr[5:3] 1=instr[11:9]
    output reg  [1:0] wb_sel,          // 00=ALU result 01=dmem rdata 10=ext_value
    output reg        dmem_addr_sel,   // 0=ALU result  1=sp_addr_out
    output reg        dmem_we,
    output reg        dmem_re,
    output reg        rd_we,
    output reg        flags_we,
    output reg        sp_we,
    output reg  [2:0] format_sel,
    output reg  [1:0] br_type,         // 00=none 01=BEQ 10=BNE 11=unconditional (JMP/RETI)
    output reg  [1:0] pc_target_sel,   // 00=branch target 01=jump target 10=LR
    output reg        shadow_restore,
    output reg        gie_set,
    output reg        lr_we,           
    output wire       shadow_save,      // tied to 0 internally - reserved, unused
    output reg spec_sel,     // NEW: which special reg for wb_sel=2'b11 reads. 0=LR, 1=SP
    output reg sp_direct_we  // NEW: write-enable for a direct (non-ADDSP) SP write
);
    assign shadow_save = 1'b0;

    localparam OP_RTYPE   = 4'b0000;
    localparam OP_LW      = 4'b0001;
    localparam OP_SW      = 4'b0010;
    localparam OP_LDI     = 4'b0011;
    localparam OP_BNE     = 4'b0100;
    localparam OP_BEQ     = 4'b0101;
    localparam OP_JMP     = 4'b0110;
    localparam OP_RETI    = 4'b0111;
    localparam OP_ADDSP   = 4'b1000;
    localparam OP_STORESP = 4'b1001;
//    localparam OP_LOADSP  = 4'b1010;
    localparam OP_ADDI    = 4'b1011;
    localparam OP_MOVLR   = 4'b1100;

    always @(*) begin
        // Defaults: everything inert (also covers reserved opcodes 1011-1111)
        alu_funct      = 3'b000;
        alu_src_b_sel  = 1'b0;
        rs1_addr_sel   = 1'b0;
        rs2_addr_sel   = 1'b0;
        wb_sel         = 2'b00;
        dmem_addr_sel  = 1'b0;
        dmem_we        = 1'b0;
        dmem_re        = 1'b0;
        rd_we          = 1'b0;
        flags_we       = 1'b0;
        sp_we          = 1'b0;
        format_sel     = 3'b000;
        br_type        = 2'b00;
        pc_target_sel  = 2'b00;
        shadow_restore = 1'b0;
        gie_set        = 1'b0;
        lr_we          = 1'b0;
        spec_sel       = 1'b0;      
        sp_direct_we   = 1'b0;

        case (opcode)
            OP_RTYPE: begin
                alu_funct     = funct;
                alu_src_b_sel = 1'b0;
                rs2_addr_sel  = 1'b0;
                wb_sel        = 2'b00;
                if (funct == 3'b000) begin
                    // NOP (all-zero word): rd_we and flags_we suppressed
                    rd_we    = 1'b0;
                    flags_we = 1'b0;
                end else begin
                    rd_we    = 1'b1;
                    flags_we = (funct == 3'b101) || (funct == 3'b001); // ADD, SUB set flags
                end
            end

            OP_LW: begin
                alu_funct     = 3'b101;
                alu_src_b_sel = 1'b1;
                format_sel    = 3'b000;
                dmem_addr_sel = 1'b0;
                dmem_re       = 1'b1;
                wb_sel        = 2'b01;
                rd_we         = 1'b1;
            end

            OP_SW: begin
                alu_funct     = 3'b101;
                alu_src_b_sel = 1'b1;
                rs2_addr_sel  = 1'b1;
                format_sel    = 3'b000;
                dmem_addr_sel = 1'b0;
                dmem_we       = 1'b1;
            end

            OP_LDI: begin
                format_sel = 3'b010;
                wb_sel     = 2'b10;
                rd_we      = 1'b1;
            end

            OP_BNE: begin
                alu_funct     = 3'b001;
                alu_src_b_sel = 1'b0;
                rs2_addr_sel  = 1'b1;
                format_sel    = 3'b001;
                pc_target_sel = 2'b00;
                br_type       = 2'b10;  // resolved in EX: redirect if !flag_z
            end

            OP_BEQ: begin
                alu_funct     = 3'b001;
                alu_src_b_sel = 1'b0;
                rs2_addr_sel  = 1'b1;
                format_sel    = 3'b001;
                pc_target_sel = 2'b00;
                br_type       = 2'b01;  // resolved in EX: redirect if flag_z
            end

            OP_JMP: begin
                format_sel    = 3'b100;
                pc_target_sel = 2'b01;
                br_type       = 2'b11;  // unconditional, resolved in EX
            end

            OP_RETI: begin
                format_sel     = 3'b100;
                pc_target_sel  = 2'b10;
                br_type        = 2'b11; // unconditional, resolved in EX
                shadow_restore = 1'b1;
                gie_set        = 1'b1;
            end

            OP_ADDSP: begin
                format_sel = 3'b101;
                sp_we      = 1'b1;
            end

            OP_STORESP: begin
                rs2_addr_sel  = 1'b1;
                format_sel    = 3'b011;
                dmem_addr_sel = 1'b1;
                if (instr8 == 1'b0) begin
                    dmem_we = 1'b1;             // store
                end else begin
                    dmem_re = 1'b1;             // load
                    wb_sel  = 2'b01;
                    rd_we   = 1'b1;
                end
            end 

//            OP_LOADSP: begin
//                format_sel    = 3'b011;
//                dmem_addr_sel = 1'b1;
//                dmem_re       = 1'b1;
//                wb_sel        = 2'b01;
//                rd_we         = 1'b1;
//            end
            
            OP_ADDI: begin
                alu_funct     = 3'b101;   // ADD - same ALU op, no ALU change needed
                alu_src_b_sel = 1'b1;     // ext_value (the immediate)
                rs1_addr_sel  = 1'b1;     // read rd's OWN position as the source
                format_sel    = 3'b010;   // FMT_LDI - identical field layout
                wb_sel        = 2'b00;    // ALU result, NOT ext_value (unlike LDI)
                rd_we         = 1'b1;
                flags_we      = 1'b1;     // matches plain ADD's flag-setting behavior
            end
            
            OP_MOVLR: begin
                if (funct[0] == 1'b0) begin
                    // read: Rd = LR or SP, selected by funct[1]
                    wb_sel   = 2'b11;
                    rd_we    = 1'b1;
                    spec_sel = funct[1];
                end else begin
                    // write: LR or SP = Rd
                    rs1_addr_sel = 1'b1;
                    if (funct[1] == 1'b0) lr_we        = 1'b1;
                    else                  sp_direct_we = 1'b1;
                end
            end           

            default: begin
                rs1_addr_sel   = 1'b0;
                lr_we = 1'b0;
                // reserved opcodes 1011-1111: stays fully inert
            end
        endcase
    end
endmodule