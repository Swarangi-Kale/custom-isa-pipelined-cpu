// -----------------------------------------------------------------------
// processor_pipelined_tb.v (PIPELINED)
//
// Same architectural goal as the single-cycle testbench, but the program
// is padded to survive having NO forwarding and NO branch/jump flush:
//   - 3 filler instructions between an instruction that writes a GPR and
//     the next one that reads it (WB is 3 stages after ID -> needs the
//     reader fetched >= 4 cycles after the writer).
//   - SP and data-memory producer/consumer pairs need 0 cycles of gap
//     (SP updates and dmem access both happen in the EX/MEM-adjacent
//     "produce" stage class, one stage ahead of GPR writes - see chat).
//   - 2 filler instructions after every taken branch/JMP (branches
//     resolve in EX, 2 cycles after fetch; the 2 already-fetched
//     instructions behind them are not flushed). These happen to be
//     NOPs already, so they're harmless regardless.
//
// This was verified against a cycle-accurate Python model of this exact
// control/datapath timing before being written into this testbench.
//
// Program (word-addressed):
//   0:  LDI  R1, 5
//   1:  LDI  R2, 3
//   2:  NOP                  ; spacer (R1/R2 need to reach WB before use)
//   3:  NOP                  ; spacer
//   4:  NOP                  ; spacer
//   5:  ADD  R3, R1, R2      ; R3 = 8, flags Z=0 C=0
//   6:  SUB  R4, R1, R2      ; R4 = 2, flags Z=0 C=1 (no borrow)
//   7:  BEQ  R1, R2, +2      ; not taken (5 != 3)
//   8:  BNE  R1, R2, +3      ; taken -> PC = 11 (resolves in EX @ fetch+2)
//   9:  NOP                  ; wrong-path fetch (harmless - already a NOP)
//   10: NOP                  ; wrong-path fetch (harmless - already a NOP)
//   11: JMP  14              ; unconditional -> PC = 14
//   12: NOP                  ; wrong-path fetch (harmless)
//   13: NOP                  ; wrong-path fetch (harmless)
//   14: ADDSP 5              ; SP = 5
//   15: LDI  R5, 42
//   16: NOP                  ; spacer
//   17: NOP                  ; spacer
//   18: NOP                  ; spacer
//   19: STORESP R5, 0        ; mem[SP+0] = mem[5] = 42
//   20: LOADSP  R6, 0        ; R6 = mem[SP+0] = mem[5] = 42
// -----------------------------------------------------------------------
`timescale 1ns/1ps

module processor_pipelined_tb;

    reg clk;
    reg rst_n;
    integer errors = 0;

    processor_pipelined uut (
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

    integer i;

    initial begin
        clk   = 0;
        rst_n = 0;

        uut.u_imem.mem[0]  = 16'h3205; // LDI  R1, 5
        uut.u_imem.mem[1]  = 16'h3403; // LDI  R2, 3
        uut.u_imem.mem[2]  = 16'h0000; // NOP
        uut.u_imem.mem[3]  = 16'h0000; // NOP
        uut.u_imem.mem[4]  = 16'h0000; // NOP
        uut.u_imem.mem[5]  = 16'h0655; // ADD  R3, R1, R2
        uut.u_imem.mem[6]  = 16'h0851; // SUB  R4, R1, R2
        uut.u_imem.mem[7]  = 16'h5442; // BEQ  R1, R2, +2   (not taken)
        uut.u_imem.mem[8]  = 16'h4443; // BNE  R1, R2, +3   (taken -> 11)
        uut.u_imem.mem[9]  = 16'h0000; // NOP  (wrong-path, harmless)
        uut.u_imem.mem[10] = 16'h0000; // NOP  (wrong-path, harmless)
        uut.u_imem.mem[11] = 16'h600E; // JMP  14
        uut.u_imem.mem[12] = 16'h0000; // NOP  (wrong-path, harmless)
        uut.u_imem.mem[13] = 16'h0000; // NOP  (wrong-path, harmless)
        uut.u_imem.mem[14] = 16'h8005; // ADDSP 5
        uut.u_imem.mem[15] = 16'h3A2A; // LDI  R5, 42
        uut.u_imem.mem[16] = 16'h0000; // NOP
        uut.u_imem.mem[17] = 16'h0000; // NOP
        uut.u_imem.mem[18] = 16'h0000; // NOP
        uut.u_imem.mem[19] = 16'h9A00; // STORESP R5, 0
        uut.u_imem.mem[20] = 16'hAC00; // LOADSP  R6, 0
        for (i = 21; i < 40; i = i + 1) uut.u_imem.mem[i] = 16'h0000;

        #12 rst_n = 1;

        // Run enough cycles for the last instruction (LOADSP, fetched at
        // cycle 20) to reach WB (fetch_cycle + 4 = cycle 24), plus margin.
        repeat (28) @(posedge clk);
        #1;

        check8("R1 (LDI R1,5)",              uut.u_rf.regs[1], 8'd5);
        check8("R2 (LDI R2,3)",              uut.u_rf.regs[2], 8'd3);
        check8("R3 (ADD R3,R1,R2)",          uut.u_rf.regs[3], 8'd8);
        check8("R4 (SUB R4,R1,R2)",          uut.u_rf.regs[4], 8'd2);
        check8("R5 (LDI R5,42)",             uut.u_rf.regs[5], 8'd42);
        check8("R6 (LOADSP R6,0)",           uut.u_rf.regs[6], 8'd42);
        check8("PC after 28 cycles (just counting on past NOPs)", uut.pc_out, 8'd28);
        check8("SP (ADDSP 5)",               uut.u_sp.sp_reg, 8'd5);
        check8("dmem[5] (STORESP R5,0)",     uut.u_dmem.mem[5], 8'd42);

        if (errors == 0) $display("\n=== ALL TESTS PASSED ===");
        else              $display("\n=== %0d TEST(S) FAILED ===", errors);

        $finish;
    end

endmodule