`timescale 1ns/1ps
// -----------------------------------------------------------------------
// task0_loop_tb.v
// Standalone test for a single task's infinite loop:
//   load own counter -> increment -> store back -> jump to loop start
// No interrupts, no context switch -- isolates the basic LW/ADDI/SW/JMP
// path (incl. the LW->ADDI load-use stall and the JMP flush) before any
// ISR is added on top.
//
// Program under test (addresses 0x00-0x03, counter at data_memory 0x01):
//   0x00  LW   R1, 0x01(R0)   -> 1201
//   0x01  ADDI R1, #1         -> B201
//   0x02  SW   R1, 0x01(R0)   -> 2201
//   0x03  JMP  0x00           -> 6000
//
// Runs for a fixed, finite number of cycles and then $finish -- does NOT
// run indefinitely.
//
// ASSUMPTIONS (same hierarchical paths as sp_roundtrip_tb.v -- verify
// against your files):
//   - uut.u_imem.mem[addr]   is instr_mem's array
//   - uut.u_dmem.mem[addr]   is data_memory's array
//   - uut.u_rf.regs[n]       is reg_bank's array
// -----------------------------------------------------------------------
module task0_loop_tb;

    reg clk, rst_n;
    integer i;
    integer errors = 0;

    localparam COUNTER_ADDR = 8'h00;

    processor_pipel_haz uut (
        .clk    (clk),
        .rst_n  (rst_n),
        .irq_in (1'b0)          // interrupts held off for this test
    );

    always #5 clk = ~clk;

    // Strictly-greater-than check (counter must have advanced between
    // checkpoints) -- can't assert exact values without cycle-accurate
    // stall/flush accounting, so this is what actually gets verified.
    task check_increasing(input [255:0] name, input [7:0] prev, input [7:0] now_val);
        begin
            if (now_val <= prev) begin
                $display("FAIL: %0s did not increase (prev=0x%02h, now=0x%02h)",
                          name, prev, now_val);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s increased (0x%02h -> 0x%02h)",
                          name, prev, now_val);
            end
        end
    endtask

    reg [7:0] ckpt1, ckpt2, ckpt3;

    initial begin
        clk = 0; rst_n = 0;

        // zero instr mem
        for (i = 0; i < 256; i = i + 1) uut.u_imem.mem[i] = 16'h0000;
        // zero data mem explicitly -- don't rely on power-up state for
        // the counter's starting value
        for (i = 0; i < 256; i = i + 1) uut.u_dmem.mem[i] = 8'h00;
        
        uut.u_imem.mem[0] = 16'h1201; // LW   R1, 0x01(R0)
        uut.u_imem.mem[1] = 16'hB201; // ADDI R1, #1
        uut.u_imem.mem[2] = 16'h2201; // SW   R1, 0x01(R0)
        uut.u_imem.mem[3] = 16'h6000; // JMP  0x00

        #12 rst_n = 1;
        uut.u_dmem.mem[1] = 8'h04;

        

        // ---- checkpoint 1: let a handful of loop passes happen ----
        repeat (100) @(posedge clk); #1;
        ckpt1 = uut.u_dmem.mem[COUNTER_ADDR];
        $display("INFO: checkpoint1 counter = 0x%02h at t=%0t", ckpt1, $time);
        check_increasing("counter (0 -> ckpt1)", 8'h00, ckpt1);

        // ---- checkpoint 2 ----
        repeat (100) @(posedge clk); #1;
        ckpt2 = uut.u_dmem.mem[COUNTER_ADDR];
        $display("INFO: checkpoint2 counter = 0x%02h at t=%0t", ckpt2, $time);
        check_increasing("counter (ckpt1 -> ckpt2)", ckpt1, ckpt2);

        // ---- checkpoint 3 ----
        repeat (100) @(posedge clk); #1;
        ckpt3 = uut.u_dmem.mem[COUNTER_ADDR];
        $display("INFO: checkpoint3 counter = 0x%02h at t=%0t", ckpt3, $time);
        check_increasing("counter (ckpt2 -> ckpt3)", ckpt2, ckpt3);

        // sanity: R1 in the register file should hold the same value
        // as the last thing stored back (whatever iteration it's mid-way through)
        $display("INFO: final R1 = 0x%02h, final mem[0x01] = 0x%02h",
                  uut.u_rf.regs[1], uut.u_dmem.mem[COUNTER_ADDR]);

        if (errors == 0) $display("\n=== TASK0 LOOP TEST PASSED (%0d checks) ===", 3);
        else              $display("\n=== %0d TEST(S) FAILED ===", errors);

        // fixed, finite runtime -- stop here, do not run indefinitely
        $finish;
    end

endmodule