// ---------------------------------------------------------------------
// processor_pipel_haz.v
//
// Builds on processor_pipelined.v by adding:
//   - Forwarding Unit (EX/MEM->EX, MEM/WB->EX) for both ALU operands,
//     which also transparently covers the store-value path (SW/STORESP)
//     since that value is just rs1/rs2-derived data riding the same
//     corrected wires through to EX/MEM.
//   - Hazard Detection Unit (GPR load-use only - the SP interlock
//     originally in the spec is confirmed unneeded and dropped; see
//     hazard_detection_unit.v header).
//   - Flush on if_id_reg and id_ex_reg, driven by EX-stage branch
//     resolution (ex_pc_redirect) - squashes exactly the 2 instructions
//     already fetched by the time a branch/jump/RETI resolves.
//   - Stall (hold) on if_id_reg and PC, plus a bubble into id_ex_reg,
//     driven by the Hazard Detection Unit - a single self-clearing
//     cycle, no counter/FSM needed.
//
// Everything else (module set, per-instruction control behavior) is
// unchanged from processor_pipelined.v.
// -----------------------------------------------------------------------
module processor_pipel_haz #(parameter INIT_FILE = "prog_sw.mem")(
    input wire clk,
    input wire rst_n,
    input wire irq_in,          // NEW: interrupt request, testbench-driven for now
    
    // port list additions:
    output wire [7:0] dbg_pc,
    output wire [7:0] dbg_wb,
    output wire [7:0] dbg_sp,
    output wire [7:0] dbg_lr,
    output wire [7:0] dbg_dmem,
    output wire       dbg_gie,
    output wire [2:0] dbg_flags
);

    // =================================================================
    // IF stage
    // =================================================================
    wire [7:0]  pc_out;
    wire [15:0] instr_if;

    wire        ex_pc_redirect;
    wire [7:0]  ex_pc_redirect_addr;
    wire        hdu_stall;
    
    // ---- Interrupt trap logic ----
    wire irq_taken = irq_in && gie_out && !hdu_stall;
    
    // Resume PC: if a branch also resolves this cycle, its own target is the
    // correct resume point (that instruction commits regardless of the
    // interrupt); otherwise the oldest squashed instruction is id_pc.
    wire [7:0] resume_pc = ex_pc_redirect ? ex_pc_redirect_addr : id_pc;
    
    localparam [7:0] ISR_VECTOR = 8'h40;   // TODO: set to your ISR's actual start address
    
    wire        pc_redirect_final      = ex_pc_redirect || irq_taken;
    wire [7:0]  pc_redirect_addr_final = irq_taken ? ISR_VECTOR : ex_pc_redirect_addr;    
        
    wire id_ex_flush = ex_pc_redirect || hdu_stall || irq_taken;
    
    pc_register u_pc (
        .clk              (clk),
        .rst_n            (rst_n),
        .pc_write_en      (~hdu_stall),         // hold PC during a load-use stall
        .pc_redirect      (pc_redirect_final),      // was: ex_pc_redirect
        .pc_redirect_addr (pc_redirect_addr_final), // was: ex_pc_redirect_addr
        .pc_out           (pc_out)
    );

    instr_mem #(
        .INIT_FILE(INIT_FILE)
    ) u_imem (
        .addr      (pc_out),
        .instr_out (instr_if)
    );

    // ---- IF/ID pipeline register ----
    wire [15:0] id_instr;
    wire [7:0]  id_pc;

    if_id_reg_modified u_if_id (
        .clk       (clk),
        .rst_n     (rst_n),
        .stall     (hdu_stall),        // hold - real instruction, just waiting
        .flush     (ex_pc_redirect || irq_taken),   // discard - wrong-path instruction
        .instr_in  (instr_if),
        .pc_in     (pc_out),
        .instr_out (id_instr),
        .pc_out    (id_pc)
    );

    // =================================================================
    // ID stage
    // =================================================================
    wire [3:0] id_opcode   = id_instr[15:12];
    wire [2:0] id_funct    = id_instr[2:0];
    wire [2:0] id_rd_addr  = id_instr[11:9];
    wire [2:0] id_rs1_addr = id_instr[8:6];

    wire [2:0] c_alu_funct;
    wire       c_alu_src_b_sel;
    wire       c_rs1_addr_sel; // added for ADDI
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
    wire       c_spec_sel;
    wire       c_sp_direct_we;

    control_unit_pipelined u_ctrl (
        .opcode         (id_opcode),
        .funct          (id_funct),
        .instr8(id_instr[8]),
        
        .alu_funct      (c_alu_funct),
        .alu_src_b_sel  (c_alu_src_b_sel),
        .rs1_addr_sel   (c_rs1_addr_sel),        
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
        .shadow_save    (c_shadow_save),
        .spec_sel       (c_spec_sel),
        .sp_direct_we   (c_sp_direct_we)   
    );

    wire [7:0] id_ext_value;
    sign_extension_unit u_seu (
        .instr      (id_instr),
        .format_sel (c_format_sel),
        .ext_value  (id_ext_value)
    );
    
    // NEW: rs1_addr mux - normally instr[8:6], but ADDI has no separate
    // rs1 field (its "source" IS its own rd), so it self-references
    // instr[11:9] instead.
    wire [2:0] id_rs1_addr_muxed;
    mux2to1 #(.WIDTH(3)) u_mux_rs1addr (
        .sel (c_rs1_addr_sel),
        .in0 (id_rs1_addr),
        .in1 (id_instr[11:9]),
        .out (id_rs1_addr_muxed)
    );

    wire [2:0] id_rs2_addr_muxed;
    mux2to1 #(.WIDTH(3)) u_mux_rs2addr (
        .sel (c_rs2_addr_sel),
        .in0 (id_instr[5:3]),
        .in1 (id_instr[11:9]),
        .out (id_rs2_addr_muxed)
    );

    // ---- Hazard Detection Unit ----
    // ex_rd_addr / ex_dmem_re / ex_rd_we are the CURRENT id_ex_reg outputs
    // (declared later, used here - Forward references fine in Verilog
    hazard_detection_unit u_hdu (
        .id_opcode   (id_opcode),
        .id_funct    (id_funct),      // NEW
        .id_rs1_addr (id_rs1_addr_muxed),
        .id_rs2_addr (id_rs2_addr_muxed),
        .ex_rd_addr  (ex_rd_addr),
        .ex_dmem_re  (ex_dmem_re),
        .ex_rd_we    (ex_rd_we),
        .stall       (hdu_stall)
    );

    // Register file: read ports driven by ID stage; write port driven by WB stage
    wire [7:0] id_rs1_rdata, id_rs2_rdata;
    wire [7:0] wb_wdata;
    wire [2:0] wb_rd_addr;
    wire       wb_rd_we;

    reg_bank u_rf (
        .clk       (clk),
        .rst_n     (rst_n),
        .rs1_addr  (id_rs1_addr_muxed),
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
    wire [2:0] ex_rs1_addr, ex_rs2_addr;      // NEW - for forwarding_unit
    wire [2:0] ex_alu_funct;
    wire       ex_alu_src_b_sel;
    wire       ex_dmem_addr_sel, ex_dmem_we, ex_dmem_re;
    wire       ex_sp_we, ex_flags_we;
    wire [1:0] ex_wb_sel;
    wire       ex_rd_we;
    wire [1:0] ex_br_type;
    wire [1:0] ex_pc_target_sel;
    wire       ex_shadow_restore, ex_gie_set;
    wire ex_lr_we, ex_spec_sel, ex_sp_direct_we;                             // add near the other ex_* control wires (with ex_sp_we, ex_flags_we)

    id_ex_reg_modified u_id_ex (
        .clk               (clk),
        .rst_n             (rst_n),
        .flush             (id_ex_flush),
        .pc_in             (id_pc),
        .rs1_rdata_in      (id_rs1_rdata),
        .rs2_rdata_in      (id_rs2_rdata),
        .ext_value_in      (id_ext_value),
        .rd_addr_in        (id_rd_addr),
        .rs1_addr_in       (id_rs1_addr_muxed),
        .rs2_addr_in       (id_rs2_addr_muxed),
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
        .lr_we_in          (c_lr_we),     // NEW
        .spec_sel_in       (c_spec_sel),
        .sp_direct_we_in   (c_sp_direct_we),

        .pc_out             (ex_pc),
        .rs1_rdata_out      (ex_rs1_rdata),
        .rs2_rdata_out      (ex_rs2_rdata),
        .ext_value_out      (ex_ext_value),
        .rd_addr_out        (ex_rd_addr),
        .rs1_addr_out       (ex_rs1_addr),
        .rs2_addr_out       (ex_rs2_addr),
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
        .gie_set_out        (ex_gie_set),
        .lr_we_out         (ex_lr_we),    // NEW
        .spec_sel_out       (ex_spec_sel),
        .sp_direct_we_out   (ex_sp_direct_we)
    );

    // =================================================================
    // EX stage
    // =================================================================

    // ---- Forwarding Unit ----
    // mem_rd_addr/mem_rd_we and wb_rd_addr/wb_rd_we are declared further
    // below (EX/MEM and MEM/WB stage signals) - forward references are
    // fine in Verilog within a module.
    wire [1:0] fwd_a_sel, fwd_b_sel;
    forwarding_unit u_fwd (
        .ex_rs1_addr   (ex_rs1_addr),
        .ex_rs2_addr   (ex_rs2_addr),
        .mem_rd_addr   (mem_rd_addr),
        .mem_rd_we     (mem_rd_we),
        .wb_rd_addr    (wb_rd_addr),
        .wb_rd_we      (wb_rd_we),
        .forward_a_sel (fwd_a_sel),
        .forward_b_sel (fwd_b_sel)
    );

    // EX/MEM-stage candidate forwarded value: ALU result, or ext_value
    // for a pipelined LDI sitting in EX/MEM. A pending load's data is
    // never actually selected here in practice - the HDU's stall
    // guarantees a load is never the distance-1 producer for a consumer
    // that needs it (see forwarding_unit.v header).
    wire [7:0] exmem_fwd_value;
    mux4to1 #(.WIDTH(8)) u_exmem_fwd_val (
    .sel (mem_wb_sel),
    .in0 (mem_alu_result),   // 00
    .in1 (mem_alu_result),   // 01 - dmem-load case; never actually selected here since
                              //      HDU guarantees distance>=2 for loads, but give it a
                              //      defined value rather than leaving it don't-care
    .in2 (mem_ext_value),    // 10
    .in3 (mem_lr_value),     // 11 - NEW
    .out (exmem_fwd_value)
    );

    // Corrected rs1: original register-file value, or forwarded
    wire [7:0] ex_rs1_corrected;
    mux4to1 #(.WIDTH(8)) u_mux_fwd_a (
        .sel (fwd_a_sel),
        .in0 (ex_rs1_rdata),
        .in1 (exmem_fwd_value),
        .in2 (wb_wdata),
        .in3 (8'b0),
        .out (ex_rs1_corrected)
    );

    // Corrected rs2: original register-file value, or forwarded. This
    // single corrected value feeds BOTH the ALU-B mux (R-type/branch
    // compares) AND rides forward as the (corrected) store-value for
    // SW/STORESP - one correction point covers both consumers.
    wire [7:0] ex_rs2_corrected;
    mux4to1 #(.WIDTH(8)) u_mux_fwd_b (
        .sel (fwd_b_sel),
        .in0 (ex_rs2_rdata),
        .in1 (exmem_fwd_value),
        .in2 (wb_wdata),
        .in3 (8'b0),
        .out (ex_rs2_corrected)
    );

    wire [7:0] ex_alu_in_b;
    mux2to1 #(.WIDTH(8)) u_mux_alu_b (
        .sel (ex_alu_src_b_sel),
        .in0 (ex_rs2_corrected),
        .in1 (ex_ext_value),
        .out (ex_alu_in_b)
    );

    wire [7:0] ex_alu_result;
    wire       ex_alu_flag_z, ex_alu_flag_c, ex_alu_flag_n;

    alu u_alu (
        .alu_in_a   (ex_rs1_corrected),
        .alu_in_b   (ex_alu_in_b),
        .alu_funct  (ex_alu_funct),
        .alu_result (ex_alu_result),
        .flag_z     (ex_alu_flag_z),
        .flag_c     (ex_alu_flag_c),
        .flag_n     (ex_alu_flag_n)
    );

    // SP Unit
    wire [7:0] ex_sp_out, ex_sp_addr_out;
    sp_unit u_sp (
        .clk         (clk),
        .rst_n       (rst_n),
        .sp_we       (ex_sp_we),
        .sp_addend   (ex_ext_value),
        .sp_out      (ex_sp_out),
        .sp_addr_out (ex_sp_addr_out),
        .sp_direct_we(ex_sp_direct_we),
        .sp_direct_wdata(ex_rs1_corrected)
    );

    // LR Register (inert - no interrupt-entry hardware yet)
    wire [7:0] lr_out;
    lr_reg u_lr (
        .clk      (clk),
        .rst_n    (rst_n),
        .lr_we    (ex_lr_we || irq_taken),                      // ex_lr_we = c_lr_we piped through id_ex_reg
        .lr_wdata (irq_taken ? resume_pc : ex_rs1_corrected),
        .lr_out   (lr_out)
    );
    
    // NEW: select which special register's read value feeds WB/forwarding,
    // now that MOV SPEC covers both LR and SP.
    wire [7:0] ex_spec_read_value = ex_spec_sel ? ex_sp_out : lr_out;

    // Flags Register
    wire flag_z, flag_c, flag_n; // committed flags (unused elsewhere)
    flags_reg u_flags (
        .clk            (clk),
        .rst_n          (rst_n),
        .flags_we       (ex_flags_we),
        .alu_z          (ex_alu_flag_z),
        .alu_c          (ex_alu_flag_c),
        .alu_n          (ex_alu_flag_n),
        .shadow_save    (irq_taken),
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
        .gie_clear (irq_taken),     // was early hardcoded to 1'b0
        .gie_out   (gie_out)
    );

    // Branch target adder
    wire [7:0] ex_branch_target;
    simple_adder u_bta (
        .pc_in         (ex_pc),
        .offset        (ex_ext_value),
        .branch_target (ex_branch_target)
    );

    // PC redirect target
    mux4to1 #(.WIDTH(8)) u_mux_pc_target (
        .sel (ex_pc_target_sel),
        .in0 (ex_branch_target),
        .in1 (ex_ext_value),   // JMP
        .in2 (lr_out),         // RETI
        .in3 (8'b0),
        .out (ex_pc_redirect_addr)
    );

    // Branch/jump resolution: br_type meets the live (forwarding-
    // corrected doesn't matter here - flag_z always comes straight off
    // this cycle's ALU comparison) ALU flag.
    assign ex_pc_redirect = (ex_br_type == 2'b01 &&  ex_alu_flag_z) ||  // BEQ taken
                            (ex_br_type == 2'b10 && !ex_alu_flag_z) ||  // BNE taken
                            (ex_br_type == 2'b11);                     // JMP/RETI

    // ---- EX/MEM pipeline register ----
    wire [7:0] mem_alu_result, mem_rs2_rdata, mem_ext_value, mem_sp_addr_out;
    wire [2:0] mem_rd_addr;
    wire       mem_dmem_addr_sel, mem_dmem_we, mem_dmem_re;
    wire [1:0] mem_wb_sel;
    wire       mem_rd_we;
    wire [7:0] mem_lr_value, wbstage_lr_value;   // add near mem_alu_result / wbstage_alu_result

    ex_mem_reg u_ex_mem (
        .clk               (clk),
        .rst_n             (rst_n),
        .alu_result_in     (ex_alu_result),
        .rs2_rdata_in      (ex_rs2_corrected),   // corrected store value
        .ext_value_in      (ex_ext_value),
        .sp_addr_out_in    (ex_sp_addr_out),
        .rd_addr_in        (ex_rd_addr),
        .dmem_addr_sel_in  (ex_dmem_addr_sel),
        .dmem_we_in        (ex_dmem_we),
        .dmem_re_in        (ex_dmem_re),
        .wb_sel_in         (ex_wb_sel),
        .rd_we_in          (ex_rd_we),
        .lr_value_in   (ex_spec_read_value),        // Even though the name is lr, it carries either lr or sp value depending on the instruction

        .alu_result_out    (mem_alu_result),
        .rs2_rdata_out     (mem_rs2_rdata),
        .ext_value_out     (mem_ext_value),
        .sp_addr_out_out   (mem_sp_addr_out),
        .rd_addr_out       (mem_rd_addr),
        .dmem_addr_sel_out (mem_dmem_addr_sel),
        .dmem_we_out       (mem_dmem_we),
        .dmem_re_out       (mem_dmem_re),
        .wb_sel_out        (mem_wb_sel),
        .rd_we_out         (mem_rd_we),
        .lr_value_out  (mem_lr_value) // NEW
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
        .lr_value_in   (mem_lr_value),     // NEW

        .dmem_rdata_out (wbstage_dmem_rdata),
        .alu_result_out (wbstage_alu_result),
        .ext_value_out  (wbstage_ext_value),
        .rd_addr_out    (wb_rd_addr),
        .rd_we_out      (wb_rd_we),
        .wb_sel_out     (wbstage_wb_sel),
        .lr_value_out  (wbstage_lr_value) // NEW
    );

    // =================================================================
    // WB stage
    // =================================================================
    mux4to1 #(.WIDTH(8)) u_mux_wb (
        .sel (wbstage_wb_sel),
        .in0 (wbstage_alu_result),
        .in1 (wbstage_dmem_rdata),
        .in2 (wbstage_ext_value),
        .in3 (wbstage_lr_value),
        .out (wb_wdata)
    );
    // wb_wdata, wb_rd_addr, wb_rd_we feed register_file's write port (declared above)
    
    // body:
    assign dbg_pc    = pc_out;
    assign dbg_wb    = wb_wdata;
    assign dbg_sp    = ex_sp_out;
    assign dbg_lr    = lr_out;
    assign dbg_dmem  = mem_dmem_rdata;
    assign dbg_gie   = gie_out;
    assign dbg_flags = {flag_z, flag_c, flag_n};
    
    
endmodule