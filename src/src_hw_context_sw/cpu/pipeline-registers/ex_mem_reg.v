// -----------------------------------------------------------------------
// ex_mem_reg.v
// EX/MEM pipeline register. Carries the ALU result, the store data
// (rs2_rdata), the SP-relative address, ext_value (still needed at WB
// for LDI), and the control signals MEM/WB need.
// -----------------------------------------------------------------------
module ex_mem_reg (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] alu_result_in,
    input  wire [7:0] rs2_rdata_in,     // store data (SW/STORESP)
    input  wire [7:0] ext_value_in,     // passthrough, needed at WB for LDI
    input  wire [7:0] sp_addr_out_in,
    input  wire [2:0] rd_addr_in,

    input  wire       dmem_addr_sel_in,
    input  wire       dmem_we_in,
    input  wire       dmem_re_in,
    input  wire [1:0] wb_sel_in,
    input  wire       rd_we_in,
    input  wire [7:0] lr_value_in,

    output reg  [7:0] alu_result_out, // alu's output
    output reg  [7:0] rs2_rdata_out, // data to be written to the data mem
    output reg  [7:0] ext_value_out, // output of sign ext unit
    output reg  [7:0] sp_addr_out_out, //sp_addr_out port
    output reg  [2:0] rd_addr_out, // stores the destination register to be selected for write back

    output reg        dmem_addr_sel_out, //data memory address line selection
    output reg        dmem_we_out, // write enable for dmem
    output reg        dmem_re_out, // read enable for dmem
    output reg  [1:0] wb_sel_out, // select line for mux selecting what to write back ot reg file
    output reg        rd_we_out, // whetehr to allow write back (goes to reg bank)
    output reg  [7:0] lr_value_out // stores lr or sp value.
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_result_out    <= 8'h00;
            rs2_rdata_out     <= 8'h00;
            ext_value_out     <= 8'h00;
            sp_addr_out_out   <= 8'h00;
            rd_addr_out       <= 3'h0;
            dmem_addr_sel_out <= 1'b0;
            dmem_we_out       <= 1'b0;
            dmem_re_out       <= 1'b0;
            wb_sel_out        <= 2'b00;
            rd_we_out         <= 1'b0;
            lr_value_out      <= 1'b0; 
        end else begin
            alu_result_out    <= alu_result_in;
            rs2_rdata_out     <= rs2_rdata_in;
            ext_value_out     <= ext_value_in;
            sp_addr_out_out   <= sp_addr_out_in;
            rd_addr_out       <= rd_addr_in;
            dmem_addr_sel_out <= dmem_addr_sel_in;
            dmem_we_out       <= dmem_we_in;
            dmem_re_out       <= dmem_re_in;
            wb_sel_out        <= wb_sel_in;
            rd_we_out         <= rd_we_in;
            lr_value_out      <= lr_value_in;
        end
    end
endmodule