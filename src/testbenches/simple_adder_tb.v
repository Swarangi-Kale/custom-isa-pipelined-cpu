// simple_adder_tb.v
// -----------------------------------------------------------------------
// Self-checking testbench for branch_target_adder.v. Covers positive and
// negative (backward-branch) offsets, zero offset, and wraparound at the
// 8-bit address boundary.
//
// Run with Icarus:
//   iverilog -o bta_sim branch_target_adder.v branch_target_adder_tb.v
//   vvp bta_sim
// -----------------------------------------------------------------------

`timescale 1ns/1ps

module simple_adder_tb;

    reg  [7:0] pc_in;
    reg  [7:0] offset;
    wire [7:0] branch_target;

    integer errors = 0;
    integer tests  = 0;

    simple_adder dut (
        .pc_in         (pc_in),
        .offset        (offset),
        .branch_target (branch_target)
    );

    task check;
        input [127:0] name;
        input [7:0]   exp;
        begin
            tests = tests + 1;
            #1;
            if (branch_target !== exp) begin
                errors = errors + 1;
                $display("FAIL [%0s]: pc=%0d offset=%0d -> got %0d, expected %0d",
                    name, pc_in, offset, branch_target, exp);
            end else begin
                $display("PASS [%0s]: pc=%0d offset=%0d -> %0d", name, pc_in, offset, branch_target);
            end
        end
    endtask

    initial begin
        // ---- Forward branch (positive offset) ----
        pc_in = 8'd10; offset = 8'd5;
        check("forward branch: PC=10 +5 = 15", 8'd15);

        // ---- Backward branch (negative/sign-extended offset) ----
        pc_in = 8'd20; offset = -8'sd5; // sign-extended -5
        check("backward branch: PC=20 + (-5) = 15", 8'd15);

        // ---- Zero offset (degenerate, PC unchanged) ----
        pc_in = 8'd50; offset = 8'd0;
        check("zero offset: PC unchanged at 50", 8'd50);

        // ---- Largest forward offset representable from a 6-bit signed field (+31) ----
        pc_in = 8'd100; offset = 8'd31;
        check("max positive 6-bit-derived offset: 100+31=131", 8'd131);

        // ---- Largest backward offset representable from a 6-bit signed field (-32) ----
        pc_in = 8'd100; offset = -8'sd32;
        check("max negative 6-bit-derived offset: 100-32=68", 8'd68);

        // ---- Wraparound past address 255 ----
        pc_in = 8'd250; offset = 8'd10;
        check("wraparound: 250+10 wraps to 4", 8'd4);

        // ---- Wraparound below address 0 ----
        pc_in = 8'd2; offset = -8'sd5;
        check("wraparound below zero: 2-5 wraps to 253", 8'd253);

        // ---- Summary ----
        if (errors == 0)
            $display("\nALL %0d TESTS PASSED", tests);
        else
            $display("\n%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule