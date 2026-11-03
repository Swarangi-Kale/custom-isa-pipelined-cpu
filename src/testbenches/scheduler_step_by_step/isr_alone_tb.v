`timescale 1ns/1ps
// -----------------------------------------------------------------------
// isr_alone_tb.v
// Tests the context-switch ISR in isolation -- no real task loops.
//
// Strategy:
//   - A tiny preamble sets task0's live SP to a known value (0xFF).
//   - data_memory is pre-loaded so task1 already looks like it has a
//     previously-saved context sitting at a known SP (0xF0..0xF7),
//     including a FAKE saved LR (0xF7 slot) that points at a "marker"
//     instruction (LDI R6,0xAB) placed at instruction address 0x08.
//   - irq_in is pulsed for exactly one cycle.
//   - If save->switch->restore->RETI all work, execution resumes at
//     the marker and overwrites R6 with 0xAB -- proving the whole
//     chain end-to-end without needing to know the PC signal's path.
//
// Program layout:
//   0x00  LDI R7,0xFF        -> 3EFF   set up scratch
//   0x01  MOV SP,R7          -> CE03   task0's live SP = 0xFF
//   0x02-0x07                 (default NOP / "task0 running")
//   0x08  LDI R6,0xAB        -> 3CAB   marker instr (resume target)
//   0x40-0x6F                 ISR (context_switch, from isr_context_switch.asm)
//
// Data memory preload:
//   0x00  current_task_id = 0x00
//   0x05  tcb1 = 0xF0                  (task1's fake saved SP)
//   0xF0..0xF6  fake saved R1-R7 for task1 = 0x11,0x22,0x33,0x44,0x55,0x66,0x77
//   0xF7  fake saved LR for task1 = 0x08 (-> marker instr above)
//
// ASSUMPTIONS (verify against your files -- same style as sp_roundtrip_tb.v):
//   - uut.u_imem.mem[addr]  is instr_mem's array
//   - uut.u_dmem.mem[addr]  is data_memory's array
//   - uut.u_rf.regs[n]      is reg_bank's array
//   - uut.u_sp.sp_out       is sp_unit's raw SP value
//   - GIE resets to 0 by design (see gie_reg.v) and is ONLY ever set
//     by executing RETI -- so a tiny "boot stub" (LDI->MOV LR->RETI,
//     same idiom as irq_entry_tb.v's boot_to() task) runs first purely
//     to arm GIE=1 and jump into the real preamble below
//   - LR's hierarchical path is UNKNOWN to me -- fill in
//     uut.<your_lr_path> below before relying on the LR check

// -----------------------------------------------------------------------
// BUGS FOUND DURING BRING-UP (kept as a running log, same spirit as
// sp_roundtrip_tb.v's "bugs faced" line):
// 1. GIE resets to 0 by design (gie_reg.v) and RETI is the only thing
//    that sets it - a boot-stub RETI is required before any real
//    irq_in pulse will ever be taken. Not a bug, just easy to forget.
// 2. Data memory preload (uut.u_dmem.mem[...]) was getting silently
//    wiped: data_memory.v clears its whole array on every posedge clk
//    while rst_n is low, and clk starts toggling before rst_n=1 is
//    applied. Preload must happen AFTER rst_n=1, not before.
// 3. Real HDU bug (in hazard_detection_unit.v, not this TB): its
//    uses_rs1 list omitted OP_MOVLR, so LW immediately followed by
//    MOV SP,Rd / MOV LR,Rd (write direction) never stalled. Forwarding
//    fell back to its "never actually selected" EX/MEM alu_result
//    path, handing SP the load's ADDRESS instead of its DATA (e.g.
//    LW R2,0x05(R0); MOV SP,R2 gave SP=0x05 instead of mem[0x05]).
//    Fix: gate on funct[0] (write direction only - read direction has
//    no real rs1 to hazard-check) and add OP_MOVLR to uses_rs1 when
//    funct[0]=1. Needed a new id_funct input on hazard_detection_unit,
//    wired from processor_pipel_haz.v's existing id_funct signal.
// 4. Default xsim simulation runtime (Settings -> xsim.simulate.runtime,
//    often 1000ns) elapses before a longer test's $finish is reached -
//    sim just pauses, log looks empty. Not a TB/RTL bug - "run -all"
//    (or raising that setting) runs to actual completion.
// -----------------------------------------------------------------------
module isr_alone_tb;

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

    initial begin
        clk = 0; rst_n = 0; irq_in = 0;

        for (i = 0; i < 256; i = i + 1) uut.u_imem.mem[i] = 16'h0000;
        for (i = 0; i < 256; i = i + 1) uut.u_dmem.mem[i] = 8'h00;

         // ---- boot stub: GIE resets to 0, and RETI is the only thing
         //     that sets it -- so run one "fake" RETI purely to arm GIE=1
         //     and jump into the real preamble (same idiom irq_entry_tb.v
         //     uses in its boot_to() task) ----
        uut.u_imem.mem[16'h00] = 16'h3E03; // LDI  R7,0x03      target = preamble below
        uut.u_imem.mem[16'h01] = 16'hCE01; // MOV  LR,R7
        uut.u_imem.mem[16'h02] = 16'h7000; // RETI              -> GIE=1, jump to 0x03

         // ---- preamble: give task0 a known live SP ----
        uut.u_imem.mem[16'h03] = 16'h3EFF; // LDI  R7,0xFF
        uut.u_imem.mem[16'h04] = 16'hCE03; // MOV  SP,R7

         // ---- resume marker (fake LR target for the incoming task) ----
        uut.u_imem.mem[16'h08] = 16'h3CAB; // LDI  R6,0xAB

         // ---- ISR: isr_context_switch, placed at ISR_VECTOR = 0x40 ----
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
        uut.u_imem.mem[16'h50] = 16'h2206; // SW R1,0x06(R0)   (task_id==2 fallthrough)
        uut.u_imem.mem[16'h51] = 16'h6055; // JMP 0x55
        uut.u_imem.mem[16'h52] = 16'h2204; // SW R1,0x04(R0)   (save_task0)
        uut.u_imem.mem[16'h53] = 16'h6055; // JMP 0x55
        uut.u_imem.mem[16'h54] = 16'h2205; // SW R1,0x05(R0)   (save_task1)
        uut.u_imem.mem[16'h55] = 16'hB601; // ADDI R3,#1
        uut.u_imem.mem[16'h56] = 16'h3803; // LDI R4,#3
        uut.u_imem.mem[16'h57] = 16'h58C2; // BEQ R3,R4,+2 -> 0x59
        uut.u_imem.mem[16'h58] = 16'h605A; // JMP 0x5A
        uut.u_imem.mem[16'h59] = 16'h3600; // LDI R3,#0        (wrap_to_zero)
        uut.u_imem.mem[16'h5A] = 16'h2600; // SW R3,0x00(R0)   (store_new_id)
        uut.u_imem.mem[16'h5B] = 16'h3800; // LDI R4,#0
        uut.u_imem.mem[16'h5C] = 16'h58C5; // BEQ R3,R4,+5 -> 0x61
        uut.u_imem.mem[16'h5D] = 16'h3801; // LDI R4,#1
        uut.u_imem.mem[16'h5E] = 16'h58C5; // BEQ R3,R4,+5 -> 0x63
        uut.u_imem.mem[16'h5F] = 16'h1406; // LW R2,0x06(R0)   (new_id==2 fallthrough)
        uut.u_imem.mem[16'h60] = 16'h6064; // JMP 0x64
        uut.u_imem.mem[16'h61] = 16'h1404; // LW R2,0x04(R0)   (load_task0)
        uut.u_imem.mem[16'h62] = 16'h6064; // JMP 0x64
        uut.u_imem.mem[16'h63] = 16'h1405; // LW R2,0x05(R0)   (load_task1)
        uut.u_imem.mem[16'h64] = 16'hC403; // MOV SP,R2
        uut.u_imem.mem[16'h65] = 16'h9300; // LOADSP R1,#0
        uut.u_imem.mem[16'h66] = 16'h9501; // LOADSP R2,#1
        uut.u_imem.mem[16'h67] = 16'h9702; // LOADSP R3,#2
        uut.u_imem.mem[16'h68] = 16'h9903; // LOADSP R4,#3
        uut.u_imem.mem[16'h69] = 16'h9B04; // LOADSP R5,#4
        uut.u_imem.mem[16'h6A] = 16'h9D05; // LOADSP R6,#5
        uut.u_imem.mem[16'h6B] = 16'h9F07; // LOADSP R7,#7    (saved LR scratch)
        uut.u_imem.mem[16'h6C] = 16'hCE01; // MOV LR,R7
        uut.u_imem.mem[16'h6D] = 16'h9F06; // LOADSP R7,#6    (R7's real value)
        uut.u_imem.mem[16'h6E] = 16'h8007; // ADDSP #+7
        uut.u_imem.mem[16'h6F] = 16'h7000; // RETI

        #12 rst_n = 1;

         // ---- data memory preload ----
         // MUST come after rst_n=1: data_memory.v's synchronous reset
         //     clears the WHOLE array on every posedge clk while rst_n is
         //     low, and clk starts toggling at t=0 (first posedge at 5ns,
         //     well before rst_n=1 at 12ns) -- preloading before this
         //     point gets silently wiped by that edge before the test
         //     even starts. Preload here (t=12ns, before the NEXT posedge
         //     at 15ns) so it survives.
        uut.u_dmem.mem[8'h00] = 8'h00;     // current_task_id = 0
        uut.u_dmem.mem[8'h05] = 8'hF0;     // tcb1 = 0xF0 (task1's fake saved SP)
        uut.u_dmem.mem[8'hF0] = 8'h11;     // fake saved R1
        uut.u_dmem.mem[8'hF1] = 8'h22;     // fake saved R2
        uut.u_dmem.mem[8'hF2] = 8'h33;     // fake saved R3
        uut.u_dmem.mem[8'hF3] = 8'h44;     // fake saved R4
        uut.u_dmem.mem[8'hF4] = 8'h55;     // fake saved R5
        uut.u_dmem.mem[8'hF5] = 8'h66;     // fake saved R6
        uut.u_dmem.mem[8'hF6] = 8'h77;     // fake saved R7
        uut.u_dmem.mem[8'hF7] = 8'h08;     // fake saved LR -> marker instr @0x08

        // let the boot stub (3 instrs, incl. a RETI) + preamble (2 instrs)
        // finish and capture the live SP, same "capture, don't assume"
        // approach as sp_roundtrip_tb -- widened from the original 15
        // cycles to cover the extra boot-stub instructions
        repeat (20) @(posedge clk); #1;
        sp_task0_live = uut.u_sp.sp_out;
        $display("INFO: task0 live SP before interrupt = 0x%02h", sp_task0_live);

        // single-cycle irq pulse
        @(posedge clk); irq_in = 1;
        @(posedge clk); irq_in = 0;

        // generous window for the full ISR (branches + stalls) plus a
        // few extra cycles for the post-RETI marker instruction to
        // reach WB -- TUNE THIS once you see real waveforms
        repeat (80) @(posedge clk); #1;

        // ---- checks ----
        check8("tcb0 = outgoing SP - 7",  uut.u_dmem.mem[8'h04], sp_task0_live - 8'd7);
        check8("current_task_id -> 1",    uut.u_dmem.mem[8'h00], 8'h01);
        check8("R1 restored",             uut.u_rf.regs[1], 8'h11);
        check8("R2 restored",             uut.u_rf.regs[2], 8'h22);
        check8("R3 restored",             uut.u_rf.regs[3], 8'h33);
        check8("R4 restored",             uut.u_rf.regs[4], 8'h44);
        check8("R5 restored",             uut.u_rf.regs[5], 8'h55);
        check8("R7 restored",             uut.u_rf.regs[7], 8'h77);
        check8("SP after ADDSP+7 (raw)",  uut.u_sp.sp_out,  8'hF7);
        // proves RETI actually jumped to the restored LR (0x08) and the
        // marker instruction executed -- indirect but solid confirmation
        check8("R6 (post-marker, proves RETI->LR jump)", uut.u_rf.regs[6], 8'hAB);

        // LR check -- UNCOMMENT once you know the hierarchical path:
        // check8("LR restored", uut.u_lr.lr_out, 8'h08);

        if (errors == 0) $display("\n=== ISR-ALONE TEST PASSED ===");
        else              $display("\n=== %0d TEST(S) FAILED ===", errors);
        $finish;
    end

endmodule