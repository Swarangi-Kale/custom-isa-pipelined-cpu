`timescale 1ns/1ps
// -----------------------------------------------------------------------
// isr_hw_task_loops_tb.v
// Phase D, step 2: real task loops + real hardware FSM context switch,
// wired via the new task-select code. Direct hardware-mechanism
// counterpart to isr_task_loops_tb.v (Phase C's software baseline) --
// same task loops, same memory map, same fake-seeded initial contexts
// for task1/task2, same correctness checks -- only the switch mechanism
// itself changed (ctx_switch_fsm.v does save/restore; software only
// does TCB bookkeeping + dispatch + one RESTORE_CTX instruction).
//
// Task-select code is ~27 instructions (0x40-0x5A) vs Phase C's 48
// (0x40-0x6F) -- no more STORESP/LOADSP/MOV-LR-scratch save/restore,
// hardware does that in a fixed 8-cycle burst per direction instead.
//
// Program layout:
//   0x00-0x02  boot stub (unaffected by FSM changes -- RETI's own
//              control-unit case is untouched, only used here to set
//              GIE=1 once; RESTORE_CTX handles all real returns)
//   0x03-0x05  task0 preamble: SP=0xFF, JMP into its loop
//   0x10-0x13  task0 loop: counter @0x01
//   0x20-0x23  task1 loop: counter @0x02
//   0x30-0x33  task2 loop: counter @0x03
//   0x40-0x5A  TASK_SELECT_VECTOR: dispatch + RESTORE_CTX (replaces the
//              old 0x40-0x6F software ISR)
//
// Data memory preload: IDENTICAL to isr_task_loops_tb.v -- the FSM's
// save/restore data format (8 bytes: R1-R7 @ offsets 0-6, LR @ offset
// 7) exactly matches the software convention already established, so
// task1/task2's fake-seeded initial contexts need no changes.
//
// PREREQUISITE: processor_hw_context_switch (renamed copy of
// processor_pipel_haz, per project convention) with all ctx_switch_fsm.v
// integration applied, including the fsm_restore_base_out port fix.
// -----------------------------------------------------------------------
module final_hw_ctx_switch_tb;

    reg clk, rst_n, irq_in;
    integer i;
    integer errors = 0;

    processor_hw_context_switch uut (
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

    // ---- exact-PC-resume capture, task0's side (unchanged mechanism) ----
    reg [7:0] irq_pc_capture [0:2];
    integer   irq_taken_count;
    always @(posedge clk) begin
        if (rst_n && uut.irq_taken) begin
            irq_pc_capture[irq_taken_count] <= uut.id_pc;
            irq_taken_count <= irq_taken_count + 1;
        end
    end

    // ---- exact-PC-resume capture, restore side -- SIMPLER than the
    //      software version: fsm_restore_done is unambiguous (unlike
    //      ex_br_type==2'b11, which needed disambiguating from JMP),
    //      so no pc_target_sel gating needed here at all ----
    reg [7:0] fsm_restore_target [0:2];
    integer   fsm_restore_count;
    always @(posedge clk) begin
        if (rst_n && uut.fsm_restore_done) begin
            fsm_restore_target[fsm_restore_count] <= uut.pc_redirect_addr_final;
            fsm_restore_count <= fsm_restore_count + 1;
        end
    end

    reg [7:0] c0_before_1, c1_before_2, c2_before_3;

    initial begin
        clk = 0; rst_n = 0; irq_in = 0;
        irq_taken_count = 0; fsm_restore_count = 0;

        for (i = 0; i < 256; i = i + 1) uut.u_imem.mem[i] = 16'h0000;

        ; // ---- boot stub ----
        uut.u_imem.mem[16'h00] = 16'h3E03; // LDI  R7,0x03
        uut.u_imem.mem[16'h01] = 16'hCE01; // MOV  LR,R7
        uut.u_imem.mem[16'h02] = 16'h7000; // RETI -> GIE=1, jump to 0x03

        ; // ---- task0 preamble ----
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

        ; // ---- TASK_SELECT_VECTOR = 0x40: dispatch + RESTORE_CTX ----
        ; // no save/restore instructions -- hardware already did that
        ; // before PC ever reached here
        uut.u_imem.mem[16'h40] = 16'hC202; // MOV R1,SP        (outgoing base SP)
        uut.u_imem.mem[16'h41] = 16'h1600; // LW R3,0x00(R0)   (outgoing task_id)
        uut.u_imem.mem[16'h42] = 16'h3800; // LDI R4,#0
        uut.u_imem.mem[16'h43] = 16'h58C5; // BEQ R3,R4,+5 -> 0x48 (save_task0)
        uut.u_imem.mem[16'h44] = 16'h3801; // LDI R4,#1
        uut.u_imem.mem[16'h45] = 16'h58C5; // BEQ R3,R4,+5 -> 0x4A (save_task1)
        uut.u_imem.mem[16'h46] = 16'h2206; // SW R1,0x06(R0)   (task_id==2 fallthrough)
        uut.u_imem.mem[16'h47] = 16'h604B; // JMP 0x4B
        uut.u_imem.mem[16'h48] = 16'h2204; // SW R1,0x04(R0)   (save_task0)
        uut.u_imem.mem[16'h49] = 16'h604B; // JMP 0x4B
        uut.u_imem.mem[16'h4A] = 16'h2205; // SW R1,0x05(R0)   (save_task1, falls through)
        uut.u_imem.mem[16'h4B] = 16'hB601; // ADDI R3,#1       (after_save)
        uut.u_imem.mem[16'h4C] = 16'h3803; // LDI R4,#3
        uut.u_imem.mem[16'h4D] = 16'h58C2; // BEQ R3,R4,+2 -> 0x4F (wrap_to_zero)
        uut.u_imem.mem[16'h4E] = 16'h6050; // JMP 0x50
        uut.u_imem.mem[16'h4F] = 16'h3600; // LDI R3,#0        (wrap_to_zero)
        uut.u_imem.mem[16'h50] = 16'h2600; // SW R3,0x00(R0)   (store_new_id)
        uut.u_imem.mem[16'h51] = 16'h3800; // LDI R4,#0
        uut.u_imem.mem[16'h52] = 16'h58C5; // BEQ R3,R4,+5 -> 0x57 (load_task0)
        uut.u_imem.mem[16'h53] = 16'h3801; // LDI R4,#1
        uut.u_imem.mem[16'h54] = 16'h58C5; // BEQ R3,R4,+5 -> 0x59 (load_task1)
        uut.u_imem.mem[16'h55] = 16'h1406; // LW R2,0x06(R0)   (new_id==2 fallthrough)
        uut.u_imem.mem[16'h56] = 16'h605A; // JMP 0x5A
        uut.u_imem.mem[16'h57] = 16'h1404; // LW R2,0x04(R0)   (load_task0)
        uut.u_imem.mem[16'h58] = 16'h605A; // JMP 0x5A
        uut.u_imem.mem[16'h59] = 16'h1405; // LW R2,0x05(R0)   (load_task1, falls through)
        uut.u_imem.mem[16'h5A] = 16'hA400; // RESTORE_CTX R2   (after_load -- hands off to hardware)

        #12 rst_n = 1;

        // ---- data memory preload (AFTER rst_n=1, unchanged from
        //      isr_task_loops_tb.v -- same 8-byte block format) ----
        uut.u_dmem.mem[8'h00] = 8'h00;
        uut.u_dmem.mem[8'h01] = 8'h00;
        uut.u_dmem.mem[8'h02] = 8'h00;
        uut.u_dmem.mem[8'h03] = 8'h00;
        uut.u_dmem.mem[8'h05] = 8'hEF;
        uut.u_dmem.mem[8'h06] = 8'hE6;
        for (i = 0; i < 7; i = i + 1) uut.u_dmem.mem[8'hEF + i] = 8'h00;
        uut.u_dmem.mem[8'hF6] = 8'h20;     // task1 fake LR -> its real loop entry
        for (i = 0; i < 7; i = i + 1) uut.u_dmem.mem[8'hE6 + i] = 8'h00;
        uut.u_dmem.mem[8'hED] = 8'h30;     // task2 fake LR -> its real loop entry

        // ---- let task0 run before the first interrupt ----
        repeat (60) @(posedge clk); #1;
        check_gt("task0 counter made progress before IRQ1", uut.u_dmem.mem[8'h01], 8'h00);

        // ---- IRQ1: task0 -> task1 ----
        @(posedge clk); irq_in = 1;
        repeat (5) @(posedge clk);
        irq_in = 0;
        repeat (100) @(posedge clk); #1;   // budget likely generous now -- retune once measured

        $display("\n---- after IRQ1 (task0 -> task1) ----");
        check8("current_task_id -> 1", uut.u_dmem.mem[8'h00], 8'h01);
        c0_before_1 = uut.u_dmem.mem[8'h01];   // race-free: task0 provably stopped by now
        check_gt("task1 counter made progress", uut.u_dmem.mem[8'h02], 8'h00);

        // ---- IRQ2: task1 -> task2 ----
        @(posedge clk); irq_in = 1;
        repeat (5) @(posedge clk);
        irq_in = 0;
        repeat (100) @(posedge clk); #1;

        $display("\n---- after IRQ2 (task1 -> task2) ----");
        check8("current_task_id -> 2", uut.u_dmem.mem[8'h00], 8'h02);
        c1_before_2 = uut.u_dmem.mem[8'h02];
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
        c2_before_3 = uut.u_dmem.mem[8'h03];
        check8("task1 counter STILL FROZEN (2 switches later)",
               uut.u_dmem.mem[8'h02], c1_before_2);
        check_gt("task0 counter RESUMED and progressed past its old value",
                 uut.u_dmem.mem[8'h01], c0_before_1);

        // ---- exact-PC resume: 3rd fsm_restore_done (index 2) is the
        //      wraparound return; its target must equal task0's true
        //      interrupted PC captured at the very first interrupt ----
        check8("FINAL RESTORE target == task0's true interrupted PC",
               fsm_restore_target[2], irq_pc_capture[0]);

        // ---- guard bytes: must never be touched ----
        check8("guard byte 0xEE untouched", uut.u_dmem.mem[8'hEE], 8'h00);
        check8("guard byte 0xF7 untouched", uut.u_dmem.mem[8'hF7], 8'h00);

        if (errors == 0) $display("\n=== HW-FSM FULL ROUND-ROBIN TEST PASSED ===");
        else              $display("\n=== %0d TEST(S) FAILED ===", errors);
        $finish;
    end

endmodule