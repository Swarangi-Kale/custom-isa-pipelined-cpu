`timescale 1ns/1ps
// -----------------------------------------------------------------------
// ctx_fsm_alone_tb.v
// Phase D, step 1: isolated test of ctx_switch_fsm.v -- single fake
// SAVE, single fake RESTORE, no real task loop, no real round-robin
// bookkeeping. Same discipline as isr_alone_tb.v was for Phase C: prove
// the mechanism in isolation before wiring it into anything bigger.
//
// Design choices, and why:
//   - GPRs get DISTINCTIVE, KNOWN values (0xA1-0xA7) before the fake
//     interrupt, not left at their boring post-reset zeros -- this lets
//     SAVE's correctness be checked against values we actually control,
//     stronger than what task0's real (all-zero) registers could prove
//     in the Phase C tests.
//   - The task-select code is DELIBERATELY the two-instruction
//     LW Rn,tcb(R0); RESTORE_CTX Rn pattern -- the exact same
//     load-use-hazard shape that bit MOV SP,Rd and LOADSP->MOV LR,Rd
//     twice already this session. If hazard_detection_unit.v's
//     unconditional OP_CTXRESTORE inclusion in uses_rs1 has any gap
//     analogous to those, this is where it will show up.
//   - A direct PC-hold monitor checks the literal "zero instructions
//     fetched during the burst" claim, rather than inferring it.
//
// Program layout:
//   0x00-0x02  boot stub (RETI-as-GIE-enable trick, unaffected by the
//              FSM changes -- RETI's own control-unit case is untouched)
//   0x03-0x04  preamble: SP = 0xFF
//   0x05-0x0B  GPR init: LDI R1..R7 = 0xA1..0xA7
//   0x0C+      default NOP ("running") -- fake irq_in lands here
//   0x40       TASK_SELECT_VECTOR: LW R2,0x05(R0); RESTORE_CTX R2
//   0x50       marker (LDI R6,0xCC) -- proves PC really redirected to
//              the restored LR value after RESTORE completes
//
// Data memory preload (AFTER rst_n=1 -- data_memory.v's sync-reset
// wipes anything written before that, see prior bug log):
//   0x05  pointer = 0xE0 (fake "next task" base SP)
//   0xE0-0xE6  fake saved R1-R7 = 0xB1-0xB7
//   0xE7  fake saved LR = 0x50 (-> marker)
//
// PREREQUISITE: all ctx_switch_fsm.v integration changes from the other
// session's design applied (control_unit_pipelined.v, hazard_detection_
// unit.v, id_ex_reg_modified.v, ctx_switch_fsm.v, processor_pipel_haz.v).
//
// ASSUMPTIONS: uut.fsm_active, uut.pc_out, uut.gie_out, uut.irq_taken,
// uut.id_pc hierarchical paths as established/used throughout this
// project's other testbenches. LR's own path is still unknown (same
// caveat as isr_alone_tb.v) -- LR correctness is verified indirectly
// here via the marker side-effect, same trick as before.
// -----------------------------------------------------------------------
module ctx_fsm_alone_tb;

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

    // ---- capture task's true interrupted PC (same trick as before) ----
    reg [7:0] captured_resume_pc;
    reg       resume_pc_captured;
    always @(posedge clk) begin
        if (!rst_n) begin
            resume_pc_captured <= 1'b0;
        end else if (uut.irq_taken && !resume_pc_captured) begin
            captured_resume_pc <= uut.id_pc;
            resume_pc_captured <= 1'b1;
        end
    end

    // ---- PC-hold monitor: PC must not move for the ENTIRE duration of
    //      either burst -- this is the literal "zero instructions
    //      fetched" claim, checked directly rather than assumed ----
    reg       fsm_active_prev;
    reg [7:0] pc_at_burst_start;
    always @(posedge clk) begin
        if (!rst_n) begin
            fsm_active_prev <= 1'b0;
        end else begin
            if (uut.fsm_active && !fsm_active_prev)
                pc_at_burst_start <= uut.pc_out;
            else if (uut.fsm_active && fsm_active_prev && uut.pc_out !== pc_at_burst_start) begin
                $display("FAIL: PC moved during FSM burst (was 0x%02h, now 0x%02h) @ t=%0t",
                          pc_at_burst_start, uut.pc_out, $time);
                errors = errors + 1;
            end
            fsm_active_prev <= uut.fsm_active;
        end
    end

    // ---- PC-after-SAVE-redirect capture: pc_out only equals
    //      TASK_SELECT_VECTOR for ONE instant (the cycle right after
    //      fsm_save_done), then keeps advancing as task-select code
    //      fetches sequentially -- sampling it at an arbitrary later
    //      delay catches it mid-race, not at rest. Capture at the
    //      correct instant instead of guessing a safe-looking delay.
    reg       fsm_save_done_prev;
    reg [7:0] pc_after_save_redirect;
    reg       pc_after_save_captured;
    always @(posedge clk) begin
        if (!rst_n) begin
            fsm_save_done_prev    <= 1'b0;
            pc_after_save_captured <= 1'b0;
        end else begin
            if (fsm_save_done_prev && !pc_after_save_captured) begin
                pc_after_save_redirect <= uut.pc_out;
                pc_after_save_captured <= 1'b1;
            end
            fsm_save_done_prev <= uut.fsm_save_done;
        end
    end

    initial begin
        clk = 0; rst_n = 0; irq_in = 0;

        for (i = 0; i < 256; i = i + 1) uut.u_imem.mem[i] = 16'h0000;

        ; // ---- boot stub ----
        uut.u_imem.mem[16'h00] = 16'h3E03; // LDI  R7,0x03
        uut.u_imem.mem[16'h01] = 16'hCE01; // MOV  LR,R7
        uut.u_imem.mem[16'h02] = 16'h7000; // RETI -> GIE=1, jump to 0x03

        ; // ---- preamble: SP = 0xFF ----
        uut.u_imem.mem[16'h03] = 16'h3EFF; // LDI  R7,0xFF
        uut.u_imem.mem[16'h04] = 16'hCE03; // MOV  SP,R7

        ; // ---- GPR init: distinctive known values for SAVE to prove ----
        uut.u_imem.mem[16'h05] = 16'h32A1; // LDI R1,0xA1
        uut.u_imem.mem[16'h06] = 16'h34A2; // LDI R2,0xA2
        uut.u_imem.mem[16'h07] = 16'h36A3; // LDI R3,0xA3
        uut.u_imem.mem[16'h08] = 16'h38A4; // LDI R4,0xA4
        uut.u_imem.mem[16'h09] = 16'h3AA5; // LDI R5,0xA5
        uut.u_imem.mem[16'h0A] = 16'h3CA6; // LDI R6,0xA6
        uut.u_imem.mem[16'h0B] = 16'h3EA7; // LDI R7,0xA7
        ; // 0x0C+ default NOP: "running", fake irq_in lands here

        ; // ---- TASK_SELECT_VECTOR = 0x40 ----
        ; // deliberately the LW-then-RESTORE_CTX hazard pattern
        uut.u_imem.mem[16'h40] = 16'h1405; // LW R2,0x05(R0)   -> R2 = 0xE0
        uut.u_imem.mem[16'h41] = 16'hA400; // RESTORE_CTX R2

        ; // ---- marker: proves PC redirected to restored LR (0x50) ----
        uut.u_imem.mem[16'h50] = 16'h3CCC; // LDI R6,0xCC

        #12 rst_n = 1;

        ; // ---- data memory preload (AFTER rst_n=1) ----
        uut.u_dmem.mem[8'h05] = 8'hE0;     // pointer to fake "next" context
        uut.u_dmem.mem[8'hE0] = 8'hB1;     // fake R1
        uut.u_dmem.mem[8'hE1] = 8'hB2;     // fake R2
        uut.u_dmem.mem[8'hE2] = 8'hB3;     // fake R3
        uut.u_dmem.mem[8'hE3] = 8'hB4;     // fake R4
        uut.u_dmem.mem[8'hE4] = 8'hB5;     // fake R5
        uut.u_dmem.mem[8'hE5] = 8'hB6;     // fake R6
        uut.u_dmem.mem[8'hE6] = 8'hB7;     // fake R7
        uut.u_dmem.mem[8'hE7] = 8'h50;     // fake LR -> marker @0x50

        // ---- let boot+preamble+GPR-init settle ----
        repeat (30) @(posedge clk); #1;

        // ---- fire the fake interrupt (held several cycles, not a
        //      single-cycle pulse -- see prior bug log re: dropped
        //      interrupts on a memoryless irq_taken) ----
        @(posedge clk); irq_in = 1;
        repeat (5) @(posedge clk);
        irq_in = 0;

        // ---- checkpoint 1: after SAVE burst should have completed ----
        repeat (15) @(posedge clk); #1;

        $display("\n---- after SAVE burst ----");
        check8("R1 saved correctly",  uut.u_dmem.mem[8'hF8], 8'hA1);
        check8("R2 saved correctly",  uut.u_dmem.mem[8'hF9], 8'hA2);
        check8("R3 saved correctly",  uut.u_dmem.mem[8'hFA], 8'hA3);
        check8("R4 saved correctly",  uut.u_dmem.mem[8'hFB], 8'hA4);
        check8("R5 saved correctly",  uut.u_dmem.mem[8'hFC], 8'hA5);
        check8("R6 saved correctly",  uut.u_dmem.mem[8'hFD], 8'hA6);
        check8("R7 saved correctly",  uut.u_dmem.mem[8'hFE], 8'hA7);
        check8("LR (resume_pc) saved correctly",
               uut.u_dmem.mem[8'hFF], captured_resume_pc);
        check8("SP == save_base (0xF8) after SAVE", uut.u_sp.sp_out, 8'hF8);
        check8("PC redirected to TASK_SELECT_VECTOR", pc_after_save_redirect, 8'h40);

        // ---- checkpoint 2: after task-select code + RESTORE burst ----
        // budget covers: LW/RESTORE_CTX fetch+hazard-stall (~5) +
        // RESTORE burst (9) + marker fetch (~5), generous margin
        repeat (45) @(posedge clk); #1;

        $display("\n---- after RESTORE burst + marker ----");
        check8("R1 restored correctly", uut.u_rf.regs[1], 8'hB1);
        check8("R2 restored correctly", uut.u_rf.regs[2], 8'hB2);
        check8("R3 restored correctly", uut.u_rf.regs[3], 8'hB3);
        check8("R4 restored correctly", uut.u_rf.regs[4], 8'hB4);
        check8("R5 restored correctly", uut.u_rf.regs[5], 8'hB5);
        check8("R7 restored correctly", uut.u_rf.regs[7], 8'hB7);
        check8("SP == restore_base+7 (0xE7) after RESTORE", uut.u_sp.sp_out, 8'hE7);
        check8("GIE restored (0x01)", {7'h00, uut.gie_out}, 8'h01);
        // R6 specifically: proves PC really jumped to the restored LR
        // (0x50) and the marker executed -- indirect but solid proof
        // of correct LR restore + redirect, same trick as isr_alone_tb.v
        check8("R6 (post-marker, proves LR restore + PC redirect)",
               uut.u_rf.regs[6], 8'hCC);

        if (errors == 0) $display("\n=== CTX_SWITCH_FSM ISOLATED TEST PASSED ===");
        else              $display("\n=== %0d TEST(S) FAILED ===", errors);
        $finish;
    end

endmodule