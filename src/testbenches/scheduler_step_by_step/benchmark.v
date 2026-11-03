`timescale 1ns/1ps
// -----------------------------------------------------------------------
// isr_cycle_benchmark_tb.v
// Closes out Phase C's last deliverable and opens Phase D: the baseline
// software-ISR cycle count for save+restore, measured from irq_in
// assertion (and separately from irq_taken) to the new task's first
// instruction.
//
// Reuses the exact proven task0/1/2 loop + ISR setup from
// isr_task_loops_tb.v (same encodings, same memory map) -- built as a
// separate file so this instrumentation never risks the correctness
// regression test.
//
// MEASUREMENT METHOD AND ITS LIMITATION (read before trusting the
// numbers): the pipeline does not thread PC past EX (ex_pc is the last
// PC signal -- no mem_pc/wb_pc exists), so "first retired instruction"
// cannot be observed directly. Instead: capture the cycle the new
// task's first instruction is FETCHED (1 cycle after its RETI resolves
// in EX -- this part IS directly observed, same detection already
// validated this session), then add a FIXED +4 cycles (ID->EX->MEM->WB)
// as the architecturally-known drain to retirement. This is only exact
// if that specific first instruction hits no hazard stall of its own --
// spot-check against a real waveform before citing these numbers,
// don't take them as ground truth from this file alone.
//
// Two latencies reported per switch:
//   - from irq_in assertion  -- includes whatever stall-deferral
//     latency happened to occur before irq_taken fired; depends on
//     testbench stimulus timing (how long irq_in is held, where in the
//     loop it happened to land), NOT a pure property of the ISR itself
//   - from irq_taken (actual acceptance) -- the fairer number to carry
//     into the Phase D FSM/banked comparison, since it isolates the
//     mechanism's own latency from stimulus-dependent deferral
//
// PREREQUISITES: both hazard/dmem_re fixes from earlier bring-up must
// be in place (see isr_task_loops_tb.v's bug log).
// -----------------------------------------------------------------------
module benchmark_tb;

    reg clk, rst_n, irq_in;
    integer i;

    processor_pipel_haz uut (
        .clk    (clk),
        .rst_n  (rst_n),
        .irq_in (irq_in)
    );

    always #5 clk = ~clk;

    // ---- capture: cycle (as $time) each irq_taken fires, indexed 0..2 ----
    reg [63:0] t_irq_taken [0:2];
    integer    irq_taken_count;
    always @(posedge clk) begin
        if (rst_n && uut.irq_taken) begin
            t_irq_taken[irq_taken_count] <= $time;
            irq_taken_count <= irq_taken_count + 1;
        end
    end

    // ---- capture: cycle (as $time) each real RETI resolves, indexed 0..3 ----
    // (index 0 = boot-stub RETI, not a real switch; 1,2,3 = the three
    // real ISR-ending RETIs -- same gating as isr_full_cycle_tb.v's fix,
    // ex_br_type alone doesn't distinguish RETI from JMP)
    reg [63:0] t_reti [0:3];
    integer    reti_count;
    always @(posedge clk) begin
        if (rst_n && uut.ex_pc_redirect && uut.ex_br_type == 2'b11
                   && uut.ex_pc_target_sel == 2'b10) begin
            t_reti[reti_count] <= $time;
            reti_count <= reti_count + 1;
        end
    end

    reg [63:0] t_irq_in_assert [1:3];

    initial begin
        clk = 0; rst_n = 0; irq_in = 0;
        irq_taken_count = 0; reti_count = 0;

        for (i = 0; i < 256; i = i + 1) uut.u_imem.mem[i] = 16'h0000;

         // ---- boot stub ----
        uut.u_imem.mem[16'h00] = 16'h3E03; // LDI  R7,0x03
        uut.u_imem.mem[16'h01] = 16'hCE01; // MOV  LR,R7
        uut.u_imem.mem[16'h02] = 16'h7000; // RETI

        // ---- task0 preamble ----
        uut.u_imem.mem[16'h03] = 16'h3EFF; // LDI  R7,0xFF
        uut.u_imem.mem[16'h04] = 16'hCE03; // MOV  SP,R7
        uut.u_imem.mem[16'h05] = 16'h6010; // JMP  0x10

        // ---- task0 loop: counter @0x01 ----
        uut.u_imem.mem[16'h10] = 16'h1201; // LW   R1,0x01(R0)
        uut.u_imem.mem[16'h11] = 16'hB201; // ADDI R1,#1
        uut.u_imem.mem[16'h12] = 16'h2201; // SW   R1,0x01(R0)
        uut.u_imem.mem[16'h13] = 16'h6010; // JMP  0x10

        // ---- task1 loop: counter @0x02 ----
        uut.u_imem.mem[16'h20] = 16'h1202; // LW   R1,0x02(R0)
        uut.u_imem.mem[16'h21] = 16'hB201; // ADDI R1,#1
        uut.u_imem.mem[16'h22] = 16'h2202; // SW   R1,0x02(R0)
        uut.u_imem.mem[16'h23] = 16'h6020; // JMP  0x20

        // ---- task2 loop: counter @0x03 ----
        uut.u_imem.mem[16'h30] = 16'h1203; // LW   R1,0x03(R0)
        uut.u_imem.mem[16'h31] = 16'hB201; // ADDI R1,#1
        uut.u_imem.mem[16'h32] = 16'h2203; // SW   R1,0x03(R0)
        uut.u_imem.mem[16'h33] = 16'h6030; // JMP  0x30

        // ---- ISR: isr_context_switch, at ISR_VECTOR = 0x40 ----
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
//        uut.u_imem.mem[16'h4A] = 16'hC202; // MOV R1,SP
//        uut.u_imem.mem[16'h4B] = 16'h1600; // LW R3,0x00(R0)
//        uut.u_imem.mem[16'h4C] = 16'h3800; // LDI R4,#0
//        uut.u_imem.mem[16'h4D] = 16'h58C5; // BEQ R3,R4,+5 -> 0x52
//        uut.u_imem.mem[16'h4E] = 16'h3801; // LDI R4,#1
//        uut.u_imem.mem[16'h4F] = 16'h58C5; // BEQ R3,R4,+5 -> 0x54
//        uut.u_imem.mem[16'h50] = 16'h2206; // SW R1,0x06(R0)
//        uut.u_imem.mem[16'h51] = 16'h6055; // JMP 0x55
//        uut.u_imem.mem[16'h52] = 16'h2204; // SW R1,0x04(R0)
//        uut.u_imem.mem[16'h53] = 16'h6055; // JMP 0x55
//        uut.u_imem.mem[16'h54] = 16'h2205; // SW R1,0x05(R0)
//        uut.u_imem.mem[16'h55] = 16'hB601; // ADDI R3,#1
//        uut.u_imem.mem[16'h56] = 16'h3803; // LDI R4,#3
//        uut.u_imem.mem[16'h57] = 16'h58C2; // BEQ R3,R4,+2 -> 0x59
//        uut.u_imem.mem[16'h58] = 16'h605A; // JMP 0x5A
//        uut.u_imem.mem[16'h59] = 16'h3600; // LDI R3,#0
//        uut.u_imem.mem[16'h5A] = 16'h2600; // SW R3,0x00(R0)
//        uut.u_imem.mem[16'h5B] = 16'h3800; // LDI R4,#0
//        uut.u_imem.mem[16'h5C] = 16'h58C5; // BEQ R3,R4,+5 -> 0x61
//        uut.u_imem.mem[16'h5D] = 16'h3801; // LDI R4,#1
//        uut.u_imem.mem[16'h5E] = 16'h58C5; // BEQ R3,R4,+5 -> 0x63
//        uut.u_imem.mem[16'h5F] = 16'h1406; // LW R2,0x06(R0)
//        uut.u_imem.mem[16'h60] = 16'h6064; // JMP 0x64
//        uut.u_imem.mem[16'h61] = 16'h1404; // LW R2,0x04(R0)
//        uut.u_imem.mem[16'h62] = 16'h6064; // JMP 0x64
//        uut.u_imem.mem[16'h63] = 16'h1405; // LW R2,0x05(R0)
//        uut.u_imem.mem[16'h64] = 16'hC403; // MOV SP,R2
//        uut.u_imem.mem[16'h65] = 16'h9300; // LOADSP R1,#0
//        uut.u_imem.mem[16'h66] = 16'h9501; // LOADSP R2,#1
//        uut.u_imem.mem[16'h67] = 16'h9702; // LOADSP R3,#2
//        uut.u_imem.mem[16'h68] = 16'h9903; // LOADSP R4,#3
//        uut.u_imem.mem[16'h69] = 16'h9B04; // LOADSP R5,#4
//        uut.u_imem.mem[16'h6A] = 16'h9D05; // LOADSP R6,#5
//        uut.u_imem.mem[16'h6B] = 16'h9F07; // LOADSP R7,#7
//        uut.u_imem.mem[16'h6C] = 16'hCE01; // MOV LR,R7
//        uut.u_imem.mem[16'h6D] = 16'h9F06; // LOADSP R7,#6
//        uut.u_imem.mem[16'h6E] = 16'h8007; // ADDSP #+7
//        uut.u_imem.mem[16'h6F] = 16'h7000; // RETI
        uut.u_imem.mem[16'h4A] = 16'h1400; // LW R2,0(R0)
        uut.u_imem.mem[16'h4B] = 16'hC202; // MOV R1,SP
        uut.u_imem.mem[16'h4C] = 16'h2284; // SW R1,4(R2)
        uut.u_imem.mem[16'h4D] = 16'h1487; // LW R2,7(R2)
        uut.u_imem.mem[16'h4E] = 16'h1284; // LW R1,4(R2)
        uut.u_imem.mem[16'h4F] = 16'h2400; // SW R2,0(R0)
        uut.u_imem.mem[16'h50] = 16'hC203; // MOV SP,R1   (replaces RESTORE_CTX)
        uut.u_imem.mem[16'h51] = 16'h9300; // LOADSP R1,#0
        uut.u_imem.mem[16'h52] = 16'h9501; // LOADSP R2,#1
        uut.u_imem.mem[16'h53] = 16'h9702; // LOADSP R3,#2
        uut.u_imem.mem[16'h54] = 16'h9903; // LOADSP R4,#3
        uut.u_imem.mem[16'h55] = 16'h9B04; // LOADSP R5,#4
        uut.u_imem.mem[16'h56] = 16'h9D05; // LOADSP R6,#5
        uut.u_imem.mem[16'h57] = 16'h9F07; // LOADSP R7,#7
        uut.u_imem.mem[16'h58] = 16'hCE01; // MOV LR,R7
        uut.u_imem.mem[16'h59] = 16'h9F06; // LOADSP R7,#6
        uut.u_imem.mem[16'h5A] = 16'h8007; // ADDSP #+7
        uut.u_imem.mem[16'h5B] = 16'h7000; // RETI
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
        report_latency(1, t_irq_in_assert[1], t_irq_taken[0], t_reti[1]);
        report_latency(2, t_irq_in_assert[2], t_irq_taken[1], t_reti[2]);
        report_latency(3, t_irq_in_assert[3], t_irq_taken[2], t_reti[3]);

        $display("\nINFO: worst-case (max) latency from irq_taken across the 3 branches");
        $display("      is the number to carry into the Phase D comparison table,");
        $display("      since it upper-bounds software-ISR scheduling latency.");

        $finish;
    end

    // reti_time is when the switch's RETI resolves in EX; the new task's
    // first instruction is fetched 1 cycle later, and (estimated, see
    // header) retires 4 cycles after that.
//    task report_latency(input integer n, input [63:0] irqin_t,
//                         input [63:0] taken_t, input [63:0] reti_t);
//        reg [63:0] fetch_t, est_retire_t;
//        integer    cyc_from_irqin, cyc_from_taken;
//        begin
//            fetch_t       = reti_t + 10;
//            est_retire_t  = fetch_t + 40;  // +4 cycles * 10ns
//            cyc_from_irqin = (est_retire_t - irqin_t) / 10;
//            cyc_from_taken = (est_retire_t - taken_t) / 10;
//            $display("\n---- switch %0d ----", n);
//            $display("  irq_in asserted @ %0t, irq_taken @ %0t, RETI resolved @ %0t",
//                      irqin_t, taken_t, reti_t);
//            $display("  estimated new-task retire @ %0t", est_retire_t);
//            $display("  latency from irq_in assertion : %0d cycles", cyc_from_irqin);
//            $display("  latency from irq_taken (fairer for Phase D): %0d cycles", cyc_from_taken);
//        end
//    endtask

    // changed latency measurement metric:
    task report_latency(input integer n, input [63:0] irqin_t,
                         input [63:0] taken_t, input [63:0] reti_t);
        reg [63:0] fetch_t;
        integer    cyc_from_irqin, cyc_from_taken;
        begin
            fetch_t        = reti_t + 10;                 // 1 cycle after RETI resolves in EX
            cyc_from_irqin = (fetch_t - irqin_t) / 10;
            cyc_from_taken = (fetch_t - taken_t) / 10;
            $display("\n---- switch %0d ----", n);
            $display("  irq_in asserted @ %0t, irq_taken @ %0t, RETI resolved @ %0t",
                      irqin_t, taken_t, reti_t);
            $display("  new-task instruction fetched @ %0t", fetch_t);
            $display("  latency from irq_in assertion : %0d cycles", cyc_from_irqin);
            $display("  latency from irq_taken (Phase D metric): %0d cycles", cyc_from_taken);
        end
    endtask    

endmodule