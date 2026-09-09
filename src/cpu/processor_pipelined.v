// -----------------------------------------------------------------------
// processor_pipelined.v (PIPELINED - Phase 2)
//
// 5-stage pipeline: IF - ID - EX - MEM - WB, built by inserting the four
// pipeline registers (if_id_reg, id_ex_reg, ex_mem_reg, mem_wb_reg)
// between the same combinational blocks used in the single-cycle build.
// None of the functional modules (alu, register_file, control_unit's
// decode logic, muxes, etc.) became sequential - they are exactly as
// combinational as before. Only the boundaries between stages are new.
//
// DELIBERATELY NOT INCLUDED (per current phase scope):
//   - Hazard Detection Unit: no stalling. pc_write_en is tied high, same
//     as the single-cycle build.
//   - Forwarding Unit: no EX/MEM->EX or MEM/WB->EX bypass paths.
//   - Branch/jump flush: control-flow instructions resolve in EX, i.e.
//     2 cycles after they're fetched. The 2 instructions fetched in the
//     meantime are NOT flushed - they flow through the pipe and, if they
//     are anything other than harmless (e.g. NOP), their effects WILL
//     commit. Any program run on this datapath must place 2 NOPs (or
//     otherwise-harmless instructions) after every branch/jump/RETI, and
//     must not rely on register results without enough spacing to
//     survive the lack of forwarding (see processor_tb.v for the
//     required spacing rules).
//
// KEY DESIGN DECISIONS forced by pipelining (see chat for full reasoning):
//   - control_unit no longer resolves pc_redirect itself (needs flag_z,
//     which isn't known in ID). It emits br_type; final pc_redirect is
//     computed combinationally in the EX stage below, using this cycle's
//     live alu_flag_z together with br_type pipelined in via ID/EX.
//   - sp_unit and flags_register and gie_register are driven directly off
//     ID/EX-stage (i.e. "EX-stage") signals, the same way the ALU is -
//     they update on the same edge the ALU's result is captured into
//     EX/MEM, not deferred all the way to WB.
// -----------------------------------------------------------------------
module processor_pipelined (
    input wire clk,
    input wire rst_n
);

    // =================================================================
    // IF stage
    // =================================================================
    wire [7:0]  pc_out;
    wire [15:0] instr_if;

    wire        ex_pc_redirect;      // computed in EX (below), fed back here
    wire [7:0]  ex_pc_redirect_addr;

    pc_register u_pc (
        .clk              (clk),
        .rst_n            (rst_n),
        .pc_write_en      (1'b1),               // no HDU yet - never stalls
        .pc_redirect      (ex_pc_redirect),
        .pc_redirect_addr (ex_pc_redirect_addr),
        .pc_out           (pc_out)
    );

    instr_mem #(.INIT_FILE("")) u_imem (
        .addr      (pc_out),
        .instr_out (instr_if)
    );

    // ---- IF/ID pipeline register ----
    wire [15:0] id_instr;
    wire [7:0]  id_pc;

    if_id_reg u_if_id (
        .clk       (clk),
        .rst_n     (rst_n),
        .instr_in  (instr_if),
        .pc_in     (pc_out),
        .instr_out (id_instr),
        .pc_out    (id_pc)
    );

    // =================================================================
    // ID stage
    // =================================================================
    wire [3:0] id_opcode  = id_instr[15:12];
    wire [2:0] id_funct   = id_instr[2:0];
    wire [2:0] id_rd_addr = id_instr[11:9];
    wire [2:0] id_rs1_addr = id_instr[8:6];

    wire [2:0] c_alu_funct;
    wire       c_alu_src_b_sel;
    wire       c_rs2_addr_sel;
    wire [1:0] c_wb_sel;
    wire       c_dmem_addr_sel;
    wire       c_dmem_we;
    wire       c_dmem_re;
    wire       c_rd_we;
    wire       c_flags_we;
    wire       c_sp_we;
    wire [2:0] c_format_sel;
    wire [1:0] c_br_type;
    wire [1:0] c_pc_target_sel;
    wire       c_shadow_restore;
    wire       c_gie_set;
    wire       c_lr_we;        // unused
    wire       c_shadow_save;  // unused

    control_unit_pipelined u_ctrl (
        .opcode         (id_opcode),
        .funct          (id_funct),
        .alu_funct      (c_alu_funct),
        .alu_src_b_sel  (c_alu_src_b_sel),
        .rs2_addr_sel   (c_rs2_addr_sel),
        .wb_sel         (c_wb_sel),
        .dmem_addr_sel  (c_dmem_addr_sel),
        .dmem_we        (c_dmem_we),
        .dmem_re        (c_dmem_re),
        .rd_we          (c_rd_we),
        .flags_we       (c_flags_we),
        .sp_we          (c_sp_we),
        .format_sel     (c_format_sel),
        .br_type        (c_br_type),
        .pc_target_sel  (c_pc_target_sel),
        .shadow_restore (c_shadow_restore),
        .gie_set        (c_gie_set),
        .lr_we          (c_lr_we),
        .shadow_save    (c_shadow_save)
    );

    wire [7:0] id_ext_value;
    sign_extension_unit u_seu (
        .instr      (id_instr),
        .format_sel (c_format_sel),
        .ext_value  (id_ext_value)
    );

    wire [2:0] id_rs2_addr_muxed;
    mux2to1 #(.WIDTH(3)) u_mux_rs2addr (
        .sel (c_rs2_addr_sel),
        .in0 (id_instr[5:3]),
        .in1 (id_instr[11:9]),
        .out (id_rs2_addr_muxed)
    );

    // Register file: read ports driven by ID stage; write port driven by WB stage
    wire [7:0] id_rs1_rdata, id_rs2_rdata;
    wire [7:0] wb_wdata;
    wire [2:0] wb_rd_addr;
    wire       wb_rd_we;

    reg_bank u_rf (
        .clk       (clk),
        .rst_n     (rst_n),
        .rs1_addr  (id_rs1_addr),
        .rs2_addr  (id_rs2_addr_muxed),
        .rs1_rdata (id_rs1_rdata),
        .rs2_rdata (id_rs2_rdata),
        .rd_addr   (wb_rd_addr),
        .rd_wdata  (wb_wdata),
        .rd_we     (wb_rd_we)
    );

    // ---- ID/EX pipeline register ----
    wire [7:0] ex_pc, ex_rs1_rdata, ex_rs2_rdata, ex_ext_value;
    wire [2:0] ex_rd_addr;
    wire [2:0] ex_alu_funct;
    wire       ex_alu_src_b_sel;
    wire       ex_dmem_addr_sel, ex_dmem_we, ex_dmem_re;
    wire       ex_sp_we, ex_flags_we;
    wire [1:0] ex_wb_sel;
    wire       ex_rd_we;
    wire [1:0] ex_br_type;
    wire [1:0] ex_pc_target_sel;
    wire       ex_shadow_restore, ex_gie_set;

    id_ex_reg u_id_ex (
        .clk               (clk),
        .rst_n             (rst_n),
        .pc_in             (id_pc),
        .rs1_rdata_in      (id_rs1_rdata),
        .rs2_rdata_in      (id_rs2_rdata),
        .ext_value_in      (id_ext_value),
        .rd_addr_in        (id_rd_addr),
        .alu_funct_in      (c_alu_funct),
        .alu_src_b_sel_in  (c_alu_src_b_sel),
        .dmem_addr_sel_in  (c_dmem_addr_sel),
        .dmem_we_in        (c_dmem_we),
        .dmem_re_in        (c_dmem_re),
        .sp_we_in          (c_sp_we),
        .flags_we_in       (c_flags_we),
        .wb_sel_in         (c_wb_sel),
        .rd_we_in          (c_rd_we),
        .br_type_in        (c_br_type),
        .pc_target_sel_in  (c_pc_target_sel),
        .shadow_restore_in (c_shadow_restore),
        .gie_set_in        (c_gie_set),

        .pc_out             (ex_pc),
        .rs1_rdata_out      (ex_rs1_rdata),
        .rs2_rdata_out      (ex_rs2_rdata),
        .ext_value_out      (ex_ext_value),
        .rd_addr_out        (ex_rd_addr),
        .alu_funct_out      (ex_alu_funct),
        .alu_src_b_sel_out  (ex_alu_src_b_sel),
        .dmem_addr_sel_out  (ex_dmem_addr_sel),
        .dmem_we_out        (ex_dmem_we),
        .dmem_re_out        (ex_dmem_re),
        .sp_we_out          (ex_sp_we),
        .flags_we_out       (ex_flags_we),
        .wb_sel_out         (ex_wb_sel),
        .rd_we_out          (ex_rd_we),
        .br_type_out        (ex_br_type),
        .pc_target_sel_out  (ex_pc_target_sel),
        .shadow_restore_out (ex_shadow_restore),
        .gie_set_out        (ex_gie_set)
    );

    // =================================================================
    // EX stage
    // =================================================================
    wire [7:0] ex_alu_in_b;
    mux2to1 #(.WIDTH(8)) u_mux_alu_b (
        .sel (ex_alu_src_b_sel),
        .in0 (ex_rs2_rdata),
        .in1 (ex_ext_value),
        .out (ex_alu_in_b)
    );

    wire [7:0] ex_alu_result;
    wire       ex_alu_flag_z, ex_alu_flag_c, ex_alu_flag_n;

    alu u_alu (
        .alu_in_a   (ex_rs1_rdata),
        .alu_in_b   (ex_alu_in_b),
        .alu_funct  (ex_alu_funct),
        .alu_result (ex_alu_result),
        .flag_z     (ex_alu_flag_z),
        .flag_c     (ex_alu_flag_c),
        .flag_n     (ex_alu_flag_n)
    );

    // SP Unit - fires here, same latency class as the ALU (see header notes)
    wire [7:0] ex_sp_out, ex_sp_addr_out;
    sp_unit u_sp (
        .clk         (clk),
        .rst_n       (rst_n),
        .sp_we       (ex_sp_we),
        .sp_addend   (ex_ext_value),
        .sp_out      (ex_sp_out),
        .sp_addr_out (ex_sp_addr_out)
    );

    // LR Register (inert - no interrupt-entry hardware yet)
    wire [7:0] lr_out;
    lr_reg u_lr (
        .clk      (clk),
        .rst_n    (rst_n),
        .lr_we    (1'b0),
        .lr_wdata (8'b0),
        .lr_out   (lr_out)
    );

    // Flags Register - fires here too, driven by this cycle's live ALU flags
    wire flag_z, flag_c, flag_n; // committed flags (unused elsewhere on this datapath)
    flags_reg u_flags (
        .clk            (clk),
        .rst_n          (rst_n),
        .flags_we       (ex_flags_we),
        .alu_z          (ex_alu_flag_z),
        .alu_c          (ex_alu_flag_c),
        .alu_n          (ex_alu_flag_n),
        .shadow_save    (1'b0),
        .shadow_restore (ex_shadow_restore),
        .flag_z         (flag_z),
        .flag_c         (flag_c),
        .flag_n         (flag_n),
        .shadow_z       (),
        .shadow_c       (),
        .shadow_n       ()
    );

    // GIE Register
    wire gie_out;
    gie_reg u_gie (
        .clk       (clk),
        .rst_n     (rst_n),
        .gie_set   (ex_gie_set),
        .gie_clear (1'b0),
        .gie_out   (gie_out)
    );

    // Branch target adder
    wire [7:0] ex_branch_target;
    simple_adder u_bta (
        .pc_in         (ex_pc),
        .offset        (ex_ext_value),
        .branch_target (ex_branch_target)
    );

    // Mux 5 - PC redirect target (still resolved in EX)
    mux4to1 #(.WIDTH(8)) u_mux_pc_target (
        .sel (ex_pc_target_sel),
        .in0 (ex_branch_target),
        .in1 (ex_ext_value),   // JMP
        .in2 (lr_out),         // RETI
        .in3 (8'b0),
        .out (ex_pc_redirect_addr)
    );

    // Branch/jump resolution: only place br_type meets the live ALU flag
    assign ex_pc_redirect = (ex_br_type == 2'b01 &&  ex_alu_flag_z) ||  // BEQ taken
                             (ex_br_type == 2'b10 && !ex_alu_flag_z) ||  // BNE taken
                             (ex_br_type == 2'b11);                     // JMP/RETI

    // ---- EX/MEM pipeline register ----
    wire [7:0] mem_alu_result, mem_rs2_rdata, mem_ext_value, mem_sp_addr_out;
    wire [2:0] mem_rd_addr;
    wire       mem_dmem_addr_sel, mem_dmem_we, mem_dmem_re;
    wire [1:0] mem_wb_sel;
    wire       mem_rd_we;

    ex_mem_reg u_ex_mem (
        .clk               (clk),
        .rst_n             (rst_n),
        .alu_result_in     (ex_alu_result),
        .rs2_rdata_in      (ex_rs2_rdata),
        .ext_value_in      (ex_ext_value),
        .sp_addr_out_in    (ex_sp_addr_out),
        .rd_addr_in        (ex_rd_addr),
        .dmem_addr_sel_in  (ex_dmem_addr_sel),
        .dmem_we_in        (ex_dmem_we),
        .dmem_re_in        (ex_dmem_re),
        .wb_sel_in         (ex_wb_sel),
        .rd_we_in          (ex_rd_we),

        .alu_result_out    (mem_alu_result),
        .rs2_rdata_out     (mem_rs2_rdata),
        .ext_value_out     (mem_ext_value),
        .sp_addr_out_out   (mem_sp_addr_out),
        .rd_addr_out       (mem_rd_addr),
        .dmem_addr_sel_out (mem_dmem_addr_sel),
        .dmem_we_out       (mem_dmem_we),
        .dmem_re_out       (mem_dmem_re),
        .wb_sel_out        (mem_wb_sel),
        .rd_we_out         (mem_rd_we)
    );

    // =================================================================
    // MEM stage
    // =================================================================
    wire [7:0] mem_dmem_addr;
    mux2to1 #(.WIDTH(8)) u_mux_dmem_addr (
        .sel (mem_dmem_addr_sel),
        .in0 (mem_alu_result),
        .in1 (mem_sp_addr_out),
        .out (mem_dmem_addr)
    );

    wire [7:0] mem_dmem_rdata;
    data_memory u_dmem (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (mem_dmem_addr),
        .wdata (mem_rs2_rdata),
        .we    (mem_dmem_we),
        .re    (mem_dmem_re),
        .rdata (mem_dmem_rdata)
    );

    // ---- MEM/WB pipeline register ----
    wire [7:0] wbstage_dmem_rdata, wbstage_alu_result, wbstage_ext_value;
    wire [1:0] wbstage_wb_sel;

    mem_wb_reg u_mem_wb (
        .clk            (clk),
        .rst_n          (rst_n),
        .dmem_rdata_in  (mem_dmem_rdata),
        .alu_result_in  (mem_alu_result),
        .ext_value_in   (mem_ext_value),
        .rd_addr_in     (mem_rd_addr),
        .rd_we_in       (mem_rd_we),
        .wb_sel_in      (mem_wb_sel),

        .dmem_rdata_out (wbstage_dmem_rdata),
        .alu_result_out (wbstage_alu_result),
        .ext_value_out  (wbstage_ext_value),
        .rd_addr_out    (wb_rd_addr),
        .rd_we_out      (wb_rd_we),
        .wb_sel_out     (wbstage_wb_sel)
    );

    // =================================================================
    // WB stage
    // =================================================================
    mux4to1 #(.WIDTH(8)) u_mux_wb (
        .sel (wbstage_wb_sel),
        .in0 (wbstage_alu_result),
        .in1 (wbstage_dmem_rdata),
        .in2 (wbstage_ext_value),
        .in3 (8'b0),
        .out (wb_wdata)
    );
    // wb_wdata, wb_rd_addr, wb_rd_we feed register_file's write port (declared above)

endmodule