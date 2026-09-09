// mux2to1_tb.v
// -----------------------------------------------------------------------
// Self-checking testbench for mux2to1.v. Tests the generic module at two
// different WIDTH instantiations (8-bit and 3-bit) to confirm the
// parameterization genuinely works for both actual use cases in this
// datapath, not just the default width.
//
// Run with Icarus:
//   iverilog -o mux2_sim mux2to1.v mux2to1_tb.v
//   vvp mux2_sim
// -----------------------------------------------------------------------

`timescale 1ns/1ps

module mux2to1_tb;

    integer errors = 0;
    integer tests  = 0;

    // ---- 8-bit instance ----
    reg        sel8;
    reg  [7:0] in0_8, in1_8;
    wire [7:0] out8;

    mux2to1 #(.WIDTH(8)) dut8 (
        .sel (sel8),
        .in0 (in0_8),
        .in1 (in1_8),
        .out (out8)
    );

    // ---- 3-bit instance (register-address width) ----
    reg        sel3;
    reg  [2:0] in0_3, in1_3;
    wire [2:0] out3;

    mux2to1 #(.WIDTH(3)) dut3 (
        .sel (sel3),
        .in0 (in0_3),
        .in1 (in1_3),
        .out (out3)
    );

    task check8;
        input [127:0] name;
        input [7:0]   exp;
        begin
            tests = tests + 1;
            #1;
            if (out8 !== exp) begin
                errors = errors + 1;
                $display("FAIL [%0s]: out8=%0d, expected %0d", name, out8, exp);
            end else begin
                $display("PASS [%0s]: out8=%0d", name, out8);
            end
        end
    endtask

    task check3;
        input [127:0] name;
        input [2:0]   exp;
        begin
            tests = tests + 1;
            #1;
            if (out3 !== exp) begin
                errors = errors + 1;
                $display("FAIL [%0s]: out3=%0d, expected %0d", name, out3, exp);
            end else begin
                $display("PASS [%0s]: out3=%0d", name, out3);
            end
        end
    endtask

    initial begin
        // ---- 8-bit width ----
        in0_8 = 8'd10; in1_8 = 8'd200;
        sel8 = 1'b0; check8("8-bit: sel=0 selects in0", 8'd10);
        sel8 = 1'b1; check8("8-bit: sel=1 selects in1", 8'd200);

        in0_8 = 8'hFF; in1_8 = 8'h00;
        sel8 = 1'b0; check8("8-bit: in0=0xFF selected", 8'hFF);
        sel8 = 1'b1; check8("8-bit: in1=0x00 selected", 8'h00);

        // ---- 3-bit width (register address use case) ----
        in0_3 = 3'b101; in1_3 = 3'b010;
        sel3 = 1'b0; check3("3-bit: sel=0 selects in0 (R-type rs2 field position)", 3'b101);
        sel3 = 1'b1; check3("3-bit: sel=1 selects in1 (B-type/SW/STORESP field position)", 3'b010);

        // ---- Summary ----
        if (errors == 0)
            $display("\nALL %0d TESTS PASSED", tests);
        else
            $display("\n%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule