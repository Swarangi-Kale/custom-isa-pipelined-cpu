// ----------------------------------------------------------------------
// irq_tb.v
// Interrupt/RETI-focused integration testbench for processor_pipel_haz.v.
//
// One continuous program/timeline (GIE and flags carry state naturally
// across the three checks):
//
//   0: LDI  R1,9        ; R1 = 9  (boot resume target)
//   1: MOV  LR,R1        ; LR = 9
//   2: RETI               ; GIE: 0->1, jump to LR = addr 9
//   3-8: NOP              ; branch-shadow / safety filler (flushed anyway)
//   9: NOP               ; cushion before flag snapshot
//  10: ADD  R2,R0,R0     ; R0=0+0=0 -> Z=1,C=0,N=0  (pre-interrupt snapshot)
//  11..: NOP (loop)      ; CPU idles here; testbench pulses irq_in once
//                          resume_pc will land somewhere in this NOP field
//
//  ISR_VECTOR = 8'h40 (64):
//  64: NOP               ; padding
//  65: NOP               ; padding
//  66: LDI  R6,0xFF       ; R6 = 255
//  67: ADD  R7,R6,R6      ; R7 = 254, C=1,Z=0,N=1  (ISR clobbers flags)
//  68: RETI               ; GIE: 0->1, jump back to resume_pc
//
// Instruction memory is zero-filled first so nothing fetched is ever X.
//
// Run with Icarus (adjust file list to your actual module filenames):
//   iverilog -o proc_sim alu.v reg_bank.v pc_register.v sp_unit.v lr_reg.v \
//     flags_reg.v sign_extension_unit.v instr_mem.v data_memory.v \
//     control_unit_pipelined.v mux2to1.v mux4to1.v simple_adder.v gie_reg.v \
//     forwarding_unit.v hazard_detection_unit.v if_id_reg_modified.v \
//     id_ex_reg_modified.v ex_mem_reg.v mem_wb_reg.v lr_reg.v \
//     processor_pipel_haz.v processor_pipel_haz_irq_tb.v
//   vvp proc_sim
// -----------------------------------------------------------------------
`timescale 1ns/1ps

module irq_tb;

    reg clk, rst_n, irq_in;
    integer errors = 0;
    integer i;

    // live monitor state for Test 2 (gie_set edge tracking)
    reg pending_gie_check;
    integer gie_set_count = 0;

    processor_pipel_haz uut (
        .clk    (clk),
        .rst_n  (rst_n),
        .irq_in (irq_in)
    );

    always #5 clk = ~clk;

    task check8(input [255:0] name, input [7:0] actual, input [7:0] expected);
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s = %0d, expected %0d", name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = %0d", name, actual);
            end
        end
    endtask

    task check1(input [255:0] name, input actual, input expected);
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s = %0b, expected %0b", name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = %0b", name, actual);
            end
        end
    endtask

    // ---- Test 2: live gie_set -> gie_out edge check, no hardcoded cycles ----
    // At the posedge where ex_gie_set is high, gie_out still reads its
    // PRE-edge value (must be 0, since RETI is only just now in EX).
    // One cycle later, gie_out must read 1 (post-edge value from the
    // previous cycle's update). Fires naturally on both the boot RETI
    // and the ISR RETI.
    initial pending_gie_check = 1'b0;
    always @(posedge clk) begin
        if (rst_n && uut.ex_gie_set) begin
            check1("gie_out still 0 while RETI is in EX", uut.gie_out, 1'b0);
            pending_gie_check <= 1'b1;
            gie_set_count     <= gie_set_count + 1;
        end else if (pending_gie_check) begin
            check1("gie_out == 1 one cycle after RETI's gie_set", uut.gie_out, 1'b1);
            pending_gie_check <= 1'b0;
        end
    end

    initial begin
        clk    = 0;
        rst_n  = 0;
        irq_in = 0;

        // Zero-fill instruction memory so nothing fetched is ever X.
        for (i = 0; i < 256; i = i + 1)
            uut.u_imem.mem[i] = 16'h0000;

        // ---- Boot sequence ----
        uut.u_imem.mem[0] = 16'h3209; // LDI  R1,9
        uut.u_imem.mem[1] = 16'hC201; // MOV  LR,R1
        uut.u_imem.mem[2] = 16'h7000; // RETI  (GIE<-1, jump to LR=9)
        // addr 3-8: NOP filler (branch-shadow-ish, harmless either way)

        // ---- Pre-interrupt flag snapshot ----
        uut.u_imem.mem[9]  = 16'h0000; // NOP cushion
        uut.u_imem.mem[10] = 16'h0405; // ADD  R2,R0,R0 -> Z=1,C=0,N=0
        // addr 11.. : NOP idle loop (irq_in pulsed while CPU sits here)

        // ---- ISR at ISR_VECTOR = 8'h40 (64) ----
        uut.u_imem.mem[64] = 16'h0000; // NOP padding
        uut.u_imem.mem[65] = 16'h0000; // NOP padding
        uut.u_imem.mem[66] = 16'h3CFF; // LDI  R6,0xFF
        uut.u_imem.mem[67] = 16'h0FB5; // ADD  R7,R6,R6 -> R7=0xFE, Z=0,C=1,N=1
        uut.u_imem.mem[68] = 16'h7000; // RETI  (GIE<-1, jump back to resume_pc)

        #12 rst_n = 1;

        // ---- Let boot RETI + pre-interrupt ADD commit ----
        repeat (20) @(posedge clk);
        #1;

        check1("gie_out == 1 after boot RETI", uut.gie_out, 1'b1);
        $display("INFO: pre-interrupt flag snapshot  Z=%0b C=%0b N=%0b",
                  uut.flag_z, uut.flag_c, uut.flag_n);
        check1("pre-interrupt flag_z (ADD R2,R0,R0)", uut.flag_z, 1'b1);
        check1("pre-interrupt flag_c (ADD R2,R0,R0)", uut.flag_c, 1'b0);
        check1("pre-interrupt flag_n (ADD R2,R0,R0)", uut.flag_n, 1'b0);

        // ---- Test 1: pulse irq_in for exactly one cycle ----
        @(negedge clk); irq_in = 1'b1;
        @(negedge clk); irq_in = 1'b0;
        #1;

        // gie_out drops on the edge following the pulse
        @(posedge clk); #1;
        check1("gie_out == 0 immediately after irq taken", uut.gie_out, 1'b0);

        // and stays 0 for several more cycles (well inside the ISR window,
        // before its RETI has a chance to re-enable it)
        repeat (3) begin
            @(posedge clk); #1;
            check1("gie_out stays 0 during ISR", uut.gie_out, 1'b0);
        end

        // ---- Test 2 runs live via the always block above (both RETIs) ----
        // Wait for the ISR's RETI (2nd gie_set event) plus drain margin.
        while (gie_set_count < 2) @(posedge clk);
        repeat (5) @(posedge clk);
        #1;

        // ---- Test 3: flags after ISR settles ----
        $display("INFO: post-ISR flags  Z=%0b C=%0b N=%0b (pre-interrupt snapshot was Z=1 C=0 N=0)",
                  uut.flag_z, uut.flag_c, uut.flag_n);
        check1("post-ISR flag_z (restored to pre-interrupt)", uut.flag_z, 1'b1);
        check1("post-ISR flag_c (restored to pre-interrupt)", uut.flag_c, 1'b0);
        check1("post-ISR flag_n (restored to pre-interrupt)", uut.flag_n, 1'b0);

        // ---- Sanity: registers touched along the way ----
        check8("R1 (boot LDI)",        uut.u_rf.regs[1], 8'd9);
        check8("R2 (pre-interrupt ADD)", uut.u_rf.regs[2], 8'd0);
        check8("R6 (ISR LDI)",          uut.u_rf.regs[6], 8'd255);
        check8("R7 (ISR ADD, wraps)",   uut.u_rf.regs[7], 8'd254);

        if (errors == 0)
            $display("\n=== ALL TESTS PASSED ===");
        else
            $display("\n=== %0d TEST(S) FAILED ===", errors);

        $finish;
    end

endmodule