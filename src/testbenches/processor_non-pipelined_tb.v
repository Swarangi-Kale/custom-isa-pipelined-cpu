// ----------------------------------------------------------------------
// processor_tb.v
// Structural/integration test for the single-cycle processor top level.
// Hand-assembles a small program covering: LDI, ADD, SUB (flags), a
// not-taken branch, a taken branch, JMP, ADDSP, and a STORESP/LOADSP
// round trip - then checks architectural state after each instruction.
//
// Program (word-addressed, PC increments by 1 per instruction):
//   0:  LDI  R1, 5
//   1:  LDI  R2, 3
//   2:  ADD  R3, R1, R2        ; R3 = 8,  Z=0 C=0
//   3:  SUB  R4, R1, R2        ; R4 = 2,  Z=0 C=1 (no borrow)
//   4:  BEQ  R1, R2, +2        ; not taken (5 != 3)
//   5:  BNE  R1, R2, +3        ; taken -> PC = 8
//   6:  NOP                    ; skipped
//   7:  NOP                    ; skipped
//   8:  JMP  12                ; -> PC = 12
//   9:  NOP                    ; skipped
//   10: NOP                    ; skipped
//   11: NOP                    ; skipped
//   12: ADDSP 5                ; SP = 5
//   13: LDI  R5, 42
//   14: STORESP R5, 0          ; mem[SP+0] = mem[5] = 42
//   15: LOADSP  R6, 0          ; R6 = mem[SP+0] = mem[5] = 42
// -----------------------------------------------------------------------
`timescale 1ns/1ps

module processor_tb;

    reg clk;
    reg rst_n;
    integer errors = 0;

    processor uut (
        .clk   (clk),
        .rst_n (rst_n)
    );

    always #5 clk = ~clk;

    task check8(input [255:0] name, input [7:0] actual, input [7:0] expected);
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s = %0d (0x%02h), expected %0d (0x%02h) at t=%0t",
                          name, actual, actual, expected, expected, $time);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = %0d (0x%02h)", name, actual, actual);
            end
        end
    endtask

    initial begin
        clk   = 0;
        rst_n = 0;

        // Hand-assembled program, preloaded directly into instruction_memory's
        // backing array (same approach as instruction_memory_tb.v).
        uut.u_imem.mem[0]  = 16'h3205; // LDI  R1, 5
        uut.u_imem.mem[1]  = 16'h3403; // LDI  R2, 3
        uut.u_imem.mem[2]  = 16'h0655; // ADD  R3, R1, R2
        uut.u_imem.mem[3]  = 16'h0851; // SUB  R4, R1, R2
        uut.u_imem.mem[4]  = 16'h5442; // BEQ  R1, R2, +2   (not taken)
        uut.u_imem.mem[5]  = 16'h4443; // BNE  R1, R2, +3   (taken -> 8)
        uut.u_imem.mem[6]  = 16'h0000; // NOP  (skipped)
        uut.u_imem.mem[7]  = 16'h0000; // NOP  (skipped)
        uut.u_imem.mem[8]  = 16'h600C; // JMP  12
        uut.u_imem.mem[9]  = 16'h0000; // NOP  (skipped)
        uut.u_imem.mem[10] = 16'h0000; // NOP  (skipped)
        uut.u_imem.mem[11] = 16'h0000; // NOP  (skipped)
        uut.u_imem.mem[12] = 16'h8005; // ADDSP 5
        uut.u_imem.mem[13] = 16'h3A2A; // LDI  R5, 42
        uut.u_imem.mem[14] = 16'h9A00; // STORESP R5, 0
        uut.u_imem.mem[15] = 16'hAC00; // LOADSP  R6, 0

        #12 rst_n = 1;

        // Instr 0: LDI R1,5
        @(posedge clk); #1;
        check8("R1 after LDI R1,5", uut.u_rf.regs[1], 8'd5);

        // Instr 1: LDI R2,3
        @(posedge clk); #1;
        check8("R2 after LDI R2,3", uut.u_rf.regs[2], 8'd3);

        // Instr 2: ADD R3,R1,R2
        @(posedge clk); #1;
        check8("R3 after ADD R3,R1,R2", uut.u_rf.regs[3], 8'd8);
        check8("flag_z after ADD",     {7'b0, uut.flag_z}, 8'd0);
        check8("flag_c after ADD",     {7'b0, uut.flag_c}, 8'd0);

        // Instr 3: SUB R4,R1,R2
        @(posedge clk); #1;
        check8("R4 after SUB R4,R1,R2",       uut.u_rf.regs[4], 8'd2);
        check8("flag_c after SUB (no borrow)", {7'b0, uut.flag_c}, 8'd1);

        // Instr 4: BEQ not taken
        @(posedge clk); #1;
        check8("PC after not-taken BEQ", uut.pc_out, 8'd5);

        // Instr 5: BNE taken
        @(posedge clk); #1;
        check8("PC after taken BNE", uut.pc_out, 8'd8);

        // Instr 8: JMP 12
        @(posedge clk); #1;
        check8("PC after JMP", uut.pc_out, 8'd12);

        // Instr 12: ADDSP 5
        @(posedge clk); #1;
        check8("SP after ADDSP 5", uut.u_sp.sp_out, 8'd5);

        // Instr 13: LDI R5,42
        @(posedge clk); #1;
        check8("R5 after LDI R5,42", uut.u_rf.regs[5], 8'd42);

        // Instr 14: STORESP R5,0
        @(posedge clk); #1;
        check8("dmem[5] after STORESP R5,0", uut.u_dmem.mem[5], 8'd42);

        // Instr 15: LOADSP R6,0
        @(posedge clk); #1;
        check8("R6 after LOADSP R6,0", uut.u_rf.regs[6], 8'd42);

        if (errors == 0) $display("\n=== ALL TESTS PASSED ===");
        else              $display("\n=== %0d TEST(S) FAILED ===", errors);

        $finish;
    end

endmodule