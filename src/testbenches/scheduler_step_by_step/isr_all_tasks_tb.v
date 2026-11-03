`timescale 1ns/1ps
// -----------------------------------------------------------------------
// isr_all_tasks_tb.v
// Extends isr_alone_tb.v's single-transition test to a FULL round-robin
// cycle: task0->task1->task2->task0, exercising the wraparound
// ((2+1) mod 3 = 0) path that isr_alone_tb.v never touches.
//
// PREREQUISITE: assumes the hazard_detection_unit.v OP_MOVLR write-
// direction stall fix (see isr_alone_tb.v's bug log, item 3) is already
// applied. Without it this test will fail the same way isr_alone_tb.v
// originally did.
//
// Strategy:
//   - task0 gets a REAL live context (boot stub + preamble), same as
//     isr_alone_tb.v.
//   - task1 and task2 start from FAKE pre-loaded "already saved"
//     contexts, same trick as isr_alone_tb.v, but now placed at their
//     REAL memory-map addresses (task1 stack 0xEF-0xF6, task2 stack
//     0xE6-0xED) instead of arbitrary ones -- doubles as a memory-map
//     sanity check.
//   - Rather than a marker-instruction side effect (fragile once you
//     don't know exactly which NOP address an irq lands on), exact-PC
//     resume is proven the same way irq_entry_tb.v proves it: capture
//     id_pc at the moment irq_taken fires for IRQ1 (task0's true
//     interrupted PC), capture ex_pc_redirect_addr at every RETI
//     resolution (4 total: 1 boot-stub + 3 ISR returns), and check the
//     4th RETI's target equals the first captured PC.
//
// Program layout:
//   0x00-0x02  boot stub (RETI-as-enable trick, same as isr_alone_tb.v)
//   0x03-0x04  task0 preamble: SP = 0xFF (top of its real stack region)
//   0x05-0x07  task0 "running" (default NOP) -- IRQ1 lands here
//   0x08-0x0B  task1 "running" (default NOP) -- IRQ2 lands here
//   0x0C-0x0F  task2 "running" (default NOP) -- IRQ3 lands here (wrap)
//   0x40-0x6F  ISR (isr_context_switch, unchanged from isr_alone_tb.v)
//
// Data memory preload (all AFTER rst_n=1 -- see isr_alone_tb.v bug log
// item 2, same reset-clear timing trap applies here):
//   0x00  current_task_id = 0x00
//   0x05  tcb1 = 0xEF          (base of task1's real stack region)
//   0x06  tcb2 = 0xE6          (base of task2's real stack region)
//   0xEF..0xF6  fake saved R1-R7,LR for task1 (LR unused now -- see below)
//   0xE6..0xED  fake saved R1-R7,LR for task2 (LR unused now -- see below)
//   0x04 (tcb0), guard bytes 0xEE/0xF7 -- left at 0, written/verified below
//
// NOTE: task1/task2's fake "saved LR" slots are no longer used as jump
// markers (that approach doesn't scale to 3 chained switches without
// knowing exact irq-landing addresses). They're set to a recognizable
// but otherwise-inert value and simply checked for correct LOAD -- the
// actual proof of correct RETI targeting comes from the capture
// mechanism above, exercised fully only on the FINAL (task0) resume,
// since that's the one with a real, testbench-known original PC.
//
// ASSUMPTIONS (same as isr_alone_tb.v -- verify against your files):
//   - uut.u_imem.mem[addr], uut.u_dmem.mem[addr], uut.u_rf.regs[n],
//     uut.u_sp.sp_out as before
//   - uut.irq_taken, uut.id_pc, uut.ex_pc_redirect, uut.ex_br_type,
//     uut.ex_pc_redirect_addr are all used directly in irq_entry_tb.v,
//     so these hierarchical paths are already confirmed valid
// -----------------------------------------------------------------------
module isr_all_tasks_tb;

    reg clk, rst_n, irq_in;
    integer i;
    integer errors = 0;
    reg [7:0] sp_task0_live;

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

    // ---- capture: task0's true interrupted PC, from the FIRST real irq ----
    reg [7:0] irq_pc_capture [0:2];
    integer   irq_taken_count;

    always @(posedge clk) begin
        if (rst_n && uut.irq_taken) begin
            irq_pc_capture[irq_taken_count] <= uut.id_pc;
            irq_taken_count <= irq_taken_count + 1;
        end
    end

    // ---- capture: every RETI's actual resolved target address ----
    // (1 boot-stub RETI + 3 real ISR-ending RETIs = 4 total, in order)
    //
    // BUG FOUND: ex_br_type==2'b11 alone is NOT unique to RETI -- per
    // processor_pipel_haz.v's own comment ("JMP/RETI"), JMP shares the
    // same br_type encoding. This monitor was originally miscounting
    // every JMP inside the ISR as a RETI, corrupting all 4 indices.
    // Fix: also gate on ex_pc_target_sel, which is what actually
    // distinguishes them at the pc-target mux (in2=lr_out for RETI).
    // ASSUMPTION: standard in0..in3 <-> sel 00..11 mapping -- confirm
    // ex_pc_target_sel==2'b10 specifically at a RETI in your waveform
    // before trusting this fully.
    reg [7:0] reti_addr_capture [0:3];
    integer   reti_count;
 
    always @(posedge clk) begin
        if (rst_n && uut.ex_pc_redirect && uut.ex_br_type == 2'b11
                   && uut.ex_pc_target_sel == 2'b10) begin
            reti_addr_capture[reti_count] <= uut.ex_pc_redirect_addr;
            reti_count <= reti_count + 1;
        end
    end

    initial begin
        clk = 0; rst_n = 0; irq_in = 0;
        irq_taken_count = 0;
        reti_count = 0;

        for (i = 0; i < 256; i = i + 1) uut.u_imem.mem[i] = 16'h0000;

        ; // ---- boot stub: arm GIE=1 (see isr_alone_tb.v bug log item 1) ----
        uut.u_imem.mem[16'h00] = 16'h3E03; // LDI  R7,0x03
        uut.u_imem.mem[16'h01] = 16'hCE01; // MOV  LR,R7
        uut.u_imem.mem[16'h02] = 16'h7000; // RETI  -> GIE=1, jump to 0x03

        ; // ---- task0 preamble: real live SP = 0xFF (top of 0xF8-0xFF) ----
        uut.u_imem.mem[16'h03] = 16'h3EFF; // LDI  R7,0xFF
        uut.u_imem.mem[16'h04] = 16'hCE03; // MOV  SP,R7
        ; // 0x05-0x0F left as default NOP: task0/task1/task2 "running" windows

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

        ; // ---- data memory preload (AFTER rst_n=1 -- see bug log item 2) ----
        uut.u_dmem.mem[8'h00] = 8'h00;     // current_task_id = 0
        uut.u_dmem.mem[8'h05] = 8'hEF;     // tcb1 = base of task1's real region
        uut.u_dmem.mem[8'h06] = 8'hE6;     // tcb2 = base of task2's real region

        ; // task1 fake saved context: region 0xEF-0xF6 (matches real map)
        uut.u_dmem.mem[8'hEF] = 8'h11;     // R1
        uut.u_dmem.mem[8'hF0] = 8'h22;     // R2
        uut.u_dmem.mem[8'hF1] = 8'h33;     // R3
        uut.u_dmem.mem[8'hF2] = 8'h44;     // R4
        uut.u_dmem.mem[8'hF3] = 8'h55;     // R5
        uut.u_dmem.mem[8'hF4] = 8'h66;     // R6
        uut.u_dmem.mem[8'hF5] = 8'h77;     // R7
        uut.u_dmem.mem[8'hF6] = 8'h99;     // LR slot -- inert value, load-only check

        ; // task2 fake saved context: region 0xE6-0xED (matches real map)
        uut.u_dmem.mem[8'hE6] = 8'h12;     // R1
        uut.u_dmem.mem[8'hE7] = 8'h23;     // R2
        uut.u_dmem.mem[8'hE8] = 8'h34;     // R3
        uut.u_dmem.mem[8'hE9] = 8'h45;     // R4
        uut.u_dmem.mem[8'hEA] = 8'h56;     // R5
        uut.u_dmem.mem[8'hEB] = 8'h67;     // R6
        uut.u_dmem.mem[8'hEC] = 8'h78;     // R7
        uut.u_dmem.mem[8'hED] = 8'h99;     // LR slot -- inert value, load-only check

        // ---- boot stub + preamble settle, capture task0's real live SP ----
        repeat (20) @(posedge clk); #1;
        sp_task0_live = uut.u_sp.sp_out;
        $display("INFO: task0 live SP before IRQ1 = 0x%02h", sp_task0_live);
        check8("task0 live SP == 0xFF (top of its stack region)",
               sp_task0_live, 8'hFF);

        // ---- IRQ1: task0 -> task1 ----
        @(posedge clk); irq_in = 1;
        @(posedge clk); irq_in = 0;
        // window sized off the ~76-cycle ISR runtime you measured, with margin
        repeat (100) @(posedge clk); #1;

        $display("\n---- after IRQ1 (task0 -> task1) ----");
        check8("current_task_id -> 1",   uut.u_dmem.mem[8'h00], 8'h01);
        check8("tcb0 = task0 live SP-7", uut.u_dmem.mem[8'h04], sp_task0_live - 8'd7);
        check8("R1 (task1 fake ctx)",    uut.u_rf.regs[1], 8'h11);
        check8("R7 (task1 fake ctx)",    uut.u_rf.regs[7], 8'h77);
        check8("SP after switch (raw)",  uut.u_sp.sp_out, 8'hF6); // base 0xEF + 7

        // ---- IRQ2: task1 -> task2 ----
        @(posedge clk); irq_in = 1;
        @(posedge clk); irq_in = 0;
        repeat (100) @(posedge clk); #1;

        $display("\n---- after IRQ2 (task1 -> task2) ----");
        check8("current_task_id -> 2",   uut.u_dmem.mem[8'h00], 8'h02);
        check8("tcb1 unchanged (task1 resumed same region it started in)",
               uut.u_dmem.mem[8'h05], 8'hEF);
        check8("R1 (task2 fake ctx)",    uut.u_rf.regs[1], 8'h12);
        check8("R7 (task2 fake ctx)",    uut.u_rf.regs[7], 8'h78);
        check8("SP after switch (raw)",  uut.u_sp.sp_out, 8'hED); // base 0xE6 + 7

        // ---- IRQ3: task2 -> task0 (WRAPAROUND: (2+1) mod 3 = 0) ----
        @(posedge clk); irq_in = 1;
        @(posedge clk); irq_in = 0;
        repeat (50) @(posedge clk); #1;

        $display("\n---- after IRQ3 (task2 -> task0, WRAPAROUND) ----");
        check8("current_task_id wraps -> 0", uut.u_dmem.mem[8'h00], 8'h00);
        check8("tcb2 unchanged (task2 resumed same region it started in)",
               uut.u_dmem.mem[8'h06], 8'hE6);
        // task0's REAL saved context from IRQ1 -- R1-R6 untouched since reset (0),
        // R7 == 0xFF (its real value from the preamble)
        check8("R1 (task0 real ctx, untouched)", uut.u_rf.regs[1], 8'h00);
        check8("R6 (task0 real ctx, untouched)", uut.u_rf.regs[6], 8'h00);
        check8("R7 (task0 real ctx == 0xFF)",    uut.u_rf.regs[7], 8'hFF);
        check8("SP restored to 0xFF (top of task0's region)",
               uut.u_sp.sp_out, 8'hFF);

        // ---- the real payoff: exact-PC resume across the full cycle ----
        // 4th RETI (index 3) is the wraparound return; its actual redirect
        // target must equal the PC captured at the very first interrupt.
        check8("FINAL RETI target == task0's true interrupted PC",
               reti_addr_capture[3], irq_pc_capture[0]);
        $display("INFO: task0 was interrupted at PC=0x%02h, final RETI targeted 0x%02h",
                 irq_pc_capture[0], reti_addr_capture[3]);

        // ---- guard bytes: must never be touched by any switch ----
        check8("guard byte 0xEE untouched", uut.u_dmem.mem[8'hEE], 8'h00);
        check8("guard byte 0xF7 untouched", uut.u_dmem.mem[8'hF7], 8'h00);

        if (errors == 0) $display("\n=== FULL ROUND-ROBIN CYCLE TEST PASSED (incl. wraparound) ===");
        else              $display("\n=== %0d TEST(S) FAILED ===", errors);
        
        repeat (30) @(posedge clk); #1;
        $finish;
    end

endmodule