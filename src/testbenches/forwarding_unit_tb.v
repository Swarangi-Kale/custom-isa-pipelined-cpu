// forwarding_unit_tb.v
// -----------------------------------------------------------------------
// Self-checking testbench for forwarding_unit.v. Covers no-hazard,
// EX/MEM-distance forwarding, MEM/WB-distance forwarding, EX/MEM
// priority over MEM/WB when both match, and independence of the a/b
// (rs1/rs2) select paths.
//
// Run with Icarus:
//   iverilog -o fwd_sim forwarding_unit.v forwarding_unit_tb.v
//   vvp fwd_sim
// -----------------------------------------------------------------------

`timescale 1ns/1ps

module forwarding_unit_tb;

    reg  [2:0] ex_rs1_addr, ex_rs2_addr;
    reg  [2:0] mem_rd_addr;
    reg        mem_rd_we;
    reg  [2:0] wb_rd_addr;
    reg        wb_rd_we;
    wire [1:0] forward_a_sel, forward_b_sel;

    integer errors = 0;
    integer tests  = 0;

    forwarding_unit dut (
        .ex_rs1_addr   (ex_rs1_addr),
        .ex_rs2_addr   (ex_rs2_addr),
        .mem_rd_addr   (mem_rd_addr),
        .mem_rd_we     (mem_rd_we),
        .wb_rd_addr    (wb_rd_addr),
        .wb_rd_we      (wb_rd_we),
        .forward_a_sel (forward_a_sel),
        .forward_b_sel (forward_b_sel)
    );

    task check;
        input [127:0] name;
        input [1:0]   exp_a;
        input [1:0]   exp_b;
        begin
            tests = tests + 1;
            #1;
            if (forward_a_sel !== exp_a || forward_b_sel !== exp_b) begin
                errors = errors + 1;
                $display("FAIL [%0s]: a=%b b=%b, expected a=%b b=%b", name, forward_a_sel, forward_b_sel, exp_a, exp_b);
            end else begin
                $display("PASS [%0s]: a=%b b=%b", name, forward_a_sel, forward_b_sel);
            end
        end
    endtask

    initial begin
        // ---- No hazard at all ----
        ex_rs1_addr=3'd1; ex_rs2_addr=3'd2; mem_rd_addr=3'd5; mem_rd_we=0; wb_rd_addr=3'd6; wb_rd_we=0;
        check("no producers writing anything", 2'b00, 2'b00);

        // ---- EX/MEM forwards to rs1 only ----
        ex_rs1_addr=3'd3; ex_rs2_addr=3'd2; mem_rd_addr=3'd3; mem_rd_we=1; wb_rd_addr=3'd6; wb_rd_we=0;
        check("EX/MEM matches rs1 only", 2'b01, 2'b00);

        // ---- EX/MEM forwards to rs2 only ----
        ex_rs1_addr=3'd1; ex_rs2_addr=3'd4; mem_rd_addr=3'd4; mem_rd_we=1; wb_rd_addr=3'd6; wb_rd_we=0;
        check("EX/MEM matches rs2 only", 2'b00, 2'b01);

        // ---- MEM/WB forwards to rs1 (no EX/MEM match) ----
        ex_rs1_addr=3'd7; ex_rs2_addr=3'd2; mem_rd_addr=3'd3; mem_rd_we=1; wb_rd_addr=3'd7; wb_rd_we=1;
        check("MEM/WB matches rs1, EX/MEM doesn't", 2'b10, 2'b00);

        // ---- Both EX/MEM and MEM/WB match rs1 -> EX/MEM (more recent) wins ----
        ex_rs1_addr=3'd5; ex_rs2_addr=3'd2; mem_rd_addr=3'd5; mem_rd_we=1; wb_rd_addr=3'd5; wb_rd_we=1;
        check("EX/MEM priority over MEM/WB on same register", 2'b01, 2'b00);

        // ---- mem_rd_we=0 must not forward even if addresses match ----
        ex_rs1_addr=3'd5; ex_rs2_addr=3'd2; mem_rd_addr=3'd5; mem_rd_we=0; wb_rd_addr=3'd6; wb_rd_we=0;
        check("mem_rd_we=0 suppresses EX/MEM forward despite addr match", 2'b00, 2'b00);

        // ---- wb_rd_we=0 must not forward even if addresses match ----
        ex_rs1_addr=3'd5; ex_rs2_addr=3'd2; mem_rd_addr=3'd1; mem_rd_we=1; wb_rd_addr=3'd5; wb_rd_we=0;
        check("wb_rd_we=0 suppresses MEM/WB forward despite addr match", 2'b00, 2'b00);

        // ---- Both rs1 and rs2 forwarded simultaneously, from different sources ----
        ex_rs1_addr=3'd2; ex_rs2_addr=3'd3; mem_rd_addr=3'd2; mem_rd_we=1; wb_rd_addr=3'd3; wb_rd_we=1;
        check("independent simultaneous forwards: rs1<-EX/MEM, rs2<-MEM/WB", 2'b01, 2'b10);

        // ---- Summary ----
        if (errors == 0)
            $display("\nALL %0d TESTS PASSED", tests);
        else
            $display("\n%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule