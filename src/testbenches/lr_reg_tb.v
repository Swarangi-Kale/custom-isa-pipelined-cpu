// lr_reg_tb.v
// -----------------------------------------------------------------------
// Self-checking testbench for lr_register.v. Since no instruction writes
// LR yet, lr_we/lr_wdata are driven directly here as a stand-in for the
// future interrupt-entry hardware - this verifies the register mechanics
// in isolation, ahead of that hardware existing.
//
// Run with Icarus:
//   iverilog -o lr_sim lr_register.v lr_register_tb.v
//   vvp lr_sim
// -----------------------------------------------------------------------

`timescale 1ns/1ps

module lr_reg_tb;

    reg        clk;
    reg        rst_n;
    reg        lr_we;
    reg  [7:0] lr_wdata;
    wire [7:0] lr_out;

    integer errors = 0;
    integer tests  = 0;

    lr_reg dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .lr_we   (lr_we),
        .lr_wdata(lr_wdata),
        .lr_out  (lr_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [127:0] name;
        input [7:0]   exp_lr;
        begin
            tests = tests + 1;
            if (lr_out !== exp_lr) begin
                errors = errors + 1;
                $display("FAIL [%0s]: lr_out=%0d, expected %0d", name, lr_out, exp_lr);
            end else begin
                $display("PASS [%0s]: lr_out=%0d", name, lr_out);
            end
        end
    endtask

    initial begin
        rst_n    = 0;
        lr_we    = 0;
        lr_wdata = 8'd0;

        // ---- Reset ----
        @(negedge clk); @(negedge clk);
        check("reset: lr=0", 8'd0);
        rst_n = 1;

        // ---- Write disabled: no change ----
        lr_wdata = 8'd77;
        @(negedge clk);
        check("lr_we=0 leaves lr unchanged", 8'd0);

        // ---- Simulated interrupt-entry write (LR <= PC_next) ----
        lr_we    = 1;
        lr_wdata = 8'd42;
        @(negedge clk);
        check("simulated interrupt-entry write: lr=42", 8'd42);

        // ---- Write disabled again: holds value ----
        lr_we = 0;
        @(negedge clk); @(negedge clk);
        check("lr_we=0 holds lr=42 across cycles", 8'd42);

        // ---- Read by RETI is just reading lr_out; overwrite with new value ----
        lr_we    = 1;
        lr_wdata = 8'd200;
        @(negedge clk);
        check("second write updates lr=200", 8'd200);

        // ---- Mid-run reset ----
        lr_we = 0;
        rst_n = 0;
        @(negedge clk);
        check("mid-run reset clears lr to 0", 8'd0);

        // ---- Summary ----
        if (errors == 0)
            $display("\nALL %0d TESTS PASSED", tests);
        else
            $display("\n%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule