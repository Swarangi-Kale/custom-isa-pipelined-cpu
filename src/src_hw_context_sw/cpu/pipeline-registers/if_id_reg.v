// -----------------------------------------------------------------------
// if_id_reg.v
// IF/ID pipeline register. On reset (or any cycle - no HDU yet, so no
// bubble/flush input), captures the fetched instruction and its PC.
// Reset value 0x0000 decodes as a true NOP (see Section 3 of the spec),
// so a freshly-reset pipeline drains as harmless NOPs.
// -----------------------------------------------------------------------
module if_id_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] instr_in,
    input  wire [7:0]  pc_in,
    output reg  [15:0] instr_out,
    output reg  [7:0]  pc_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            instr_out <= 16'h0000;
            pc_out    <= 8'h00;
        end else begin
            instr_out <= instr_in;
            pc_out    <= pc_in;
        end
    end
endmodule