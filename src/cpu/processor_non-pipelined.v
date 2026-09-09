// -----------------------------------------------------------------------
// processor.v
// Top-level single-cycle datapath for the custom 16-bit-instruction /
// 8-bit-data processor. Instantiates and wires the already-verified
// modules per the control-signal map in processor_context.md, Section 5.
//
// Current phase: single-cycle (no pipeline registers, no hazard/forwarding
// logic). Pipelining, the Hazard Detection Unit, and the Forwarding Unit
// are the next phase and are deliberately not present here.
// -----------------------------------------------------------------------
module processor (
    input wire clk,
    input wire rst_n
);

    // ---------------------------------------------------------------
    // Fetch
    // ---------------------------------------------------------------
    wire [7:0]  pc_out;
    wire [15:0] instr;

    wire [3:0] opcode   = instr[15:12];
    wire [2:0] funct    = instr[2:0];
    wire [2:0] rd_addr  = instr[11:9];  // register-file write address (field-consistent)
    wire [2:0] rs1_addr = instr[8:6];   // register-file read port 1 address

    // ---------------------------------------------------------------
    // Control Unit outputs
    // ---------------------------------------------------------------
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
    wire       c_pc_redirect;
    wire [1:0] c_pc_target_sel;
    wire       c_shadow_restore;
    wire       c_gie_set;
    wire       c_lr_we;         // reserved, unused
    wire       c_shadow_save;   // reserved, unused

    // ---------------------------------------------------------------
    // Datapath internal wires
    // ---------------------------------------------------------------
    wire [7:0] ext_value;
    wire [2:0] rs2_addr_muxed;
    wire [7:0] rs1_rdata, rs2_rdata;
    wire [7:0] alu_in_b;
    wire [7:0] alu_result;
    wire       alu_flag_z, alu_flag_c, alu_flag_n;   // live ALU flags -> Control Unit / Flags reg
    wire       flag_z, flag_c, flag_n;               // committed flags (Flags register)
    wire [7:0] sp_out, sp_addr_out;
    wire [7:0] lr_out;
    wire [7:0] dmem_addr, dmem_rdata;
    wire [7:0] wb_data;
    wire [7:0] branch_target;
    wire [7:0] pc_redirect_addr;
    wire       gie_out;

    // ---------------------------------------------------------------
    // PC / Instruction Fetch
    // ---------------------------------------------------------------
    pc_register u_pc (
        .clk               (clk),
        .rst_n             (rst_n),
        .pc_write_en       (1'b1),           // no Hazard Detection Unit yet - never stalls
        .pc_redirect       (c_pc_redirect),
        .pc_redirect_addr  (pc_redirect_addr),
        .pc_out            (pc_out)
    );

    instr_mem #(
        .INIT_FILE("")
    ) u_imem (
        .addr      (pc_out),
        .instr_out (instr)
    );

    // ---------------------------------------------------------------
    // Control Unit
    // NOTE: flag_z here is the LIVE ALU flag (this cycle's BEQ/BNE
    // comparison result), NOT the committed Flags register output.
    // ---------------------------------------------------------------
    control_unit u_ctrl (
        .opcode         (opcode),
        .funct          (funct),
        .flag_z         (alu_flag_z),
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
        .pc_redirect    (c_pc_redirect),
        .pc_target_sel  (c_pc_target_sel),
        .shadow_restore (c_shadow_restore),
        .gie_set        (c_gie_set),
        .lr_we          (c_lr_we),
        .shadow_save    (c_shadow_save)
    );

    sign_extension_unit u_seu (
        .instr      (instr),
        .format_sel (c_format_sel),
        .ext_value  (ext_value)
    );

    // ---------------------------------------------------------------
    // Mux 1 - register file rs2_addr source
    // ---------------------------------------------------------------
    mux2to1 #(.WIDTH(3)) u_mux_rs2addr (
        .sel (c_rs2_addr_sel),
        .in0 (instr[5:3]),    // R-type rs2
        .in1 (instr[11:9]),   // B-type rs2 / SW & STORESP store-source reg
        .out (rs2_addr_muxed)
    );

    // ---------------------------------------------------------------
    // Register File
    // ---------------------------------------------------------------
    reg_bank u_rf (
        .clk       (clk),
        .rst_n     (rst_n),
        .rs1_addr  (rs1_addr),
        .rs2_addr  (rs2_addr_muxed),
        .rs1_rdata (rs1_rdata),
        .rs2_rdata (rs2_rdata),
        .rd_addr   (rd_addr),
        .rd_wdata  (wb_data),
        .rd_we     (c_rd_we)
    );

    // ---------------------------------------------------------------
    // Mux 2 - ALU operand B
    // ---------------------------------------------------------------
    mux2to1 #(.WIDTH(8)) u_mux_alu_b (
        .sel (c_alu_src_b_sel),
        .in0 (rs2_rdata),
        .in1 (ext_value),
        .out (alu_in_b)
    );

    // ---------------------------------------------------------------
    // ALU  (alu_in_a is always rs1_rdata directly, no mux)
    // ---------------------------------------------------------------
    alu u_alu (
        .alu_in_a   (rs1_rdata),
        .alu_in_b   (alu_in_b),
        .alu_funct  (c_alu_funct),
        .alu_result (alu_result),
        .flag_z     (alu_flag_z),
        .flag_c     (alu_flag_c),
        .flag_n     (alu_flag_n)
    );

    // ---------------------------------------------------------------
    // SP Unit
    // ---------------------------------------------------------------
    sp_unit u_sp (
        .clk         (clk),
        .rst_n       (rst_n),
        .sp_we       (c_sp_we),
        .sp_addend   (ext_value),
        .sp_out      (sp_out),
        .sp_addr_out (sp_addr_out)
    );

    // ---------------------------------------------------------------
    // LR Register (inert - no interrupt-entry hardware yet)
    // ---------------------------------------------------------------
    lr_reg u_lr (
        .clk     (clk),
        .rst_n   (rst_n),
        .lr_we   (1'b0),
        .lr_wdata(8'b0),
        .lr_out  (lr_out)
    );

    // ---------------------------------------------------------------
    // Flags Register
    // ---------------------------------------------------------------
    flags_reg u_flags (
        .clk            (clk),
        .rst_n          (rst_n),
        .flags_we       (c_flags_we),
        .alu_z          (alu_flag_z),
        .alu_c          (alu_flag_c),
        .alu_n          (alu_flag_n),
        .shadow_save    (1'b0),           // reserved, no interrupt-entry hw yet
        .shadow_restore (c_shadow_restore),
        .flag_z         (flag_z),
        .flag_c         (flag_c),
        .flag_n         (flag_n),
        .shadow_z       (),
        .shadow_c       (),
        .shadow_n       ()
    );

    // ---------------------------------------------------------------
    // Mux 4 - Data Memory address
    // ---------------------------------------------------------------
    mux2to1 #(.WIDTH(8)) u_mux_dmem_addr (
        .sel (c_dmem_addr_sel),
        .in0 (alu_result),     // LW/SW: rs1+imm
        .in1 (sp_addr_out),    // STORESP/LOADSP
        .out (dmem_addr)
    );

    // ---------------------------------------------------------------
    // Data Memory (wdata uses the SAME rs2_addr-muxed read port as Mux 1)
    // ---------------------------------------------------------------
    data_memory u_dmem (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (dmem_addr),
        .wdata (rs2_rdata),
        .we    (c_dmem_we),
        .re    (c_dmem_re),
        .rdata (dmem_rdata)
    );

    // ---------------------------------------------------------------
    // GIE Register
    // ---------------------------------------------------------------
    gie_reg u_gie (
        .clk       (clk),
        .rst_n     (rst_n),
        .gie_set   (c_gie_set),
        .gie_clear (1'b0),      // no interrupt-taken hardware yet
        .gie_out   (gie_out)
    );

    // ---------------------------------------------------------------
    // Branch target adder
    // ---------------------------------------------------------------
    simple_adder u_bta (
        .pc_in         (pc_out),
        .offset        (ext_value),
        .branch_target (branch_target)
    );

    // ---------------------------------------------------------------
    // Mux 5 - PC redirect target
    // ---------------------------------------------------------------
    mux4to1 #(.WIDTH(8)) u_mux_pc_target (
        .sel (c_pc_target_sel),
        .in0 (branch_target), // BEQ/BNE
        .in1 (ext_value),     // JMP (already absolute, no shift)
        .in2 (lr_out),        // RETI
        .in3 (8'b0),          // unused
        .out (pc_redirect_addr)
    );

    // ---------------------------------------------------------------
    // Mux 3 - write-back data
    // ---------------------------------------------------------------
    mux4to1 #(.WIDTH(8)) u_mux_wb (
        .sel (c_wb_sel),
        .in0 (alu_result),  // ALU ops
        .in1 (dmem_rdata),  // LW / LOADSP
        .in2 (ext_value),   // LDI
        .in3 (8'b0),        // unused
        .out (wb_data)
    );

endmodule