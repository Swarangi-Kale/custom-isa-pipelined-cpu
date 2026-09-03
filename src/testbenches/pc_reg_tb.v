// pc_register_tb.v
// -----------------------------------------------------------------------
// Self-checking testbench for pc_register.v. Covers reset, normal
// increment, stall-hold, redirect (branch/jump), redirect-overrides-stall
// priority, and PC wraparound (255 -> 0).
//
// Run with Icarus:
//   iverilog -o pc_sim pc_register.v pc_register_tb.v
//   vvp pc_sim
// -----------------------------------------------------------------------

`timescale 1ns/1ps

module pc_register_tb;

    reg        clk;
    reg        rst_n;
    reg        pc_write_en;
    reg        pc_redirect;
    reg  [7:0] pc_redirect_addr;
    wire [7:0] pc_out;

    integer errors = 0;
    integer tests  = 0;

    pc_register dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .pc_write_en      (pc_write_en),
        .pc_redirect      (pc_redirect),
        .pc_redirect_addr (pc_redirect_addr),
        .pc_out           (pc_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [127:0] name;
        input [7:0]   exp_pc;
        begin
            tests = tests + 1;
            if (pc_out !== exp_pc) begin
                errors = errors + 1;
                $display("FAIL [%0s]: pc_out=%0d, expected %0d", name, pc_out, exp_pc);
            end else begin
                $display("PASS [%0s]: pc_out=%0d", name, pc_out);
            end
        end
    endtask

    initial begin
        rst_n            = 0;
        pc_write_en      = 0;
        pc_redirect      = 0;
        pc_redirect_addr = 8'd0;

        // ---- Reset ----
        @(negedge clk); @(negedge clk);
        check("reset holds pc=0 while rst_n=0", 8'd0);
        rst_n = 1;

        // ---- Normal increment ----
        pc_write_en = 1;
        @(negedge clk);
        check("first increment after reset", 8'd1);
        @(negedge clk);
        check("second increment", 8'd2);
        @(negedge clk);
        check("third increment", 8'd3);

        // ---- Stall: write_en=0 holds value ----
        pc_write_en = 0;
        @(negedge clk);
        check("stall cycle 1 holds pc=3", 8'd3);
        @(negedge clk);
        check("stall cycle 2 holds pc=3", 8'd3);

        // ---- Resume after stall ----
        pc_write_en = 1;
        @(negedge clk);
        check("resume increments from held value", 8'd4);

        // ---- Redirect (taken branch/jump) ----
        pc_redirect      = 1;
        pc_redirect_addr = 8'd100;
        @(negedge clk);
        check("redirect loads target address", 8'd100);

        // next cycle, redirect deasserted, normal increment resumes from target
        pc_redirect = 0;
        @(negedge clk);
        check("increment resumes from redirect target", 8'd101);

        // ---- Redirect overrides a concurrent stall ----
        pc_write_en      = 0;   // stall asserted...
        pc_redirect      = 1;   // ...at the same time as a redirect
        pc_redirect_addr = 8'd50;
        @(negedge clk);
        check("redirect wins over concurrent stall", 8'd50);

        // ---- Wraparound: 255 -> 0 ----
        pc_redirect      = 1;
        pc_redirect_addr = 8'd255;
        pc_write_en      = 1;
        @(negedge clk);
        check("load pc=255 via redirect", 8'd255);
        pc_redirect = 0;
        @(negedge clk);
        check("increment wraps 255 -> 0", 8'd0);

        // ---- Mid-run reset ----
        pc_write_en = 1;
        @(negedge clk);
        check("one more increment before reset test", 8'd1);
        rst_n = 0;
        @(negedge clk);
        check("mid-run reset clears pc to 0", 8'd0);

        // ---- Summary ----
        if (errors == 0)
            $display("\nALL %0d TESTS PASSED", tests);
        else
            $display("\n%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule