// data_memory_tb.v
// -----------------------------------------------------------------------
// Self-checking testbench for data_memory.v. Covers reset, write+read,
// we=0 no-write, re=0 gating rdata to 0 (without disturbing stored data),
// read-during-write timing, and multiple distinct addresses.
//
// Run with Icarus:
//   iverilog -o dmem_sim data_memory.v data_memory_tb.v
//   vvp dmem_sim
// -----------------------------------------------------------------------

`timescale 1ns/1ps

module data_memory_tb;

    reg        clk;
    reg        rst_n;
    reg  [7:0] addr;
    reg  [7:0] wdata;
    reg        we, re;
    wire [7:0] rdata;

    integer errors = 0;
    integer tests  = 0;

    data_memory #(.MEM_DEPTH(256)) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (addr),
        .wdata (wdata),
        .we    (we),
        .re    (re),
        .rdata (rdata)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [127:0] name;
        input [7:0]   exp_rdata;
        begin
            tests = tests + 1;
            #1;
            if (rdata !== exp_rdata) begin
                errors = errors + 1;
                $display("FAIL [%0s]: addr=%0d rdata=%0d, expected %0d", name, addr, rdata, exp_rdata);
            end else begin
                $display("PASS [%0s]: addr=%0d rdata=%0d", name, addr, rdata);
            end
        end
    endtask

    task write_mem;
        input [7:0] a;
        input [7:0] d;
        begin
            @(negedge clk);
            addr  = a;
            wdata = d;
            we    = 1'b1;
            @(posedge clk);
            @(negedge clk);
            we    = 1'b0;
        end
    endtask

    initial begin
        rst_n = 0;
        addr  = 0; wdata = 0; we = 0; re = 0;

        // ---- Reset: memory reads back 0 ----
        @(negedge clk); @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        addr = 8'd0; re = 1'b1;
        check("post-reset addr 0 reads 0", 8'd0);

        addr = 8'd255;
        check("post-reset addr 255 reads 0", 8'd0);

        // ---- Basic write then read ----
        re = 0;
        write_mem(8'd10, 8'd77);
        addr = 8'd10; re = 1'b1;
        check("write addr10=77 then read", 8'd77);

        // ---- we=0 must not modify contents ----
        re = 0;
        @(negedge clk);
        addr = 8'd10; wdata = 8'd200; we = 1'b0;
        @(posedge clk); @(negedge clk);
        addr = 8'd10; re = 1'b1;
        check("we=0 leaves addr10 unchanged at 77", 8'd77);

        // ---- re=0 gates rdata to 0, without disturbing stored data ----
        re = 0;
        check("re=0 gates rdata to 0 (data still safe underneath)", 8'd0);
        re = 1'b1;
        check("re=1 again shows the real stored value (77)", 8'd77);

        // ---- Multiple distinct addresses ----
        re = 0;
        write_mem(8'd20, 8'd5);
        write_mem(8'd21, 8'd6);
        addr = 8'd20; re = 1'b1;
        check("addr20=5", 8'd5);
        addr = 8'd21;
        check("addr21=6", 8'd6);
        addr = 8'd10;
        check("addr10 still 77 (unaffected by other writes)", 8'd77);

        // ---- Read-during-write: async read sees OLD value on the write cycle ----
        re = 1;
        @(negedge clk);
        addr  = 8'd20;
        wdata = 8'd99;
        we    = 1'b1;
        #1; // before the posedge that commits the write
        tests = tests + 1;
        if (rdata !== 8'd5) begin
            errors = errors + 1;
            $display("FAIL [read-during-write sees old value]: got %0d, expected 5", rdata);
        end else begin
            $display("PASS [read-during-write sees old value]: got %0d", rdata);
        end
        @(posedge clk); // write commits now
        @(negedge clk);
        we = 1'b0;
        check("read-after-write sees NEW value next cycle", 8'd99);

        // ---- Mid-run reset clears everything ----
        rst_n = 0;
        @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        addr = 8'd20;
        check("mid-run reset clears addr20 back to 0", 8'd0);
        addr = 8'd21;
        check("mid-run reset clears addr21 back to 0", 8'd0);

        // ---- Summary ----
        if (errors == 0)
            $display("\nALL %0d TESTS PASSED", tests);
        else
            $display("\n%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule