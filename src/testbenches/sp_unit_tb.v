// sp_unit_tb.v
// -----------------------------------------------------------------------
// Self-checking testbench for sp_unit.v. Covers reset, ADDSP commit
// (positive and negative/signed addends), non-destructive address
// generation for STORESP/LOADSP, and wraparound.
//
// Run with Icarus:
//   iverilog -o sp_sim sp_unit.v sp_unit_tb.v
//   vvp sp_sim
// -----------------------------------------------------------------------

`timescale 1ns/1ps

module sp_unit_tb;

    reg        clk;
    reg        rst_n;
    reg        sp_we;
    reg  [7:0] sp_addend;
    wire [7:0] sp_out;
    wire [7:0] sp_addr_out;

    integer errors = 0;
    integer tests  = 0;

    sp_unit #(.SP_RESET_VAL(8'h00)) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .sp_we       (sp_we),
        .sp_addend   (sp_addend),
        .sp_out      (sp_out),
        .sp_addr_out (sp_addr_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [127:0] name;
        input [7:0]   exp_sp;
        input [7:0]   exp_addr;
        begin
            tests = tests + 1;
            #1;
            if (sp_out !== exp_sp || sp_addr_out !== exp_addr) begin
                errors = errors + 1;
                $display("FAIL [%0s]: sp_out=%0d sp_addr_out=%0d, expected sp_out=%0d sp_addr_out=%0d",
                    name, sp_out, sp_addr_out, exp_sp, exp_addr);
            end else begin
                $display("PASS [%0s]: sp_out=%0d sp_addr_out=%0d", name, sp_out, sp_addr_out);
            end
        end
    endtask

    initial begin
        rst_n     = 0;
        sp_we     = 0;
        sp_addend = 8'd0;

        // ---- Reset ----
        @(negedge clk); @(negedge clk);
        check("reset: sp=0", 8'd0, 8'd0);
        rst_n = 1;

        // ---- ADDSP with positive addend ----
        sp_we     = 1;
        sp_addend = 8'd10;
        @(negedge clk);
        sp_addend = 8'd0; // clear addend so sp_addr_out (combinational) reads back sp_out cleanly
        check("ADDSP +10 commits", 8'd10, 8'd10);

        // ---- ADDSP with negative (signed) addend ----
        sp_addend = -8'sd3; // sign-extended -3
        @(negedge clk);
        sp_addend = 8'd0;
        check("ADDSP -3 commits (10-3=7)", 8'd7, 8'd7);

        // ---- STORESP/LOADSP: non-destructive address calc ----
        sp_we     = 0;
        sp_addend = 8'd5;
        @(negedge clk);
        check("STORESP offset+5: addr=12, SP unchanged at 7", 8'd7, 8'd12);

        sp_addend = -8'sd2;
        @(negedge clk);
        check("LOADSP offset-2: addr=5, SP still unchanged at 7", 8'd7, 8'd5);

        // ---- ADDSP wraparound (SP=7, add 250 -> wraps) ----
        sp_we     = 1;
        sp_addend = 8'd250; // as signed 8-bit, 250 = -6
        @(negedge clk);
        sp_addend = 8'd0;
        check("ADDSP wraparound: 7 + (-6) = 1", 8'd1, 8'd1);

        // ---- Back-to-back ADDSP commits ----
        sp_addend = 8'd20;
        @(negedge clk);
        sp_addend = 8'd0;
        check("ADDSP +20: 1+20=21", 8'd21, 8'd21);

        // ---- sp_we=0 holds SP even with nonzero addend ----
        sp_we     = 0;
        sp_addend = 8'd99;
        @(negedge clk);
        check("sp_we=0 holds SP at 21 (addr shows would-be 120)", 8'd21, 8'd120);

        // ---- Mid-run reset ----
        sp_addend = 8'd0;
        rst_n = 0;
        @(negedge clk);
        check("mid-run reset clears SP to 0", 8'd0, 8'd0);

        // ---- Summary ----
        if (errors == 0)
            $display("\nALL %0d TESTS PASSED", tests);
        else
            $display("\n%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule