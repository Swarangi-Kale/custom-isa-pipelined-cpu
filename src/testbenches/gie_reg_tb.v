// gie_reg_tb.v
// -----------------------------------------------------------------------
// Self-checking testbench for gie_register.v. Covers reset, RETI setting
// GIE, holding across cycles, simulated interrupt-taken clearing GIE
// (stand-in for hardware that doesn't exist yet, same approach used for
// lr_register_tb.v), and clear-wins-over-set priority.
//
// Run with Icarus:
//   iverilog -o gie_sim gie_register.v gie_register_tb.v
//   vvp gie_sim
// -----------------------------------------------------------------------

`timescale 1ns/1ps

module gie_reg_tb;

    reg clk;
    reg rst_n;
    reg gie_set, gie_clear;
    wire gie_out;

    integer errors = 0;
    integer tests  = 0;

    gie_reg dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .gie_set   (gie_set),
        .gie_clear (gie_clear),
        .gie_out   (gie_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [127:0] name;
        input         exp;
        begin
            tests = tests + 1;
            if (gie_out !== exp) begin
                errors = errors + 1;
                $display("FAIL [%0s]: gie_out=%b, expected %b", name, gie_out, exp);
            end else begin
                $display("PASS [%0s]: gie_out=%b", name, gie_out);
            end
        end
    endtask

    initial begin
        rst_n = 0; gie_set = 0; gie_clear = 0;

        // ---- Reset: interrupts disabled ----
        @(negedge clk); @(negedge clk);
        check("reset: GIE=0 (disabled)", 1'b0);
        rst_n = 1;

        // ---- RETI sets GIE ----
        gie_set = 1'b1;
        @(negedge clk);
        check("RETI sets GIE=1", 1'b1);

        // ---- Holds across cycles with no further writes ----
        gie_set = 1'b0;
        @(negedge clk); @(negedge clk);
        check("GIE holds at 1 with no writes", 1'b1);

        // ---- Simulated interrupt-taken clears GIE ----
        gie_clear = 1'b1;
        @(negedge clk);
        check("simulated interrupt-taken clears GIE=0", 1'b0);

        // ---- Holds at 0 ----
        gie_clear = 1'b0;
        @(negedge clk);
        check("GIE holds at 0", 1'b0);

        // ---- RETI sets it again ----
        gie_set = 1'b1;
        @(negedge clk);
        check("second RETI sets GIE=1 again", 1'b1);

        // ---- Clear-wins-over-set priority ----
        gie_set   = 1'b1;
        gie_clear = 1'b1; // both asserted same cycle
        @(negedge clk);
        check("gie_clear wins over concurrent gie_set", 1'b0);

        // ---- Mid-run reset ----
        gie_set = 1'b1; gie_clear = 1'b0;
        @(negedge clk);
        check("GIE set to 1 before reset test", 1'b1);
        rst_n = 0;
        @(negedge clk);
        check("mid-run reset clears GIE to 0", 1'b0);

        // ---- Summary ----
        if (errors == 0)
            $display("\nALL %0d TESTS PASSED", tests);
        else
            $display("\n%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule