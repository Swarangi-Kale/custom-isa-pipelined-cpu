// -----------------------------------------------------------------------
// mem_wb_reg.v
// MEM/WB pipeline register. Carries everything the WB-stage write-back
// mux and the register-file write port need.
// -----------------------------------------------------------------------
module mem_wb_reg (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] dmem_rdata_in,
    input  wire [7:0] alu_result_in,
    input  wire [7:0] ext_value_in,
    input  wire [2:0] rd_addr_in,
    input  wire       rd_we_in,
    input  wire [1:0] wb_sel_in,

    output reg  [7:0] dmem_rdata_out,
    output reg  [7:0] alu_result_out,
    output reg  [7:0] ext_value_out,
    output reg  [2:0] rd_addr_out,
    output reg        rd_we_out,
    output reg  [1:0] wb_sel_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmem_rdata_out <= 8'h00;
            alu_result_out <= 8'h00;
            ext_value_out  <= 8'h00;
            rd_addr_out    <= 3'h0;
            rd_we_out      <= 1'b0;
            wb_sel_out     <= 2'b00;
        end else begin
            dmem_rdata_out <= dmem_rdata_in;
            alu_result_out <= alu_result_in;
            ext_value_out  <= ext_value_in;
            rd_addr_out    <= rd_addr_in;
            rd_we_out      <= rd_we_in;
            wb_sel_out     <= wb_sel_in;
        end
    end
endmodule