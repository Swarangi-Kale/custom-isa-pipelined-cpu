// hazard_detection_unit_tb.v
// -----------------------------------------------------------------------
// Self-checking testbench for hazard_detection_unit.v. Covers a real
// load-use hazard on rs1 and rs2, no hazard when the producer isn't a
// load, no hazard when addresses don't match, and - the important
// negative case - no FALSE trigger on a format (LDI) whose bit positions
// aren't real register reads, even when they numerically coincide with
// the pending load's destination.
//
// Run with Icarus:
//   iverilog -o hdu_sim hazard_detection_unit.v hazard_detection_unit_tb.v
//   vvp hdu_sim
// -----------------------------------------------------------------------

`timescale 1ns/1ps

module hazard_detection_unit_tb;

    reg  [3:0] id_opcode;
    reg  [2:0] id_rs1_addr, id_rs2_addr;
    reg  [2:0] ex_rd_addr;
    reg        ex_dmem_re, ex_rd_we;
    wire       stall;

    integer errors = 0;
    integer tests  = 0;

    hazard_detection_unit dut (
        .id_opcode   (id_opcode),
        .id_rs1_addr (id_rs1_addr),
        .id_rs2_addr (id_rs2_addr),
        .ex_rd_addr  (ex_rd_addr),
        .ex_dmem_re  (ex_dmem_re),
        .ex_rd_we    (ex_rd_we),
        .stall       (stall)
    );

    task check;
        input [127:0] name;
        input         exp;
        begin
            tests = tests + 1;
            #1;
            if (stall !== exp) begin
                errors = errors + 1;
                $display("FAIL [%0s]: stall=%b, expected %b", name, stall, exp);
            end else begin
                $display("PASS [%0s]: stall=%b", name, stall);
            end
        end
    endtask

    initial begin
        // ---- Real load-use on rs1 (R-type consumer) ----
        id_opcode=4'b0000; id_rs1_addr=3'd3; id_rs2_addr=3'd1;
        ex_rd_addr=3'd3; ex_dmem_re=1; ex_rd_we=1;
        check("R-type rs1 matches pending load -> stall", 1'b1);

        // ---- Real load-use on rs2 (STORESP consumer) ----
        id_opcode=4'b1001; id_rs1_addr=3'd1; id_rs2_addr=3'd4;
        ex_rd_addr=3'd4; ex_dmem_re=1; ex_rd_we=1;
        check("STORESP rs2(muxed) matches pending load -> stall", 1'b1);

        // ---- No stall: producer isn't a load (dmem_re=0) ----
        id_opcode=4'b0000; id_rs1_addr=3'd3; id_rs2_addr=3'd1;
        ex_rd_addr=3'd3; ex_dmem_re=0; ex_rd_we=1;
        check("R-type ALU producer (not a load) -> no stall", 1'b0);

        // ---- No stall: rd_we=0 (e.g. STORESP as producer, never writes back) ----
        id_opcode=4'b0000; id_rs1_addr=3'd3; id_rs2_addr=3'd1;
        ex_rd_addr=3'd3; ex_dmem_re=1; ex_rd_we=0;
        check("pending load-like access but rd_we=0 -> no stall", 1'b0);

        // ---- No stall: addresses simply don't match ----
        id_opcode=4'b0000; id_rs1_addr=3'd2; id_rs2_addr=3'd5;
        ex_rd_addr=3'd3; ex_dmem_re=1; ex_rd_we=1;
        check("no address match -> no stall", 1'b0);

        // ---- Critical negative case: LDI's bits aren't rs1/rs2 at all ----
        // id_rs1_addr numerically equals the pending load's destination
        // purely by chance (it's really immediate bits for LDI) - must
        // NOT stall, since LDI doesn't read any register.
        id_opcode=4'b0011; id_rs1_addr=3'd3; id_rs2_addr=3'd1;
        ex_rd_addr=3'd3; ex_dmem_re=1; ex_rd_we=1;
        check("LDI: numeric coincidence must NOT false-trigger", 1'b0);

        // ---- Same negative case for J-type/ADDSP-style opcodes ----
        id_opcode=4'b0110; id_rs1_addr=3'd3; id_rs2_addr=3'd3;
        ex_rd_addr=3'd3; ex_dmem_re=1; ex_rd_we=1;
        check("JMP: no real register read, must NOT stall", 1'b0);

        // ---- BEQ uses both rs1 and rs2(muxed) - hazard on rs2 ----
        id_opcode=4'b0101; id_rs1_addr=3'd1; id_rs2_addr=3'd6;
        ex_rd_addr=3'd6; ex_dmem_re=1; ex_rd_we=1;
        check("BEQ rs2(muxed) matches pending load -> stall", 1'b1);

        // ---- Summary ----
        if (errors == 0)
            $display("\nALL %0d TESTS PASSED", tests);
        else
            $display("\n%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule