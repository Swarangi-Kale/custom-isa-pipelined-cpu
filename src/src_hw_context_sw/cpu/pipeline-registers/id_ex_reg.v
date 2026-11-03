// -----------------------------------------------------------------------
// id_ex_reg.v
// ID/EX pipeline register. Carries decoded operands plus every control
// signal needed from the EX stage onward (EX itself, and passed further
// via EX/MEM and MEM/WB for the stages after that).
// -----------------------------------------------------------------------
module id_ex_reg (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] pc_in,             // for branch_target_adder in EX
    input  wire [7:0] rs1_rdata_in,
    input  wire [7:0] rs2_rdata_in,
    input  wire [7:0] ext_value_in,
    input  wire [2:0] rd_addr_in,

    input  wire [2:0] alu_funct_in,
    input  wire       alu_src_b_sel_in,
    input  wire       dmem_addr_sel_in,
    input  wire       dmem_we_in,
    input  wire       dmem_re_in,
    input  wire       sp_we_in,
    input  wire       flags_we_in,
    input  wire [1:0] wb_sel_in,
    input  wire       rd_we_in,
    input  wire [1:0] br_type_in,        // 00=none 01=BEQ 10=BNE 11=uncond
    input  wire [1:0] pc_target_sel_in,
    input  wire       shadow_restore_in,
    input  wire       gie_set_in,

    output reg  [7:0] pc_out,
    output reg  [7:0] rs1_rdata_out,
    output reg  [7:0] rs2_rdata_out,
    output reg  [7:0] ext_value_out,
    output reg  [2:0] rd_addr_out,

    output reg  [2:0] alu_funct_out,
    output reg        alu_src_b_sel_out,
    output reg        dmem_addr_sel_out,
    output reg        dmem_we_out,
    output reg        dmem_re_out,
    output reg        sp_we_out,
    output reg        flags_we_out,
    output reg  [1:0] wb_sel_out,
    output reg        rd_we_out,
    output reg  [1:0] br_type_out,
    output reg  [1:0] pc_target_sel_out,
    output reg        shadow_restore_out,
    output reg        gie_set_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out             <= 8'h00;
            rs1_rdata_out      <= 8'h00;
            rs2_rdata_out      <= 8'h00;
            ext_value_out      <= 8'h00;
            rd_addr_out        <= 3'h0;
            alu_funct_out      <= 3'h0;
            alu_src_b_sel_out  <= 1'b0;
            dmem_addr_sel_out  <= 1'b0;
            dmem_we_out        <= 1'b0;
            dmem_re_out        <= 1'b0;
            sp_we_out          <= 1'b0;
            flags_we_out       <= 1'b0;
            wb_sel_out         <= 2'b00;
            rd_we_out          <= 1'b0;
            br_type_out        <= 2'b00;
            pc_target_sel_out  <= 2'b00;
            shadow_restore_out <= 1'b0;
            gie_set_out        <= 1'b0;
        end else begin
            pc_out             <= pc_in;
            rs1_rdata_out      <= rs1_rdata_in;
            rs2_rdata_out      <= rs2_rdata_in;
            ext_value_out      <= ext_value_in;
            rd_addr_out        <= rd_addr_in;
            alu_funct_out      <= alu_funct_in;
            alu_src_b_sel_out  <= alu_src_b_sel_in;
            dmem_addr_sel_out  <= dmem_addr_sel_in;
            dmem_we_out        <= dmem_we_in;
            dmem_re_out        <= dmem_re_in;
            sp_we_out          <= sp_we_in;
            flags_we_out       <= flags_we_in;
            wb_sel_out         <= wb_sel_in;
            rd_we_out          <= rd_we_in;
            br_type_out        <= br_type_in;
            pc_target_sel_out  <= pc_target_sel_in;
            shadow_restore_out <= shadow_restore_in;
            gie_set_out        <= gie_set_in;
        end
    end
endmodule