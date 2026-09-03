// alu_tb.v
// -----------------------------------------------------------------------
// Self-checking testbench for alu.v. Drives inputs, waits for combinational
// settle, and compares against expected result + flags. Prints PASS/FAIL
// per case and a summary at the end. Works with Icarus Verilog and Vivado
// simulation.
//
// Run with Icarus:
//   iverilog -o alu_sim alu.v alu_tb.v
//   vvp alu_sim
// -----------------------------------------------------------------------

`timescale 1ns/1ps

module alu_tb;

    reg  [7:0] alu_in_a;
    reg  [7:0] alu_in_b;
    reg  [2:0] alu_funct;
    wire [7:0] alu_result;
    wire       flag_z, flag_c, flag_n;

    integer errors = 0;
    integer tests  = 0;

    alu dut (
        .alu_in_a  (alu_in_a),
        .alu_in_b  (alu_in_b),
        .alu_funct (alu_funct),
        .alu_result(alu_result),
        .flag_z    (flag_z),
        .flag_c    (flag_c),
        .flag_n    (flag_n)
    );

    task check;
        input [127:0] name;
        input [7:0]   exp_result;
        input         exp_z;
        input         exp_c;
        input         exp_n;
        begin
            tests = tests + 1;
            #1; // let combinational logic settle
            if (alu_result !== exp_result || flag_z !== exp_z ||
                flag_c !== exp_c || flag_n !== exp_n) begin
                errors = errors + 1;
                $display("FAIL [%0s]: a=%0d b=%0d funct=%0b -> got result=%0d z=%0b c=%0b n=%0b, expected result=%0d z=%0b c=%0b n=%0b",
                    name, alu_in_a, alu_in_b, alu_funct,
                    alu_result, flag_z, flag_c, flag_n,
                    exp_result, exp_z, exp_c, exp_n);
            end else begin
                $display("PASS [%0s]: a=%0d b=%0d funct=%0b -> result=%0d z=%0b c=%0b n=%0b",
                    name, alu_in_a, alu_in_b, alu_funct, alu_result, flag_z, flag_c, flag_n);
            end
        end
    endtask

    initial begin
        // ---- ADD ----
        alu_in_a = 8'd10;  alu_in_b = 8'd20;  alu_funct = 3'b000;
        check("ADD basic", 8'd30, 1'b0, 1'b0, 1'b0);

        alu_in_a = 8'd200; alu_in_b = 8'd100; alu_funct = 3'b000; // 300 -> wraps to 44, carry
        check("ADD overflow/carry", 8'd44, 1'b0, 1'b1, 1'b0);

        alu_in_a = 8'd0;   alu_in_b = 8'd0;   alu_funct = 3'b000;
        check("ADD zero result", 8'd0, 1'b1, 1'b0, 1'b0);

        alu_in_a = 8'd200; alu_in_b = 8'd10;  alu_funct = 3'b000; // 210 -> bit7 set, no carry
        check("ADD negative-looking result (bit7 set)", 8'd210, 1'b0, 1'b0, 1'b1);

        // ---- SUB ----
        alu_in_a = 8'd20; alu_in_b = 8'd10; alu_funct = 3'b001; // no borrow -> C=1
        check("SUB basic no-borrow", 8'd10, 1'b0, 1'b1, 1'b0);

        alu_in_a = 8'd10; alu_in_b = 8'd10; alu_funct = 3'b001; // equal -> BEQ case
        check("SUB equal (BEQ case)", 8'd0, 1'b1, 1'b1, 1'b0);

        alu_in_a = 8'd10; alu_in_b = 8'd20; alu_funct = 3'b001; // borrow -> C=0
        check("SUB borrow", 8'd246, 1'b0, 1'b0, 1'b1);

        // ---- SHL ----
        alu_in_a = 8'b0000_0001; alu_in_b = 8'd3; alu_funct = 3'b010;
        check("SHL by 3", 8'b0000_1000, 1'b0, 1'b0, 1'b0);

        alu_in_a = 8'b1000_0001; alu_in_b = 8'd1; alu_funct = 3'b010; // MSB shifted out
        check("SHL carry-out", 8'b0000_0010, 1'b0, 1'b1, 1'b0);

        alu_in_a = 8'hFF; alu_in_b = 8'd0; alu_funct = 3'b010; // shift by 0
        check("SHL by 0", 8'hFF, 1'b0, 1'b0, 1'b1);

        // ---- SHR (logical) ----
        alu_in_a = 8'b1000_0000; alu_in_b = 8'd7; alu_funct = 3'b011;
        check("SHR logical by 7", 8'b0000_0001, 1'b0, 1'b0, 1'b0);

        alu_in_a = 8'b1000_0001; alu_in_b = 8'd1; alu_funct = 3'b011; // LSB shifted out
        check("SHR carry-out", 8'b0100_0000, 1'b0, 1'b1, 1'b0);

        alu_in_a = 8'hFF; alu_in_b = 8'd0; alu_funct = 3'b011; // shift by 0
        check("SHR by 0", 8'hFF, 1'b0, 1'b0, 1'b1);

        // ---- SHRA (arithmetic) ----
        alu_in_a = 8'b1000_0000; alu_in_b = 8'd1; alu_funct = 3'b100; // -128 >>> 1 = -64
        check("SHRA sign-fill negative", 8'b1100_0000, 1'b0, 1'b0, 1'b1);

        alu_in_a = 8'b0100_0000; alu_in_b = 8'd2; alu_funct = 3'b100; // positive, no sign fill
        check("SHRA positive value", 8'b0001_0000, 1'b0, 1'b0, 1'b0);

        alu_in_a = 8'b1111_1111; alu_in_b = 8'd4; alu_funct = 3'b100; // -1 >>> 4 = -1
        check("SHRA all-ones stays all-ones", 8'b1111_1111, 1'b0, 1'b1, 1'b1);

        // ---- Summary ----
        #1;
        if (errors == 0)
            $display("\nALL %0d TESTS PASSED", tests);
        else
            $display("\n%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule