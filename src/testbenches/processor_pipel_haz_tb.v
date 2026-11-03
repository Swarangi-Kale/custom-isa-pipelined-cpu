// -----------------------------------------------------------------------
// processor_pipel_haz_tb.v
// Integration testbench for processor_pipel_haz.v. Covers:
//   - Simultaneous EX/MEM and MEM/WB forwarding into the same instruction
//     (ADD R3,R1,R2: rs1=R1 is 2 back / MEM/WB, rs2=R2 is 1 back / EX/MEM)
//   - EX/MEM forwarding into a second consumer (SUB R4,R3,R1)
//   - Store-value forwarding (STORESP R4,0: R4 produced 1 instruction back)
//   - Load-use hazard: LOADSP immediately consumed by ADD -> must stall
//     exactly 1 cycle, verified both by the stall pulse itself and by the
//     final correct value
//   - Branch flush: a taken BEQ must squash exactly the instruction in
//     its shadow (the poison LDI R0,99), while the branch target
//     executes normally
//   - Not-taken branch: BNE must fall through with no flush and no
//     disruption to normal sequential execution
//
// Program (word-addressed, hand-assembled and verified against the
// bit-layout in processor_context.md):
//    0: LDI  R1,5
//    1: LDI  R2,3
//    2: ADD  R3,R1,R2        ; R3=8   (MEM/WB fwd R1 + EX/MEM fwd R2)
//    3: SUB  R4,R3,R1        ; R4=3   (EX/MEM fwd R3)
//    4: STORESP R4,0         ; dmem[0]=3 (EX/MEM fwd store-value R4)
//    5: LOADSP  R5,0         ; R5=3
//    6: ADD  R6,R5,R5        ; R6=6   (load-use: must stall once)
//    7-10: NOP (drain/spacer)
//   11: LDI  R1,20
//   12: LDI  R2,20
//   13: BEQ  R1,R2,+2        ; taken -> target = 13+2 = 15
//   14: LDI  R0,99           ; POISON - must be flushed, R0 stays 0
//   15: LDI  R7,55           ; branch target, executes normally
//   16: BNE  R1,R2,+3        ; R1==R2 -> NOT taken, falls through
//   17: ADD  R1,R1,R2        ; R1=40  (confirms normal execution resumes)
//
// Run with Icarus (adjust the file list to your actual module filenames):
//   iverilog -o proc_sim alu.v reg_bank.v pc_register.v sp_unit.v lr_reg.v \
//     flags_reg.v sign_extension_unit.v instr_mem.v data_memory.v \
//     control_unit_pipelined.v mux2to1.v mux4to1.v simple_adder.v gie_reg.v \
//     forwarding_unit.v hazard_detection_unit.v if_id_reg.v id_ex_reg.v \
//     ex_mem_reg.v mem_wb_reg.v processor_pipel_haz.v processor_pipel_haz_tb.v
//   vvp proc_sim
// -----------------------------------------------------------------------
`timescale 1ns/1ps

module processor_pipel_haz_tb;

    reg clk, rst_n,irq_in;
    integer errors = 0;
    integer stall_cycles_seen = 0;

    processor_pipel_haz uut (
        .clk   (clk),
        .rst_n (rst_n)
        .irq_in (irq_in)          // NEW: interrupt request, testbench-driven for now
    );

    always #5 clk = ~clk;

    task check8(input [255:0] name, input [7:0] actual, input [7:0] expected);
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s = %0d, expected %0d", name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = %0d", name, actual);
            end
        end
    endtask

    // Track every cycle the stall line is asserted, for the load-use check.
    always @(posedge clk) begin
        if (rst_n && uut.hdu_stall) stall_cycles_seen = stall_cycles_seen + 1;
    end

    initial begin
        clk   = 0;
        rst_n = 0;

        uut.u_imem.mem[0]  = 16'h3205; // LDI  R1,5
        uut.u_imem.mem[1]  = 16'h3403; // LDI  R2,3
        uut.u_imem.mem[2]  = 16'h0655; // ADD  R3,R1,R2
        uut.u_imem.mem[3]  = 16'h08C9; // SUB  R4,R3,R1
        uut.u_imem.mem[4]  = 16'h9800; // STORESP R4,0
        uut.u_imem.mem[5]  = 16'hAA00; // LOADSP  R5,0
        uut.u_imem.mem[6]  = 16'h0D6D; // ADD  R6,R5,R5
        uut.u_imem.mem[7]  = 16'h0000; // NOP
        uut.u_imem.mem[8]  = 16'h0000; // NOP
        uut.u_imem.mem[9]  = 16'h0000; // NOP
        uut.u_imem.mem[10] = 16'h0000; // NOP
        uut.u_imem.mem[11] = 16'h3214; // LDI  R1,20
        uut.u_imem.mem[12] = 16'h3414; // LDI  R2,20
        uut.u_imem.mem[13] = 16'h5442; // BEQ  R1,R2,+2
        uut.u_imem.mem[14] = 16'h3063; // LDI  R0,99 (poison)
        uut.u_imem.mem[15] = 16'h3E37; // LDI  R7,55
        uut.u_imem.mem[16] = 16'h4443; // BNE  R1,R2,+3
        uut.u_imem.mem[17] = 16'h0255; // ADD  R1,R1,R2

        #12 rst_n = 1;

        // Run long enough for the whole program (18 instrs) to fully
        // drain through 5 stages, plus the one stall cycle and margin.
        repeat (30) @(posedge clk);
        #1;

        // ---- Forwarding: simultaneous EX/MEM + MEM/WB into one instr ----
        check8("R1 (LDI)",                 uut.u_rf.regs[1], 8'd40); // overwritten later, checked below too
        check8("R3 = ADD R1,R2 (fwd both)", uut.u_rf.regs[3], 8'd8);

        // ---- EX/MEM forwarding into a second consumer ----
        check8("R4 = SUB R3,R1 (EX/MEM fwd)", uut.u_rf.regs[4], 8'd3);

        // ---- Store-value forwarding ----
        check8("dmem[0] after STORESP (fwd store value)", uut.u_dmem.mem[0], 8'd3);

        // ---- Load-use hazard: stall fired, and final value correct ----
        if (stall_cycles_seen == 1)
            $display("PASS: load-use hazard stalled exactly 1 cycle");
        else begin
            $display("FAIL: load-use hazard stalled %0d cycles, expected 1", stall_cycles_seen);
            errors = errors + 1;
        end
        check8("R5 = LOADSP", uut.u_rf.regs[5], 8'd3);
        check8("R6 = ADD R5,R5 (load-use, then fwd)", uut.u_rf.regs[6], 8'd6);

        // ---- Branch flush: poison instruction must never commit ----
        check8("R0 after taken BEQ's shadow (must stay 0 - flushed)", uut.u_rf.regs[0], 8'd0);
        check8("R7 = branch target LDI executed normally", uut.u_rf.regs[7], 8'd55);

        // ---- Not-taken branch: normal execution continues ----
        check8("R1 = ADD after not-taken BNE (normal resume)", uut.u_rf.regs[1], 8'd40);
        check8("R2 (unchanged since instr 12)", uut.u_rf.regs[2], 8'd20);

        if (errors == 0)
            $display("\n=== ALL TESTS PASSED ===");
        else
            $display("\n=== %0d TEST(S) FAILED ===", errors);

        $finish;
    end

endmodule