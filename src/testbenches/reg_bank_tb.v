// reg_bank_tb.v
// -----------------------------------------------------------------------
// Self-checking testbench for register_file.v. Uses a clock, drives
// synchronous writes and checks asynchronous reads, including reset
// behavior, R0 being an ordinary register, and read-during-write timing.
//
// Run with Icarus:
//   iverilog -o rf_sim register_file.v register_file_tb.v
//   vvp rf_sim
// -----------------------------------------------------------------------

`timescale 1ns/1ps

module reg_bank_tb;

    reg        clk;
    reg        rst_n;
    reg  [2:0] rs1_addr, rs2_addr;
    wire [7:0] rs1_rdata, rs2_rdata;
    reg  [2:0] rd_addr;
    reg  [7:0] rd_wdata;
    reg        rd_we;

    integer errors = 0;
    integer tests  = 0;
    integer i;

    reg_bank dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .rs1_addr  (rs1_addr),
        .rs2_addr  (rs2_addr),
        .rs1_rdata (rs1_rdata),
        .rs2_rdata (rs2_rdata),
        .rd_addr   (rd_addr),
        .rd_wdata  (rd_wdata),
        .rd_we     (rd_we)
    );

    // 10ns clock period
    initial clk = 0;
    always #5 clk = ~clk;

    task write_reg;
        input [2:0] addr;
        input [7:0] data;
        begin
            @(negedge clk);
            rd_addr  = addr;
            rd_wdata = data;
            rd_we    = 1'b1;
            @(posedge clk); // write lands here
            @(negedge clk);
            rd_we    = 1'b0;
        end
    endtask

    task check_read;
        input [127:0] name;
        input [2:0]   addr1;
        input [2:0]   addr2;
        input [7:0]   exp1;
        input [7:0]   exp2;
        begin
            tests = tests + 1;
            rs1_addr = addr1;
            rs2_addr = addr2;
            #1; // combinational settle
            if (rs1_rdata !== exp1 || rs2_rdata !== exp2) begin
                errors = errors + 1;
                $display("FAIL [%0s]: R%0d=%0d R%0d=%0d, expected R%0d=%0d R%0d=%0d",
                    name, addr1, rs1_rdata, addr2, rs2_rdata, addr1, exp1, addr2, exp2);
            end else begin
                $display("PASS [%0s]: R%0d=%0d R%0d=%0d", name, addr1, rs1_rdata, addr2, rs2_rdata);
            end
        end
    endtask

    initial begin
        rst_n    = 0;
        rs1_addr = 0; rs2_addr = 0;
        rd_addr  = 0; rd_wdata = 0; rd_we = 0;

        // ---- Reset: all regs should read 0 ----
        @(negedge clk); @(negedge clk); // hold reset across a couple edges
        rst_n = 1;
        @(negedge clk);
        check_read("post-reset all zero (R0,R7)", 3'd0, 3'd7, 8'd0, 8'd0);

        // ---- Basic write then read ----
        write_reg(3'd3, 8'd42);
        check_read("write R3=42 then read", 3'd3, 3'd0, 8'd42, 8'd0);

        // ---- R0 is an ordinary writable register (not hardwired zero) ----
        write_reg(3'd0, 8'd99);
        check_read("R0 is writable (not hardwired zero)", 3'd0, 3'd3, 8'd99, 8'd42);

        // ---- Write disabled (rd_we=0) must not change contents ----
        @(negedge clk);
        rd_addr = 3'd3; rd_wdata = 8'd255; rd_we = 1'b0;
        @(posedge clk);
        @(negedge clk);
        check_read("write with rd_we=0 has no effect", 3'd3, 3'd0, 8'd42, 8'd99);

        // ---- Same address on both read ports ----
        check_read("both read ports same address", 3'd3, 3'd3, 8'd42, 8'd42);

        // ---- Write all 8 registers with distinct values ----
        for (i = 0; i < 8; i = i + 1)
            write_reg(i[2:0], (i * 8'd11) + 1);
        check_read("all-regs sweep: R1 vs R6", 3'd1, 3'd6, (8'd1*8'd11)+1, (8'd6*8'd11)+1);
        check_read("all-regs sweep: R0 vs R7", 3'd0, 3'd7, (8'd0*8'd11)+1, (8'd7*8'd11)+1);

        // ---- Read-during-write: async read sees OLD value on the write cycle ----
        @(negedge clk);
        rd_addr  = 3'd2;
        rd_wdata = 8'd200;
        rd_we    = 1'b1;
        rs1_addr = 3'd2;
        rs2_addr = 3'd2;
        #1; // still before the posedge that commits the write
        tests = tests + 1;
        if (rs1_rdata !== ((8'd2*8'd11)+1)) begin
            errors = errors + 1;
            $display("FAIL [read-during-write sees old value]: got %0d, expected %0d",
                rs1_rdata, (8'd2*8'd11)+1);
        end else begin
            $display("PASS [read-during-write sees old value]: got %0d", rs1_rdata);
        end
        @(posedge clk); // write commits now
        @(negedge clk);
        rd_we = 1'b0;
        check_read("read-after-write sees NEW value next cycle", 3'd2, 3'd0, 8'd200, (8'd0*8'd11)+1);

        // ---- Reset again mid-run clears everything ----
        rst_n = 0;
        @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        check_read("second reset clears R2/R6", 3'd2, 3'd6, 8'd0, 8'd0);

        // ---- Summary ----
        if (errors == 0)
            $display("\nALL %0d TESTS PASSED", tests);
        else
            $display("\n%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule