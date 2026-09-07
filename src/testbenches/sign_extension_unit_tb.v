// sign_extension_unit_tb.v
// -----------------------------------------------------------------------
// Self-checking testbench for sign_extension_unit.v. Covers real sign-
// extension for I-type/B-type (positive and negative 6-bit values), and
// plain low-8-bit pass-through for LDI/SP-mem/J-type/SP-imm - including
// deliberately nonzero "garbage" in the upper bits to confirm they're
// correctly ignored/grounded, not accidentally included.
//
// Run with Icarus:
//   iverilog -o seu_sim sign_extension_unit.v sign_extension_unit_tb.v
//   vvp seu_sim
// -----------------------------------------------------------------------

`timescale 1ns/1ps

module sign_extension_unit_tb;

    localparam FMT_ITYPE = 3'b000;
    localparam FMT_BTYPE = 3'b001;
    localparam FMT_LDI   = 3'b010;
    localparam FMT_SPMEM = 3'b011;
    localparam FMT_JTYPE = 3'b100;
    localparam FMT_SPIMM = 3'b101;

    reg  [15:0] instr;
    reg  [2:0]  format_sel;
    wire [7:0]  ext_value;

    integer errors = 0;
    integer tests  = 0;

    sign_extension_unit dut (
        .instr      (instr),
        .format_sel (format_sel),
        .ext_value  (ext_value)
    );

    task check;
        input [127:0] name;
        input [7:0]   exp_value;
        begin
            tests = tests + 1;
            #1;
            if (ext_value !== exp_value) begin
                errors = errors + 1;
                $display("FAIL [%0s]: instr=%b format_sel=%0d -> got %0d (%b), expected %0d (%b)",
                    name, instr, format_sel, ext_value, ext_value, exp_value, exp_value);
            end else begin
                $display("PASS [%0s]: ext_value=%0d (%b)", name, ext_value, ext_value);
            end
        end
    endtask

    initial begin
        // ---- I-type: 6-bit imm at instr[5:0], sign-extend to 8 ----
        // positive: imm = 6'b011111 (+31) -> 8'b00011111 (+31)
        instr = {10'b0, 6'b011111}; format_sel = FMT_ITYPE;
        check("I-type positive imm (+31)", 8'b00011111);

        // negative: imm = 6'b100000 (-32) -> 8'b11100000 (-32)
        instr = {10'b0, 6'b100000}; format_sel = FMT_ITYPE;
        check("I-type negative imm (-32)", 8'b11100000);

        // negative: imm = 6'b111111 (-1) -> 8'b11111111 (-1)
        instr = {10'b0, 6'b111111}; format_sel = FMT_ITYPE;
        check("I-type negative imm (-1)", 8'b11111111);

        // upper bits of instr (opcode/rd/rs1) are garbage - must be ignored
        instr = {10'b1111111111, 6'b000001}; format_sel = FMT_ITYPE;
        check("I-type ignores upper instr bits (+1 despite garbage)", 8'b00000001);

        // ---- B-type: same bit position [5:0], same sign-extension ----
        instr = {10'b0, 6'b100000}; format_sel = FMT_BTYPE;
        check("B-type negative offset (-32)", 8'b11100000);

        instr = {10'b0, 6'b001010}; format_sel = FMT_BTYPE;
        check("B-type positive offset (+10)", 8'b00001010);

        // ---- LDI: 9-bit imm at instr[8:0], only [7:0] meaningful ----
        instr = {7'b0, 9'b0_11001000}; format_sel = FMT_LDI; // bit8=0, low8=200
        check("LDI: bit8=0, low8=200 -> 200", 8'd200);

        // bit 8 set (would-be "extra" bit) must be ignored/grounded
        instr = {7'b0, 9'b1_11001000}; format_sel = FMT_LDI; // bit8=1, low8=200
        check("LDI: bit8=1 ignored -> still 200", 8'd200);

        instr = {7'b0, 9'b0_00000000}; format_sel = FMT_LDI;
        check("LDI: zero", 8'd0);

        // ---- SP-mem: 9-bit offset at instr[8:0], same treatment as LDI ----
        instr = {4'b0, 3'b010, 9'b1_00101000}; format_sel = FMT_SPMEM; // rd=garbage, bit8=1 ignored
        check("SP-mem: bit8 ignored, low8=0x28=40", 8'd40);

        // ---- J-type: 12-bit addr at instr[11:0], only [7:0] meaningful ----
        instr = {4'b0, 12'b1111_00110011}; format_sel = FMT_JTYPE; // upper nibble=garbage, low8=0x33=51
        check("J-type: upper 4 bits ignored, low8=51", 8'd51);

        instr = {4'b0, 12'b0000_11111111}; format_sel = FMT_JTYPE;
        check("J-type: low8=255", 8'd255);

        // ---- SP-imm (ADDSP): 12-bit imm at instr[11:0], same as J-type ----
        instr = {4'b0, 12'b1010_00000001}; format_sel = FMT_SPIMM; // upper nibble=garbage, low8=1
        check("SP-imm(ADDSP): upper 4 bits ignored, low8=1", 8'd1);

        instr = {4'b0, 12'b0101_11111111}; format_sel = FMT_SPIMM;
        check("SP-imm(ADDSP): low8=255 (-1 signed)", 8'd255);

        // ---- Default/unused format_sel value ----
        instr = 16'hFFFF; format_sel = 3'b111;
        check("undefined format_sel -> 0", 8'd0);

        // ---- Summary ----
        if (errors == 0)
            $display("\nALL %0d TESTS PASSED", tests);
        else
            $display("\n%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule