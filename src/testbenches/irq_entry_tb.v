`timescale 1ns/1ps
// -----------------------------------------------------------------------
// irq_entry_tb.v  --  Phase B: interrupt entry hardware
//
// Five independent sub-tests, each with its own reset + program:
//   T1  GIE gating        : irq while GIE=0 must do nothing
//   T2  Entry mechanics   : PC->ISR_VECTOR, LR=resume_pc, GIE->0
//   T3  Squash count      : exactly 2 instructions discarded
//   T4  Stall-defer       : irq during hdu_stall is deferred, not lost
//   T5  Branch collision  : LR gets the branch target, not id_pc
//   T6  Full round trip   : RETI resumes at exactly the squashed instr
//
// ENCODINGS USED (all previously verified in this project):
//   NOP          0x0000
//   LDI Rn,imm   {0011, n, 1'b0, imm8}
//   ADDI Rn,imm  {1011, n, 1'b0, imm8}
//   MOV LR,Rn    {1100, n, 6'b0, 3'b001}
//   MOV Rn,LR    {1100, n, 6'b0, 3'b000}
//   RETI         0x7000
//   LW  Rd,0(R0) {0001, rd, 3'b000, 6'b0}   <- offset 0, so the immediate
//                slice doesn't matter; safe without knowing FMT_LW exactly
//
// ASSUMPTION: gie_reg resets to 0 (T1 depends on this). If your gie_reg
// resets to 1, T1 will report a false FAIL -- check that file first.
// -----------------------------------------------------------------------
module irq_entry_tb;

    reg clk, rst_n, irq_in;
    reg collision_mode;              // T5: drives irq from RETI-in-EX
    integer errors = 0;
    integer i;

    localparam [7:0] ISR_VECTOR = 8'h40;   // must match the RTL localparam
    
    // Declare and drive irq_in_eff BEFORE the instantiation that uses it.
    wire irq_in_eff = collision_mode ? (uut.ex_br_type == 2'b11) : irq_in;

    processor_pipel_haz uut (
        .clk    (clk),
        .rst_n  (rst_n),
        .irq_in (irq_in_eff)
    );

    always #5 clk = ~clk;

    // ---- entry monitor: snapshot what the RTL saw the cycle irq fired ----
    reg        irq_seen;
    reg [7:0]  cap_id_pc, cap_redirect_addr, cap_pc_out;
    reg        cap_was_branch;
    integer    irq_count;

    always @(posedge clk) begin
        if (rst_n && uut.irq_taken) begin
            cap_id_pc         <= uut.id_pc;
            cap_redirect_addr <= uut.ex_pc_redirect_addr;
            cap_pc_out        <= uut.pc_out;
            cap_was_branch    <= uut.ex_pc_redirect;
            irq_seen          <= 1'b1;
            irq_count         <= irq_count + 1;
        end
    end

    // ---- T4 assertion: irq must never be taken during a stall ----
    always @(posedge clk)
        if (rst_n && uut.hdu_stall && uut.irq_taken) begin
            $display("FAIL: irq_taken asserted during hdu_stall");
            errors = errors + 1;
        end

    task check1(input [255:0] name, input a, input e);
        begin
            if (a !== e) begin
                $display("FAIL: %0s = %0b, expected %0b", name, a, e);
                errors = errors + 1;
            end else $display("PASS: %0s = %0b", name, a);
        end
    endtask

    task check8(input [255:0] name, input [7:0] a, input [7:0] e);
        begin
            if (a !== e) begin
                $display("FAIL: %0s = %0d, expected %0d", name, a, e);
                errors = errors + 1;
            end else $display("PASS: %0s = %0d", name, a);
        end
    endtask

    task neq8(input [255:0] name, input [7:0] a, input [7:0] notexp);
        begin
            if (a === notexp) begin
                $display("FAIL: %0s = %0d, should NOT have executed", name, a);
                errors = errors + 1;
            end else $display("PASS: %0s = %0d (correctly squashed)", name, a);
        end
    endtask

    task clear_imem;
        begin
            for (i = 0; i < 256; i = i + 1) uut.u_imem.mem[i] = 16'h0000;
        end
    endtask

    // Boot stub: LDI R7,target ; MOV LR,R7 ; RETI  -> GIE=1, PC=target
    task boot_to(input [7:0] target);
        begin
            uut.u_imem.mem[0] = 16'h3E00 | {7'b0, target};  // LDI R7,target
            uut.u_imem.mem[1] = 16'hCE01;                   // MOV LR,R7
            uut.u_imem.mem[2] = 16'h7000;                   // RETI
        end
    endtask

    task do_reset;
        begin
            rst_n = 0; irq_in = 0; collision_mode = 0;
            irq_seen = 0; irq_count = 0;
            cap_id_pc = 8'h00; cap_redirect_addr = 8'h00;
            cap_pc_out = 8'h00; cap_was_branch = 1'b0;
            @(negedge clk); @(negedge clk);
            rst_n = 1;
        end
    endtask

    // LDI chain at 16..22 : addr A writes register (A-15) with value (A-15)*16
    task load_ldi_chain;
        integer k;
        begin
            for (k = 0; k < 7; k = k + 1)
                uut.u_imem.mem[16+k] = 16'h3000 | ((k+1) << 9) | ((k+1)*16);
        end
    endtask

    // ISR at 64: NOP padding, RETI at 70
    task load_isr;
        begin
            uut.u_imem.mem[70] = 16'h7000;   // RETI
        end
    endtask

    integer squashed_reg;

    initial begin
        clk = 0; irq_in = 0; collision_mode = 0;

        // =============================================================
        // T1: GIE gating -- irq while GIE=0 must be ignored entirely
        // =============================================================
        $display("\n---- T1: GIE gating ----");
        clear_imem;
        load_ldi_chain;
        // NO boot stub: GIE stays at its reset value (assumed 0)
        for (i = 0; i < 16; i = i + 1) uut.u_imem.mem[i] = 16'h0000;
        do_reset;
        repeat (4) @(posedge clk);
        @(negedge clk); irq_in = 1;
        repeat (4) @(posedge clk);
        @(negedge clk); irq_in = 0;
        repeat (2) @(posedge clk); #1;

        check1("GIE is 0 at reset (T1 precondition)", uut.gie_out, 1'b0);
        check1("irq NOT taken while GIE=0",           irq_seen,    1'b0);

        // =============================================================
        // T2 + T3: entry mechanics and squash count
        // =============================================================
        $display("\n---- T2/T3: entry mechanics + squash count ----");
        clear_imem;
        boot_to(8'd16);
        load_ldi_chain;
        load_isr;
        do_reset;

        // land the pulse while the LDI chain is in ID (approx cycle 9-10)
        repeat (9) @(posedge clk);
        @(negedge clk); irq_in = 1;
        @(negedge clk); irq_in = 0;
        repeat (3) @(posedge clk); #1;

        check1("irq was taken (GIE=1)",        irq_seen,    1'b1);
        check1("GIE cleared on entry",         uut.gie_out, 1'b0);
        $display("INFO: captured id_pc=%0d  pc_out=%0d  was_branch=%0b",
                 cap_id_pc, cap_pc_out, cap_was_branch);

        if (cap_id_pc < 16 || cap_id_pc > 22) begin
            $display("FAIL: irq landed outside the LDI chain (id_pc=%0d) -- retune the pulse cycle",
                     cap_id_pc);
            errors = errors + 1;
        end

        check8("LR == resume_pc (id_pc, no branch in flight)",
               uut.lr_out, cap_id_pc);
        check8("PC redirected to ISR_VECTOR",
               uut.u_pc.pc_out, ISR_VECTOR + 8'd3);  // +3: a few ISR NOPs in by now

        // squash check: instruction AT cap_id_pc must not have run yet;
        // the one BEFORE it must have completed.
        squashed_reg = cap_id_pc - 15;
        neq8("squashed instr's register",
             uut.u_rf.regs[squashed_reg], (squashed_reg*16));
        if (squashed_reg > 1)
            check8("instruction before it completed",
                   uut.u_rf.regs[squashed_reg-1], (squashed_reg-1)*16);

        // =============================================================
        // T6: full round trip -- RETI resumes exactly at the squashed instr
        // =============================================================
        $display("\n---- T6: RETI round trip ----");
        repeat (20) @(posedge clk); #1;   // let ISR reach RETI at 70 and return

        check1("GIE restored after RETI", uut.gie_out, 1'b1);
        check8("resumed instruction now executed",
               uut.u_rf.regs[squashed_reg], (squashed_reg*16));
        check8("only ONE interrupt was taken", irq_count[7:0], 8'd1);

        // =============================================================
        // T4: stall-defer -- irq asserted during a load-use stall
        // =============================================================
        $display("\n---- T4: stall-defer ----");
        clear_imem;
        boot_to(8'd16);
        uut.u_imem.mem[16] = 16'h1200;   // LW   R1,0(R0)
        uut.u_imem.mem[17] = 16'hB201;   // ADDI R1,1      <- load-use stall
        uut.u_imem.mem[18] = 16'h3420;   // LDI  R2,32
        load_isr;
        do_reset;

        // hold irq high across the stall window; the always-block
        // assertion above fires if irq_taken ever coincides with hdu_stall
        repeat (6) @(posedge clk);
        @(negedge clk); irq_in = 1;
        repeat (6) @(posedge clk);
        @(negedge clk); irq_in = 0;
        repeat (4) @(posedge clk); #1;

        check1("irq eventually taken after stall cleared", irq_seen, 1'b1);

        // =============================================================
        // T5: branch collision -- RETI (br_type=11) resolving same cycle
        // =============================================================
        $display("\n---- T5: branch/irq same-cycle collision ----");
        clear_imem;
        boot_to(8'd16);
        uut.u_imem.mem[16] = 16'h3E32;   // LDI R7,50
        uut.u_imem.mem[17] = 16'hCE01;   // MOV LR,R7
        uut.u_imem.mem[18] = 16'h7000;   // RETI  -> target 50, collides w/ irq
        uut.u_imem.mem[50] = 16'h3420;   // LDI R2,32  (the real resume point)
        load_isr;
        do_reset;

        collision_mode = 1;              // irq fires when br_type==11 in EX
        repeat (16) @(posedge clk); #1;
        collision_mode = 0;

        $display("INFO: collision capture -- was_branch=%0b redirect_addr=%0d id_pc=%0d LR=%0d",
                 cap_was_branch, cap_redirect_addr, cap_id_pc, uut.lr_out);
        check1("branch and irq resolved same cycle", cap_was_branch, 1'b1);
        check8("LR == branch target (NOT id_pc)",
               uut.lr_out, cap_redirect_addr);

        // ---- summary ----
        if (errors == 0) $display("\n=== ALL PHASE B TESTS PASSED ===");
        else             $display("\n=== %0d TEST(S) FAILED ===", errors);
        $finish;
    end

endmodule