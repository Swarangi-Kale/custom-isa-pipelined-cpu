// control_unit_tb.v
// -----------------------------------------------------------------------
// Self-checking testbench for control_unit.v. One test case per
// mnemonic (R-type broken out per funct, including the NOP encoding),
// both BEQ/BNE taken and not-taken outcomes, and a reserved opcode to
// confirm everything stays inert. Every one of the 17 output signals is
// checked on every case.
//
// Run with Icarus:
//   iverilog -o cu_sim control_unit.v control_unit_tb.v
//   vvp cu_sim
// -----------------------------------------------------------------------

`timescale 1ns/1ps

module control_unit_tb;

    reg  [3:0] opcode;
    reg  [2:0] funct;
    reg        flag_z;

    wire [2:0] alu_funct;
    wire       alu_src_b_sel;
    wire       rs2_addr_sel;
    wire [1:0] wb_sel;
    wire       dmem_addr_sel;
    wire       dmem_we;
    wire       dmem_re;
    wire       rd_we;
    wire       flags_we;
    wire       sp_we;
    wire [2:0] format_sel;
    wire       pc_redirect;
    wire [1:0] pc_target_sel;
    wire       shadow_restore;
    wire       gie_set;
    wire       lr_we;
    wire       shadow_save;

    integer errors = 0;
    integer tests  = 0;

    control_unit dut (
        .opcode         (opcode),
        .funct          (funct),
        .flag_z         (flag_z),
        .alu_funct      (alu_funct),
        .alu_src_b_sel  (alu_src_b_sel),
        .rs2_addr_sel   (rs2_addr_sel),
        .wb_sel         (wb_sel),
        .dmem_addr_sel  (dmem_addr_sel),
        .dmem_we        (dmem_we),
        .dmem_re        (dmem_re),
        .rd_we          (rd_we),
        .flags_we       (flags_we),
        .sp_we          (sp_we),
        .format_sel     (format_sel),
        .pc_redirect    (pc_redirect),
        .pc_target_sel  (pc_target_sel),
        .shadow_restore (shadow_restore),
        .gie_set        (gie_set),
        .lr_we          (lr_we),
        .shadow_save    (shadow_save)
    );

    task check;
        input [255:0] name;
        input [2:0] e_alu_funct;
        input       e_alu_src_b_sel;
        input       e_rs2_addr_sel;
        input [1:0] e_wb_sel;
        input       e_dmem_addr_sel;
        input       e_dmem_we;
        input       e_dmem_re;
        input       e_rd_we;
        input       e_flags_we;
        input       e_sp_we;
        input [2:0] e_format_sel;
        input       e_pc_redirect;
        input [1:0] e_pc_target_sel;
        input       e_shadow_restore;
        input       e_gie_set;
        begin
            tests = tests + 1;
            #1;
            if (alu_funct !== e_alu_funct || alu_src_b_sel !== e_alu_src_b_sel ||
                rs2_addr_sel !== e_rs2_addr_sel || wb_sel !== e_wb_sel ||
                dmem_addr_sel !== e_dmem_addr_sel || dmem_we !== e_dmem_we ||
                dmem_re !== e_dmem_re || rd_we !== e_rd_we || flags_we !== e_flags_we ||
                sp_we !== e_sp_we || format_sel !== e_format_sel ||
                pc_redirect !== e_pc_redirect || pc_target_sel !== e_pc_target_sel ||
                shadow_restore !== e_shadow_restore || gie_set !== e_gie_set ||
                lr_we !== 1'b0 || shadow_save !== 1'b0) begin
                errors = errors + 1;
                $display("FAIL [%0s]", name);
                $display("   got: alu_funct=%b alu_src_b_sel=%b rs2_addr_sel=%b wb_sel=%b dmem_addr_sel=%b dmem_we=%b dmem_re=%b rd_we=%b flags_we=%b sp_we=%b format_sel=%b pc_redirect=%b pc_target_sel=%b shadow_restore=%b gie_set=%b lr_we=%b shadow_save=%b",
                    alu_funct, alu_src_b_sel, rs2_addr_sel, wb_sel, dmem_addr_sel, dmem_we, dmem_re, rd_we, flags_we, sp_we, format_sel, pc_redirect, pc_target_sel, shadow_restore, gie_set, lr_we, shadow_save);
                $display("   exp: alu_funct=%b alu_src_b_sel=%b rs2_addr_sel=%b wb_sel=%b dmem_addr_sel=%b dmem_we=%b dmem_re=%b rd_we=%b flags_we=%b sp_we=%b format_sel=%b pc_redirect=%b pc_target_sel=%b shadow_restore=%b gie_set=%b lr_we=0 shadow_save=0",
                    e_alu_funct, e_alu_src_b_sel, e_rs2_addr_sel, e_wb_sel, e_dmem_addr_sel, e_dmem_we, e_dmem_re, e_rd_we, e_flags_we, e_sp_we, e_format_sel, e_pc_redirect, e_pc_target_sel, e_shadow_restore, e_gie_set);
            end else begin
                $display("PASS [%0s]", name);
            end
        end
    endtask

    initial begin
        flag_z = 1'b0;

        // ================= R-type (opcode 0000), by funct =================
        // ADD: funct=101 (moved here to free 000 for NOP)
        opcode=4'b0000; funct=3'b101;
        check("ADD (funct 101)", 3'b101,0,0,2'b00,0,0,0, 1,1,0, 3'b000, 0,2'b00, 0,0);

        // SUB: funct=001
        opcode=4'b0000; funct=3'b001;
        check("SUB (funct 001)", 3'b001,0,0,2'b00,0,0,0, 1,1,0, 3'b000, 0,2'b00, 0,0);

        // SHL: funct=010
        opcode=4'b0000; funct=3'b010;
        check("SHL (funct 010)", 3'b010,0,0,2'b00,0,0,0, 1,1,0, 3'b000, 0,2'b00, 0,0);

        // SHR: funct=011
        opcode=4'b0000; funct=3'b011;
        check("SHR (funct 011)", 3'b011,0,0,2'b00,0,0,0, 1,1,0, 3'b000, 0,2'b00, 0,0);

        // SHRA: funct=100
        opcode=4'b0000; funct=3'b100;
        check("SHRA (funct 100)", 3'b100,0,0,2'b00,0,0,0, 1,1,0, 3'b000, 0,2'b00, 0,0);

        // NOP: funct=000 -> rd_we and flags_we must both be suppressed
        opcode=4'b0000; funct=3'b000;
        check("NOP (funct 000): rd_we=0, flags_we=0", 3'b000,0,0,2'b00,0,0,0, 0,0,0, 3'b000, 0,2'b00, 0,0);

        // ================= LW =================
        opcode=4'b0001; funct=3'bxxx;
        check("LW", 3'b101,1,0,2'b01,0,0,1, 1,0,0, 3'b000, 0,2'b00, 0,0);

        // ================= SW =================
        opcode=4'b0010; funct=3'bxxx;
        check("SW", 3'b101,1,1,2'b00,0,1,0, 0,0,0, 3'b000, 0,2'b00, 0,0);

        // ================= LDI =================
        opcode=4'b0011; funct=3'bxxx;
        check("LDI", 3'b000,0,0,2'b10,0,0,0, 1,0,0, 3'b010, 0,2'b00, 0,0);

        // ================= BNE =================
        opcode=4'b0100; funct=3'bxxx;
        flag_z = 1'b0; // rs1 != rs2 -> BNE taken
        check("BNE not-equal (taken)", 3'b001,0,1,2'b00,0,0,0, 0,0,0, 3'b001, 1,2'b00, 0,0);

        flag_z = 1'b1; // rs1 == rs2 -> BNE not taken
        check("BNE equal (not taken)", 3'b001,0,1,2'b00,0,0,0, 0,0,0, 3'b001, 0,2'b00, 0,0);

        // ================= BEQ =================
        opcode=4'b0101; funct=3'bxxx;
        flag_z = 1'b1; // rs1 == rs2 -> BEQ taken
        check("BEQ equal (taken)", 3'b001,0,1,2'b00,0,0,0, 0,0,0, 3'b001, 1,2'b00, 0,0);

        flag_z = 1'b0; // rs1 != rs2 -> BEQ not taken
        check("BEQ not-equal (not taken)", 3'b001,0,1,2'b00,0,0,0, 0,0,0, 3'b001, 0,2'b00, 0,0);

        // ================= JMP =================
        flag_z = 1'b0;
        opcode=4'b0110; funct=3'bxxx;
        check("JMP", 3'b000,0,0,2'b00,0,0,0, 0,0,0, 3'b100, 1,2'b01, 0,0);

        // ================= RETI =================
        opcode=4'b0111; funct=3'bxxx;
        check("RETI", 3'b000,0,0,2'b00,0,0,0, 0,0,0, 3'b000, 1,2'b10, 1,1);

        // ================= ADDSP =================
        opcode=4'b1000; funct=3'bxxx;
        check("ADDSP", 3'b000,0,0,2'b00,0,0,0, 0,0,1, 3'b101, 0,2'b00, 0,0);

        // ================= STORESP =================
        opcode=4'b1001; funct=3'bxxx;
        check("STORESP", 3'b000,0,1,2'b00,1,1,0, 0,0,0, 3'b011, 0,2'b00, 0,0);

        // ================= LOADSP =================
        opcode=4'b1010; funct=3'bxxx;
        check("LOADSP", 3'b000,0,0,2'b01,1,0,1, 1,0,0, 3'b011, 0,2'b00, 0,0);

        // ================= Reserved opcode: everything stays inert =================
        opcode=4'b1101; funct=3'b010; // arbitrary funct, must not matter
        check("reserved opcode 1101: fully inert", 3'b000,0,0,2'b00,0,0,0, 0,0,0, 3'b000, 0,2'b00, 0,0);

        opcode=4'b1111; funct=3'b111;
        check("reserved opcode 1111: fully inert", 3'b000,0,0,2'b00,0,0,0, 0,0,0, 3'b000, 0,2'b00, 0,0);

        // ---- Summary ----
        if (errors == 0)
            $display("\nALL %0d TESTS PASSED", tests);
        else
            $display("\n%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule