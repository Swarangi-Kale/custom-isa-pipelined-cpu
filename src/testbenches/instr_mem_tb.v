// instr_mem_tb.v
// -----------------------------------------------------------------------
// Self-checking testbench for instruction_memory.v. Since there's no
// runtime write port, the program is loaded by poking dut.mem[] directly
// (hierarchical reference) - a stand-in for what $readmemh/INIT_FILE
// would do in a real top-level.
//
// Run with Icarus:
//   iverilog -o imem_sim instruction_memory.v instruction_memory_tb.v
//   vvp imem_sim
// -----------------------------------------------------------------------

`timescale 1ns/1ps

module instr_mem_tb;

    reg  [7:0]  addr;
    wire [15:0] instr_out;

    integer errors = 0;
    integer tests  = 0;

    instr_mem #(.MEM_DEPTH(256), .INIT_FILE("")) dut (
        .addr      (addr),
        .instr_out (instr_out)
    );

    task check;
        input [127:0] name;
        input [15:0]  exp_instr;
        begin
            tests = tests + 1;
            #1;
            if (instr_out !== exp_instr) begin
                errors = errors + 1;
                $display("FAIL [%0s]: addr=%0d -> instr_out=%h, expected %h", name, addr, instr_out, exp_instr);
            end else begin
                $display("PASS [%0s]: addr=%0d -> instr_out=%h", name, addr, instr_out);
            end
        end
    endtask

    initial begin
        // ---- Default fill: unprogrammed locations are 0x0000 ----
        addr = 8'd0;
        check("unprogrammed addr 0 defaults to 0x0000", 16'h0000);

        addr = 8'd255;
        check("unprogrammed addr 255 defaults to 0x0000", 16'h0000);

        // ---- Load a small program by poking mem[] directly ----
        dut.mem[0] = 16'h1234;
        dut.mem[1] = 16'hABCD;
        dut.mem[2] = 16'hFFFF;
        dut.mem[100] = 16'h00FF;

        addr = 8'd0;
        check("addr 0 reads loaded 0x1234", 16'h1234);

        addr = 8'd1;
        check("addr 1 reads loaded 0xABCD", 16'hABCD);

        addr = 8'd2;
        check("addr 2 reads loaded 0xFFFF", 16'hFFFF);

        addr = 8'd100;
        check("addr 100 reads loaded 0x00FF", 16'h00FF);

        // ---- Untouched location between programmed ones stays default ----
        addr = 8'd3;
        check("addr 3 (untouched) still 0x0000", 16'h0000);

        // ---- Combinational read: changing addr immediately updates output ----
        addr = 8'd1;
        #1;
        if (instr_out !== 16'hABCD) begin
            errors = errors + 1;
            tests = tests + 1;
            $display("FAIL [combinational read reacts to addr change]: got %h", instr_out);
        end else begin
            tests = tests + 1;
            $display("PASS [combinational read reacts to addr change]: got %h", instr_out);
        end

        // ---- Summary ----
        if (errors == 0)
            $display("\nALL %0d TESTS PASSED", tests);
        else
            $display("\n%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule