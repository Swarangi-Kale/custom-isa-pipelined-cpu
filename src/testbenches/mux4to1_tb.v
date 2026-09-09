// mux4to1_tb.v
// -----------------------------------------------------------------------
// Self-checking testbench for mux4to1.v at WIDTH=8 (the only width this
// datapath needs a 4:1 mux at - WB mux and PC-target mux both carry
// 8-bit values).
//
// Run with Icarus:
//   iverilog -o mux4_sim mux4to1.v mux4to1_tb.v
//   vvp mux4_sim
// -----------------------------------------------------------------------

`timescale 1ns/1ps

module mux4to1_tb;

    reg  [1:0] sel;
    reg  [7:0] in0, in1, in2, in3;
    wire [7:0] out;

    integer errors = 0;
    integer tests  = 0;

    mux4to1 #(.WIDTH(8)) dut (
        .sel (sel),
        .in0 (in0),
        .in1 (in1),
        .in2 (in2),
        .in3 (in3),
        .out (out)
    );

    task check;
        input [127:0] name;
        input [7:0]   exp;
        begin
            tests = tests + 1;
            #1;
            if (out !== exp) begin
                errors = errors + 1;
                $display("FAIL [%0s]: sel=%b out=%0d, expected %0d", name, sel, out, exp);
            end else begin
                $display("PASS [%0s]: sel=%b out=%0d", name, sel, out);
            end
        end
    endtask

    initial begin
        in0 = 8'd11; in1 = 8'd22; in2 = 8'd33; in3 = 8'd44;

        sel = 2'b00; check("sel=00 selects in0", 8'd11);
        sel = 2'b01; check("sel=01 selects in1", 8'd22);
        sel = 2'b10; check("sel=10 selects in2", 8'd33);
        sel = 2'b11; check("sel=11 selects in3 (unused input, still correctly muxed)", 8'd44);

        // reconfirm after changing input values - correct source tracked live
        in0 = 8'd200;
        sel = 2'b00; check("in0 change reflected immediately", 8'd200);

        // ---- Summary ----
        if (errors == 0)
            $display("\nALL %0d TESTS PASSED", tests);
        else
            $display("\n%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule