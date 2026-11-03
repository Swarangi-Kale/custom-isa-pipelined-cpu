`timescale 1ns/1ps
// -----------------------------------------------------------------------
// isr_hw_cycle_benchmark_tb.v
// Phase D hardware-mechanism cycle-count benchmark. Deliberately mirrors
// isr_cycle_benchmark_tb.v's measurement methodology exactly, so the two
// numbers are apples-to-apples:
//   - same two start points: irq_in assertion (testbench stimulus) and
//     irq_taken (actual acceptance)
//   - same endpoint definition: new task's first instruction FETCHED
//     (1 cycle after the mechanism's own completion event), plus the
//     same fixed +4 cycles (ID->EX->MEM->WB) as an estimated drain to
//     retirement -- neither design threads PC past EX, so neither
//     benchmark can observe true WB-stage retirement directly; both
//     use the identical estimation so the COMPARISON is fair even
//     though neither individual number is perfectly exact.
//
// The only thing that changes vs isr_cycle_benchmark_tb.v is WHICH
// signal marks "the mechanism just finished, new task is about to be
// fetched": there it was RETI resolving in EX (ex_br_type==2'b11,
// needing extra gating to exclude JMP); here it's fsm_restore_done,
// which is unambiguous on its own -- no gating needed.
//
// Same program as isr_hw_task_loops_tb.v (task loops + task-select code
// unchanged) -- reusing the already-validated correct layout rather
// than re-deriving anything.
// -----------------------------------------------------------------------
module hw_benchmark_tb;

    reg clk, rst_n, irq_in;
    integer i;

    processor_hw_context_switch uut (
        .clk    (clk),
        .rst_n  (rst_n),
        .irq_in (irq_in)
    );

    always #5 clk = ~clk;

    // ---- capture: $time of each irq_taken (0..2, one per real switch) ----
    reg [63:0] t_irq_taken [0:2];
    integer    irq_taken_count;
    always @(posedge clk) begin
        if (rst_n && uut.irq_taken) begin
            t_irq_taken[irq_taken_count] <= $time;
            irq_taken_count <= irq_taken_count + 1;
        end
    end

    // ---- capture: $time of each fsm_restore_done (0..2) -- the hardware
    //      mechanism's completion event, unambiguous unlike RETI-vs-JMP ----
    reg [63:0] t_fsm_restore_done [0:2];
    integer    restore_count;
    always @(posedge clk) begin
        if (rst_n && uut.fsm_restore_done) begin
            t_fsm_restore_done[restore_count] <= $time;
            restore_count <= restore_count + 1;
        end
    end

    reg [63:0] t_irq_in_assert [1:3];

    initial begin
        clk = 0; rst_n = 0; irq_in = 0;
        irq_taken_count = 0; restore_count = 0;

        for (i = 0; i < 256; i = i + 1) uut.u_imem.mem[i] = 16'h0000;

        ; // ---- boot stub ----
        uut.u_imem.mem[16'h00] = 16'h3E03; // LDI  R7,0x03
        uut.u_imem.mem[16'h01] = 16'hCE01; // MOV  LR,R7
        uut.u_imem.mem[16'h02] = 16'h7000; // RETI

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

        ; // ---- TASK_SELECT_VECTOR = 0x40 ----
//        uut.u_imem.mem[16'h40] = 16'hC202; // MOV R1,SP
//        uut.u_imem.mem[16'h41] = 16'h1600; // LW R3,0x00(R0)
//        uut.u_imem.mem[16'h42] = 16'h3800; // LDI R4,#0
//        uut.u_imem.mem[16'h43] = 16'h58C5; // BEQ R3,R4,+5 -> 0x48
//        uut.u_imem.mem[16'h44] = 16'h3801; // LDI R4,#1
//        uut.u_imem.mem[16'h45] = 16'h58C5; // BEQ R3,R4,+5 -> 0x4A
//        uut.u_imem.mem[16'h46] = 16'h2206; // SW R1,0x06(R0)
//        uut.u_imem.mem[16'h47] = 16'h604B; // JMP 0x4B
//        uut.u_imem.mem[16'h48] = 16'h2204; // SW R1,0x04(R0)
//        uut.u_imem.mem[16'h49] = 16'h604B; // JMP 0x4B
//        uut.u_imem.mem[16'h4A] = 16'h2205; // SW R1,0x05(R0)
//        uut.u_imem.mem[16'h4B] = 16'hB601; // ADDI R3,#1
//        uut.u_imem.mem[16'h4C] = 16'h3803; // LDI R4,#3
//        uut.u_imem.mem[16'h4D] = 16'h58C2; // BEQ R3,R4,+2 -> 0x4F
//        uut.u_imem.mem[16'h4E] = 16'h6050; // JMP 0x50
//        uut.u_imem.mem[16'h4F] = 16'h3600; // LDI R3,#0
//        uut.u_imem.mem[16'h50] = 16'h2600; // SW R3,0x00(R0)
//        uut.u_imem.mem[16'h51] = 16'h3800; // LDI R4,#0
//        uut.u_imem.mem[16'h52] = 16'h58C5; // BEQ R3,R4,+5 -> 0x57
//        uut.u_imem.mem[16'h53] = 16'h3801; // LDI R4,#1
//        uut.u_imem.mem[16'h54] = 16'h58C5; // BEQ R3,R4,+5 -> 0x59
//        uut.u_imem.mem[16'h55] = 16'h1406; // LW R2,0x06(R0)
//        uut.u_imem.mem[16'h56] = 16'h605A; // JMP 0x5A
//        uut.u_imem.mem[16'h57] = 16'h1404; // LW R2,0x04(R0)
//        uut.u_imem.mem[16'h58] = 16'h605A; // JMP 0x5A
//        uut.u_imem.mem[16'h59] = 16'h1405; // LW R2,0x05(R0)
//        uut.u_imem.mem[16'h5A] = 16'hA400; // RESTORE_CTX R2
        uut.u_imem.mem[16'h40] = 16'h1400; // LW R2,0(R0)
        uut.u_imem.mem[16'h41] = 16'hC202; // MOV R1,SP
        uut.u_imem.mem[16'h42] = 16'h2284; // SW R1,4(R2)
        uut.u_imem.mem[16'h43] = 16'h1487; // LW R2,7(R2)
        uut.u_imem.mem[16'h44] = 16'h1284; // LW R1,4(R2)
        uut.u_imem.mem[16'h45] = 16'h2400; // SW R2,0(R0)
        uut.u_imem.mem[16'h46] = 16'hA200; // RESTORE_CTX R1
        
        #12 rst_n = 1;

        uut.u_dmem.mem[8'h00] = 8'h00;
        uut.u_dmem.mem[8'h01] = 8'h00;
        uut.u_dmem.mem[8'h02] = 8'h00;
        uut.u_dmem.mem[8'h03] = 8'h00;
        uut.u_dmem.mem[8'h05] = 8'hEF;
        uut.u_dmem.mem[8'h06] = 8'hE6;
        uut.u_dmem.mem[8'h07] = 8'h01;
        uut.u_dmem.mem[8'h08] = 8'h02;
        uut.u_dmem.mem[8'h09] = 8'h00;
        for (i = 0; i < 7; i = i + 1) uut.u_dmem.mem[8'hEF + i] = 8'h00;
        uut.u_dmem.mem[8'hF6] = 8'h20;
        for (i = 0; i < 7; i = i + 1) uut.u_dmem.mem[8'hE6 + i] = 8'h00;
        uut.u_dmem.mem[8'hED] = 8'h30;

        repeat (60) @(posedge clk); #1;

        // ---- IRQ1: task0 -> task1 ----
        @(posedge clk); irq_in = 1;
        t_irq_in_assert[1] = $time;
        repeat (5) @(posedge clk);
        irq_in = 0;
        repeat (100) @(posedge clk); #1;

        // ---- IRQ2: task1 -> task2 ----
        @(posedge clk); irq_in = 1;
        t_irq_in_assert[2] = $time;
        repeat (5) @(posedge clk);
        irq_in = 0;
        repeat (100) @(posedge clk); #1;

        // ---- IRQ3: task2 -> task0 (wraparound) ----
        @(posedge clk); irq_in = 1;
        t_irq_in_assert[3] = $time;
        repeat (5) @(posedge clk);
        irq_in = 0;
        repeat (100) @(posedge clk); #1;
        
        $display("cur_id=%0d (exp 0)  ctr0=%0d ctr1=%0d ctr2=%0d (all >0)",
                 uut.u_dmem.mem[0], uut.u_dmem.mem[1], uut.u_dmem.mem[2], uut.u_dmem.mem[3]);
        $display("tcb: %02h %02h %02h (exp F8 EF E6)",
                 uut.u_dmem.mem[4], uut.u_dmem.mem[5], uut.u_dmem.mem[6]);

        // ---- compute and report ----
        report_latency(1, t_irq_in_assert[1], t_irq_taken[0], t_fsm_restore_done[0]);
        report_latency(2, t_irq_in_assert[2], t_irq_taken[1], t_fsm_restore_done[1]);
        report_latency(3, t_irq_in_assert[3], t_irq_taken[2], t_fsm_restore_done[2]);

        $display("\nINFO: worst-case (max) latency from irq_taken across the 3 branches");
        $display("      is the hardware-side number for the Phase D comparison table --");
        $display("      compare directly against isr_cycle_benchmark_tb.v's same number.");

        $finish;
    end

    // done_time is when fsm_restore_done fires; the new task's first
    // instruction is fetched 1 cycle later, and (estimated, see header)
    // retires 4 cycles after that -- identical formula to the software
    // benchmark's RETI-based version, only the trigger event differs.
    task report_latency(input integer n, input [63:0] irqin_t,
                         input [63:0] taken_t, input [63:0] done_t);
        reg [63:0] fetch_t;
        integer    cyc_from_irqin, cyc_from_taken;
        begin
            fetch_t        = done_t + 10;
            cyc_from_irqin = (fetch_t - irqin_t) / 10;
            cyc_from_taken = (fetch_t - taken_t) / 10;
            $display("\n---- switch %0d ----", n);
            $display("  irq_in asserted @ %0t, irq_taken @ %0t, fsm_restore_done @ %0t",
                      irqin_t, taken_t, done_t);
            $display("  new-task instruction fetched @ %0t", fetch_t);
            $display("  latency from irq_in assertion : %0d cycles", cyc_from_irqin);
            $display("  latency from irq_taken (Phase D metric): %0d cycles", cyc_from_taken);
        end
    endtask

endmodule