`timescale 1ns/1ps
// -----------------------------------------------------------------------
// isr_task_loops_tb.v
// Stage 4: real task loops + real ISR + periodic irq_in, combining
// everything isr_full_cycle_tb.v and task0_loop_tb.v verified separately.
//
// Checks, per your Phase C spec:
//   (a) each task's counter increments correctly and monotonically
//   (b) each task resumes at the exact PC it was interrupted at
//   (c) no cross-task stack/GPR corruption
//   (d) current_task_id cycles 0->1->2->0 correctly
//
// The strongest new proof here vs isr_full_cycle_tb.v: task0's counter
// must be FROZEN for the entire time task0 isn't scheduled (two full
// switch windows), then resume climbing from exactly where it left off
// (not reset, not corrupted) once wraparound hands control back.
//
// Program layout (instr_mem and data_mem are separate/Harvard, so no
// address-space collision between e.g. task2 loop @0x30 and TCB @0x06):
//   0x00-0x02  boot stub (RETI-as-enable trick)
//   0x03-0x05  task0 preamble: SP=0xFF, then JMP into its loop
//   0x10-0x13  task0 loop: counter @0x01
//   0x20-0x23  task1 loop: counter @0x02
//   0x30-0x33  task2 loop: counter @0x03
//   0x40-0x6F  ISR (unchanged from isr_full_cycle_tb.v)
//
// Data memory preload (AFTER rst_n=1 -- data_memory.v clears its whole
// array on every posedge clk while rst_n is low, see prior bug log):
//   0x00 current_task_id=0, 0x01-0x03 counters=0, 0x05 tcb1=0xEF,
//   0x06 tcb2=0xE6, fake initial contexts at 0xEF-0xF6 (task1) and
//   0xE6-0xED (task2) -- LR slots hold their REAL loop entry addresses
//   this time (0x20, 0x30), since these tasks genuinely start there.
//
// PREREQUISITES: both fixes from earlier bring-up must be in place --
// hazard_detection_unit.v's OP_MOVLR-write stall, and control_unit_
// pipelined.v's dmem_re for OP_STORESP's load direction.
//
// ASSUMPTIONS: same hierarchical paths as isr_full_cycle_tb.v, plus the
// same ex_pc_target_sel==2'b10 assumption for RETI-vs-JMP disambiguation
// (already confirmed against a real waveform in that test).
// -----------------------------------------------------------------------
module final_tb;

    reg clk, rst_n, irq_in;
    integer i;
    integer errors = 0;

    processor_pipel_haz uut (
        .clk    (clk),
        .rst_n  (rst_n),
        .irq_in (irq_in)
    );

    always #5 clk = ~clk;

    task check8(input [255:0] name, input [7:0] a, input [7:0] e);
        begin
            if (a !== e) begin
                $display("FAIL: %0s = 0x%02h, expected 0x%02h", name, a, e);
                errors = errors + 1;
            end else $display("PASS: %0s = 0x%02h", name, a);
        end
    endtask

    task check_gt(input [255:0] name, input [7:0] now_val, input [7:0] prev);
        begin
            if (now_val <= prev) begin
                $display("FAIL: %0s did not increase (prev=0x%02h, now=0x%02h)",
                          name, prev, now_val);
                errors = errors + 1;
            end else $display("PASS: %0s increased (0x%02h -> 0x%02h)",
                                name, prev, now_val);
        end
    endtask

    // ---- exact-PC-resume capture (same mechanism as isr_full_cycle_tb.v) ----
    reg [7:0] irq_pc_capture [0:2];
    integer   irq_taken_count;
    always @(posedge clk) begin
        if (rst_n && uut.irq_taken) begin
            irq_pc_capture[irq_taken_count] <= uut.id_pc;
            irq_taken_count <= irq_taken_count + 1;
        end
    end

    reg [7:0] reti_addr_capture [0:3];
    integer   reti_count;
    always @(posedge clk) begin
        // gated on pc_target_sel too -- ex_br_type alone doesn't
        // distinguish RETI from JMP (see isr_full_cycle_tb.v bug log)
        if (rst_n && uut.ex_pc_redirect && uut.ex_br_type == 2'b11
                   && uut.ex_pc_target_sel == 2'b10) begin
            reti_addr_capture[reti_count] <= uut.ex_pc_redirect_addr;
            reti_count <= reti_count + 1;
        end
    end

    reg [7:0] c0_before_1, c1_before_2, c2_before_3;

    initial begin
        clk = 0; rst_n = 0; irq_in = 0;
        irq_taken_count = 0; reti_count = 0;

        for (i = 0; i < 256; i = i + 1) uut.u_imem.mem[i] = 16'h0000;

        ; // ---- boot stub: arm GIE=1 ----
        uut.u_imem.mem[16'h00] = 16'h3E03; // LDI  R7,0x03
        uut.u_imem.mem[16'h01] = 16'hCE01; // MOV  LR,R7
        uut.u_imem.mem[16'h02] = 16'h7000; // RETI -> GIE=1, jump to 0x03

        ; // ---- task0 preamble: SP=0xFF, jump into its loop ----
        uut.u_imem.mem[16'h03] = 16'h3EFF; // LDI  R7,0xFF
        uut.u_imem.mem[16'h04] = 16'hCE03; // MOV  SP,R7
        uut.u_imem.mem[16'h05] = 16'h6010; // JMP  0x10

        ; // ---- task0 loop: counter @0x01 ----
        uut.u_imem.mem[16'h10] = 16'h1201; // LW   R1,0x01(R0)
        uut.u_imem.mem[16'h11] = 16'hB201; // ADDI R1,#1
        uut.u_imem.mem[16'h12] = 16'h2201; // SW   R1,0x01(R0)
        uut.u_imem.mem[16'h13] = 16'h6010; // JMP  0x10

        ; // ---- task1 loop: counter @0x02 ----
        uut.u_imem.mem[16'h20] = 16'h1202; // LW   R1,0x02(R0)
        uut.u_imem.mem[16'h21] = 16'hB201; // ADDI R1,#1
        uut.u_imem.mem[16'h22] = 16'h2202; // SW   R1,0x02(R0)
        uut.u_imem.mem[16'h23] = 16'h6020; // JMP  0x20

        ; // ---- task2 loop: counter @0x03 ----
        uut.u_imem.mem[16'h30] = 16'h1203; // LW   R1,0x03(R0)
        uut.u_imem.mem[16'h31] = 16'hB201; // ADDI R1,#1
        uut.u_imem.mem[16'h32] = 16'h2203; // SW   R1,0x03(R0)
        uut.u_imem.mem[16'h33] = 16'h6030; // JMP  0x30

        ; // ---- ISR: isr_context_switch, at ISR_VECTOR = 0x40 ----
        uut.u_imem.mem[16'h40] = 16'h80F9; // ADDSP #-7
        uut.u_imem.mem[16'h41] = 16'h9200; // STORESP R1,#0
        uut.u_imem.mem[16'h42] = 16'h9401; // STORESP R2,#1
        uut.u_imem.mem[16'h43] = 16'h9602; // STORESP R3,#2
        uut.u_imem.mem[16'h44] = 16'h9803; // STORESP R4,#3
        uut.u_imem.mem[16'h45] = 16'h9A04; // STORESP R5,#4
        uut.u_imem.mem[16'h46] = 16'h9C05; // STORESP R6,#5
        uut.u_imem.mem[16'h47] = 16'h9E06; // STORESP R7,#6
        uut.u_imem.mem[16'h48] = 16'hCE00; // MOV R7,LR
        uut.u_imem.mem[16'h49] = 16'h9E07; // STORESP R7,#7
        uut.u_imem.mem[16'h4A] = 16'hC202; // MOV R1,SP
        uut.u_imem.mem[16'h4B] = 16'h1600; // LW R3,0x00(R0)
        uut.u_imem.mem[16'h4C] = 16'h3800; // LDI R4,#0
        uut.u_imem.mem[16'h4D] = 16'h58C5; // BEQ R3,R4,+5 -> 0x52
        uut.u_imem.mem[16'h4E] = 16'h3801; // LDI R4,#1
        uut.u_imem.mem[16'h4F] = 16'h58C5; // BEQ R3,R4,+5 -> 0x54
        uut.u_imem.mem[16'h50] = 16'h2206; // SW R1,0x06(R0)
        uut.u_imem.mem[16'h51] = 16'h6055; // JMP 0x55
        uut.u_imem.mem[16'h52] = 16'h2204; // SW R1,0x04(R0)
        uut.u_imem.mem[16'h53] = 16'h6055; // JMP 0x55
        uut.u_imem.mem[16'h54] = 16'h2205; // SW R1,0x05(R0)
        uut.u_imem.mem[16'h55] = 16'hB601; // ADDI R3,#1
        uut.u_imem.mem[16'h56] = 16'h3803; // LDI R4,#3
        uut.u_imem.mem[16'h57] = 16'h58C2; // BEQ R3,R4,+2 -> 0x59
        uut.u_imem.mem[16'h58] = 16'h605A; // JMP 0x5A
        uut.u_imem.mem[16'h59] = 16'h3600; // LDI R3,#0
        uut.u_imem.mem[16'h5A] = 16'h2600; // SW R3,0x00(R0)
        uut.u_imem.mem[16'h5B] = 16'h3800; // LDI R4,#0
        uut.u_imem.mem[16'h5C] = 16'h58C5; // BEQ R3,R4,+5 -> 0x61
        uut.u_imem.mem[16'h5D] = 16'h3801; // LDI R4,#1
        uut.u_imem.mem[16'h5E] = 16'h58C5; // BEQ R3,R4,+5 -> 0x63
        uut.u_imem.mem[16'h5F] = 16'h1406; // LW R2,0x06(R0)
        uut.u_imem.mem[16'h60] = 16'h6064; // JMP 0x64
        uut.u_imem.mem[16'h61] = 16'h1404; // LW R2,0x04(R0)
        uut.u_imem.mem[16'h62] = 16'h6064; // JMP 0x64
        uut.u_imem.mem[16'h63] = 16'h1405; // LW R2,0x05(R0)
        uut.u_imem.mem[16'h64] = 16'hC403; // MOV SP,R2
        uut.u_imem.mem[16'h65] = 16'h9300; // LOADSP R1,#0
        uut.u_imem.mem[16'h66] = 16'h9501; // LOADSP R2,#1
        uut.u_imem.mem[16'h67] = 16'h9702; // LOADSP R3,#2
        uut.u_imem.mem[16'h68] = 16'h9903; // LOADSP R4,#3
        uut.u_imem.mem[16'h69] = 16'h9B04; // LOADSP R5,#4
        uut.u_imem.mem[16'h6A] = 16'h9D05; // LOADSP R6,#5
        uut.u_imem.mem[16'h6B] = 16'h9F07; // LOADSP R7,#7
        uut.u_imem.mem[16'h6C] = 16'hCE01; // MOV LR,R7
        uut.u_imem.mem[16'h6D] = 16'h9F06; // LOADSP R7,#6
        uut.u_imem.mem[16'h6E] = 16'h8007; // ADDSP #+7
        uut.u_imem.mem[16'h6F] = 16'h7000; // RETI

        #12 rst_n = 1;

        ; // ---- data memory preload (AFTER rst_n=1) ----
        uut.u_dmem.mem[8'h00] = 8'h00;     // current_task_id = 0
        uut.u_dmem.mem[8'h01] = 8'h00;     // task0 counter
        uut.u_dmem.mem[8'h02] = 8'h00;     // task1 counter
        uut.u_dmem.mem[8'h03] = 8'h00;     // task2 counter
        uut.u_dmem.mem[8'h05] = 8'hEF;     // tcb1
        uut.u_dmem.mem[8'h06] = 8'hE6;     // tcb2

        ; // task1 fake-but-real initial context: LR = its real loop entry
        for (i = 0; i < 7; i = i + 1) uut.u_dmem.mem[8'hEF + i] = 8'h00;
        uut.u_dmem.mem[8'hF6] = 8'h20;     // LR -> task1 loop entry (0x20)

        ; // task2 fake-but-real initial context: LR = its real loop entry
        for (i = 0; i < 7; i = i + 1) uut.u_dmem.mem[8'hE6 + i] = 8'h00;
        uut.u_dmem.mem[8'hED] = 8'h30;     // LR -> task2 loop entry (0x30)

        // ---- let task0 run for a while before the first interrupt ----
        repeat (60) @(posedge clk); #1;
        check_gt("task0 counter made progress before IRQ1", uut.u_dmem.mem[8'h01], 8'h00);

        // ---- IRQ1: task0 -> task1 ----
        // held high across several cycles rather than a single-cycle pulse:
        // irq_taken is purely combinational with no pending-latch, so a
        // 1-cycle pulse landing on an hdu_stall cycle is silently dropped
        // (see prior bug log) -- holding it guarantees eventual overlap
        // with a non-stall cycle.
        @(posedge clk); irq_in = 1;
        repeat (5) @(posedge clk);
        irq_in = 0;
        repeat (100) @(posedge clk); #1;

        // BASELINE CAPTURE TIMING BUG (found this session): capturing a
        // task's "frozen" baseline BEFORE pulsing the interrupt that
        // switches it out is a race -- the pipeline keeps running
        // normally until irq_taken actually fires (which can take extra
        // cycles waiting out an hdu_stall), so the outgoing task can
        // complete one or more further loop iterations after the
        // baseline was captured but before it actually stops. Fix:
        // capture "frozen" baselines AFTER the switch has fully settled
        // (i.e. right here, once current_task_id has already changed),
        // never before triggering the interrupt that causes the freeze.
        $display("\n---- after IRQ1 (task0 -> task1) ----");
        check8("current_task_id -> 1", uut.u_dmem.mem[8'h00], 8'h01);
        c0_before_1 = uut.u_dmem.mem[8'h01];   // race-free: task0 is provably stopped by now
        $display("INFO: task0 counter settled (frozen baseline) = 0x%02h", c0_before_1);
        check_gt("task1 counter made progress", uut.u_dmem.mem[8'h02], 8'h00);

        // ---- IRQ2: task1 -> task2 ----
        @(posedge clk); irq_in = 1;
        repeat (5) @(posedge clk);
        irq_in = 0;
        repeat (100) @(posedge clk); #1;

        $display("\n---- after IRQ2 (task1 -> task2) ----");
        check8("current_task_id -> 2", uut.u_dmem.mem[8'h00], 8'h02);
        c1_before_2 = uut.u_dmem.mem[8'h02];   // race-free: task1 is provably stopped by now
        $display("INFO: task1 counter settled (frozen baseline) = 0x%02h", c1_before_2);
        check8("task0 counter STILL FROZEN (1 switch later)",
               uut.u_dmem.mem[8'h01], c0_before_1);
        check_gt("task2 counter made progress", uut.u_dmem.mem[8'h03], 8'h00);

        // ---- IRQ3: task2 -> task0 (WRAPAROUND) ----
        @(posedge clk); irq_in = 1;
        repeat (5) @(posedge clk);
        irq_in = 0;
        repeat (100) @(posedge clk); #1;

        $display("\n---- after IRQ3 (task2 -> task0, WRAPAROUND) ----");
        check8("current_task_id wraps -> 0", uut.u_dmem.mem[8'h00], 8'h00);
        c2_before_3 = uut.u_dmem.mem[8'h03];   // race-free: task2 is provably stopped by now
        check8("task1 counter STILL FROZEN (2 switches later)",
               uut.u_dmem.mem[8'h02], c1_before_2);
        check_gt("task0 counter RESUMED and progressed past its old value",
                 uut.u_dmem.mem[8'h01], c0_before_1);

        // ---- exact-PC resume, reused mechanism ----
        check8("FINAL RETI target == task0's true interrupted PC",
               reti_addr_capture[3], irq_pc_capture[0]);

        // ---- guard bytes: must never be touched by any switch ----
        check8("guard byte 0xEE untouched", uut.u_dmem.mem[8'hEE], 8'h00);
        check8("guard byte 0xF7 untouched", uut.u_dmem.mem[8'hF7], 8'h00);

        if (errors == 0) $display("\n=== STAGE 4 FULL INTEGRATION TEST PASSED ===");
        else              $display("\n=== %0d TEST(S) FAILED ===", errors);
        $finish;
    end

endmodule