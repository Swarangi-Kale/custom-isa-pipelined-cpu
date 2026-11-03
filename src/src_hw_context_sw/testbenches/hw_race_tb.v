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
    
    // ---- exact-increment monitor (counter stores must be prev+1) ----
    reg [7:0] prev [1:3]; integer a, fails;
    initial begin prev[1]=0; prev[2]=0; prev[3]=0; fails=0; end
    always @(posedge clk) if (rst_n && uut.mem_dmem_we && !uut.fsm_active) begin
        a = uut.mem_dmem_addr;
        if (a>=1 && a<=3) begin
            if (uut.mem_rs2_rdata !== prev[a] + 8'd1) begin
                fails = fails + 1;
                $display("SEQ-FAIL @%0t: ctr[%0d] stored %0d, expected %0d",
                         $time, a, uut.mem_rs2_rdata, prev[a]+1);
            end
            prev[a] = uut.mem_rs2_rdata;
        end
    end
    
    // ---- direct detectors for the two suspected bugs ----
    always @(posedge clk) if (rst_n) begin
        if (uut.fsm_active && (uut.mem_dmem_we || uut.mem_dmem_re))
            $display("HIJACK @%0t: MEM-stage op overridden by FSM (we=%b re=%b)",
                     $time, uut.mem_dmem_we, uut.mem_dmem_re);
        if (uut.fsm_save_read_gpr &&
            ((uut.wb_rd_we  && uut.wb_rd_addr  == uut.fsm_gpr_addr) ||
             (uut.mem_rd_we && uut.mem_rd_addr == uut.fsm_gpr_addr)))
            $display("STALE-READ @%0t: R%0d has a pending write", $time, uut.fsm_gpr_addr);
    end
    
    initial begin #200000; $display("TIMEOUT: a fire_at_ex_pc never matched"); $finish; end
    
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
        
        // task order rotates 0,1,2,0,... so each group of three covers all tasks
                // task order rotates 0,1,2,0,... so each group of three covers all tasks
        fire_at_ex_pc(8'h11); fire_at_ex_pc(8'h21); fire_at_ex_pc(8'h31); // ADDI in EX
        fire_at_ex_pc(8'h12); fire_at_ex_pc(8'h22); fire_at_ex_pc(8'h32); // SW   in EX
        fire_when_lw_in_mem; fire_when_lw_in_mem; fire_when_lw_in_mem;
        fire_at_ex_pc(8'h13); fire_at_ex_pc(8'h23); fire_at_ex_pc(8'h33); // JMP  in EX

        $display("SEQ fails = %0d", fails);
        $display("cur_id=%0d (exp 0)  tcb: %02h %02h %02h (exp F8 EF E6)",
                 uut.u_dmem.mem[0], uut.u_dmem.mem[4], uut.u_dmem.mem[5], uut.u_dmem.mem[6]);
        $finish;
    end
    
    task fire_when_lw_in_mem;
        begin
            @(negedge clk);
            while (!(uut.mem_dmem_re && uut.mem_rd_addr == 3'd1 &&
                     !uut.hdu_stall && uut.gie_out && !uut.fsm_active))
                @(negedge clk);
            $display("=== FIRE @ LW R1 in MEM  t=%0t", $time);
            irq_in = 1; @(negedge clk); irq_in = 0;
            repeat (100) @(posedge clk);
        end
    endtask
        
        // ---- fire irq exactly when a chosen PC is in EX ----
    task fire_at_ex_pc(input [7:0] pc);
        begin
            @(negedge clk);
            while (!(uut.ex_pc==pc && !uut.hdu_stall && uut.gie_out && !uut.fsm_active))
                @(negedge clk);
            $display("=== FIRE @ ex_pc=%h  t=%0t", pc, $time);
            irq_in = 1; @(negedge clk); irq_in = 0;
            repeat (100) @(posedge clk);
        end
    endtask




endmodule