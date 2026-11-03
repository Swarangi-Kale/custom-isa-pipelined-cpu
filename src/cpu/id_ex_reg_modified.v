// id_ex_reg_modified.v (MODIFIED - adds flush/bubble input, adds rs1_addr/rs2_addr
// passthrough)
// -----------------------------------------------------------------------
// ID/EX pipeline register. Two changes from the original single-cycle-
// derived version:
//
//   1. New `flush` input: when asserted, every control-enable field
//      (rd_we, dmem_we, dmem_re, sp_we, flags_we, br_type,
//      shadow_restore, gie_set) is forced to its inert value instead of
//      the real decoded value, creating a bubble. One shared input
//      serves BOTH triggers that need this - branch misprediction
//      (ex_pc_redirect) and a load-use stall (hazard_detection_unit.stall)
//      - ORed together at the top level before reaching this port. This
//      module doesn't need to know or care which trigger caused it.
//      Data fields (pc, rs1_rdata, etc.) are zeroed too on a bubble for
//      simulation cleanliness, though nothing downstream acts on them
//      once every enable is 0.
//
//   2. New rs1_addr_in/out and rs2_addr_in/out: the Forwarding Unit
//      compares register ADDRESSES, not values, so the ID-stage source
//      register indices (rs2_addr_in is the ALREADY-MUXED rs2 position)
//      need to ride alongside the data into EX.
// -----------------------------------------------------------------------
module id_ex_reg_modified (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       flush,

    input  wire [7:0] pc_in,             // for branch_target_adder in EX
    input  wire [7:0] rs1_rdata_in,
    input  wire [7:0] rs2_rdata_in,
    input  wire [7:0] ext_value_in,
    input  wire [2:0] rd_addr_in,
    input  wire [2:0] rs1_addr_in,       // NEW - for forwarding_unit
    input  wire [2:0] rs2_addr_in,       // NEW - already-muxed rs2 position

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
    input  wire       lr_we_in,

    output reg  [7:0] pc_out,
    output reg  [7:0] rs1_rdata_out,
    output reg  [7:0] rs2_rdata_out,
    output reg  [7:0] ext_value_out,
    output reg  [2:0] rd_addr_out,
    output reg  [2:0] rs1_addr_out,      // NEW
    output reg  [2:0] rs2_addr_out,      // NEW

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
    output reg        gie_set_out,
    output reg        lr_we_out,
    
    input  wire spec_sel_in,      output reg spec_sel_out,
    input  wire sp_direct_we_in,  output reg sp_direct_we_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            pc_out             <= 8'h00;
            rs1_rdata_out      <= 8'h00;
            rs2_rdata_out      <= 8'h00;
            ext_value_out      <= 8'h00;
            rd_addr_out        <= 3'h0;
            rs1_addr_out       <= 3'h0;
            rs2_addr_out       <= 3'h0;
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
            lr_we_out <= 1'b0;
            spec_sel_out <= 1'b0;
            sp_direct_we_out <= 1'b0;
        end else begin
            pc_out             <= pc_in;
            rs1_rdata_out      <= rs1_rdata_in;
            rs2_rdata_out      <= rs2_rdata_in;
            ext_value_out      <= ext_value_in;
            rd_addr_out        <= rd_addr_in;
            rs1_addr_out       <= rs1_addr_in;
            rs2_addr_out       <= rs2_addr_in;
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
            lr_we_out <= lr_we_in;
            spec_sel_out <= spec_sel_in;
            sp_direct_we_out <= sp_direct_we_in;
        end
    end
endmodule