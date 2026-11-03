// if_id_reg_modified.v (MODIFIED - adds stall and flush)
// -----------------------------------------------------------------------
// IF/ID pipeline register. Two new control inputs beyond the original
// single-cycle-derived version:
//
//   stall - load-use hazard (from hazard_detection_unit): HOLD the
//           current instr/pc (do NOT advance to the new fetch). The
//           instruction here is real and just needs to wait one more
//           cycle - it must be preserved, not discarded.
//   flush - branch/jump/RETI resolved taken in EX (from
//           ex_pc_redirect): DISCARD whatever was just fetched (it came
//           from the wrong path) and replace it with the NOP encoding.
//
// Priority: flush > stall > normal capture. If both happen to be true
// the same cycle, the currently-fetched instruction is wrong-path
// anyway, so there's no point holding it - discard wins.
// -----------------------------------------------------------------------
module if_id_reg_modified (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    input  wire [15:0] instr_in,
    input  wire [7:0]  pc_in,
    output reg  [15:0] instr_out,
    output reg  [7:0]  pc_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            instr_out <= 16'h0000;
            pc_out    <= 8'h00;
        end else if (flush) begin
            instr_out <= 16'h0000;   // NOP encoding (opcode 0000, funct 000)
            pc_out    <= 8'h00;
        end else if (stall) begin
            instr_out <= instr_out;  // hold
            pc_out    <= pc_out;     // hold
        end else begin
            instr_out <= instr_in;
            pc_out    <= pc_in;
        end
    end
endmodule