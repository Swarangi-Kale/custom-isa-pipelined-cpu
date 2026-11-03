// forwarding_unit.v
// -----------------------------------------------------------------------
// EX/MEM->EX and MEM/WB->EX forwarding, for both ALU operands. Pure
// control (selects only) - the actual value muxing happens at the top
// level, same convention as control_unit's own selects.
//
// One shared pair of selects (forward_a_sel for rs1, forward_b_sel for
// rs2) covers BOTH the ALU-operand path and the store-value path: at the
// top level, the corrected rs1/rs2 values are computed once, upstream of
// wherever they fan out to (ALU-B mux input, and the value later riding
// into EX/MEM for a store) - so this unit doesn't need separate awareness
// of "is this instruction a store." See processor context notes.
//
// Priority: EX/MEM (distance 1, the more recent) wins over MEM/WB
// (distance 2) when both would apply to the same register - always
// forward the freshest available value.
//
// No R0 special-casing: this ISA never hardwires a register to zero.
//
// Correctness of this unit depends on an invariant enforced by the
// Hazard Detection Unit, not by anything in here: a pending load
// (dmem_re asserted, result not yet in dmem_rdata) is never the EX/MEM-
// stage producer for a consumer that needs it at distance 1 - the HDU's
// stall guarantees that case never reaches this unit in the first place.
// -----------------------------------------------------------------------

module forwarding_unit (
    input  wire [2:0] ex_rs1_addr,
    input  wire [2:0] ex_rs2_addr,

    input  wire [2:0] mem_rd_addr,
    input  wire       mem_rd_we,

    input  wire [2:0] wb_rd_addr,
    input  wire       wb_rd_we,

    output reg  [1:0] forward_a_sel,   // 00=no forward 01=EX/MEM 10=MEM/WB
    output reg  [1:0] forward_b_sel
);

    always @(*) begin
        if (mem_rd_we && (mem_rd_addr != 3'b000) && (mem_rd_addr == ex_rs1_addr))
            forward_a_sel = 2'b01;
        else if (wb_rd_we && (wb_rd_addr != 3'b000) && (wb_rd_addr == ex_rs1_addr))
            forward_a_sel = 2'b10;
        else
            forward_a_sel = 2'b00;

        if (mem_rd_we && (mem_rd_addr != 3'b000) && (mem_rd_addr == ex_rs2_addr))
            forward_b_sel = 2'b01;
        else if (wb_rd_we && (wb_rd_addr != 3'b000) && (wb_rd_addr == ex_rs2_addr))
            forward_b_sel = 2'b10;
        else
            forward_b_sel = 2'b00;
    end

endmodule