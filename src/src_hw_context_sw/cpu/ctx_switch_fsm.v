// -----------------------------------------------------------------------
// ctx_switch_fsm.v
// Hardware auto-stack/unstack for interrupt context switching (Phase D).
// Replaces the software ISR's save/restore instruction sequence with a
// dedicated 8-cycle burst per direction, driven entirely by this FSM --
// no instructions are fetched or executed during either burst.
//
// Saves/restores R1-R7 + LR (8 words), matching Phase C's exact memory
// layout (base = SP-7 .. SP, LR at offset 7) so the TCB/stack format is
// unchanged and directly comparable to the software baseline.
//
// Flow:
//   IDLE    -- irq_taken -> latch save_base = sp_current - 7, go to SAVE
//   SAVE    -- 8 cycles (cnt 0..7): cnt 0..6 store R1..R7, cnt 7 stores
//              LR (read directly from lr_reg, no GPR round-trip needed).
//              On cnt==7: sp_reg <= save_base, PC redirects to
//              TASK_SELECT_VECTOR, -> WAIT
//   WAIT    -- normal pipeline execution resumes; software finds the
//              next task and executes RESTORE_CTX Rn (Rn = that task's
//              saved base SP, exactly what its TCB entry already holds)
//   RESTORE -- 8 cycles (cnt 0..7): cnt 0..6 load R1..R7, cnt 7 loads
//              LR directly into lr_reg (no GPR round-trip).
//              On cnt==7: sp_reg <= restore_base+7, PC redirects to the
//              just-read LR value, GIE set, shadow_restore -> IDLE
//
// fsm_active covers the FULL 8 cycles of either burst (drives the
// data_memory/reg_bank port muxes at the top level). fsm_busy is a
// strict subset (cnt 0..6 only) -- it drops one cycle early, on cnt==7,
// so that cycle's PC redirect behaves like an ordinary same-cycle branch
// resolution rather than fighting a held PC. See processor_pipel_haz.v
// for how fsm_active/fsm_busy/fsm_save_done/fsm_restore_done are used.
// -----------------------------------------------------------------------
module ctx_switch_fsm (
    input  wire       clk,
    input  wire       rst_n,

    input  wire        irq_taken,
    input  wire        ex_ctx_restore,
    input  wire [7:0]  ex_rs1_corrected,
    input  wire [7:0]  sp_current,

    output wire        fsm_active,
    output wire        fsm_busy,
    output wire        fsm_save_active,
    output wire        fsm_restore_active,
    output wire        fsm_save_done,
    output wire        fsm_restore_done,
    output wire [7:0]  fsm_mem_addr,
    output wire [2:0]  fsm_gpr_addr,
    output wire [7:0]  fsm_save_base_out,
    output wire [7:0]  fsm_restore_base_out,    // NEW -- mirrors fsm_save_base_out
    output wire        fsm_settle

);

//    localparam IDLE = 2'b00, SAVE = 2'b01, WAIT = 2'b10, RESTORE = 2'b11;
    localparam IDLE = 3'd0, SETTLE = 3'd1, SAVE = 3'd2, WAIT = 3'd3, RESTORE = 3'd4;
    localparam SETTLE_CYCLES = 2;
    reg [2:0] state;
    
//    reg [1:0] state;
    reg [2:0] cnt;
    reg [7:0] save_base, restore_base;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            cnt   <= 3'd0;
        end else begin
            case (state)
//                IDLE: begin
//                    if (irq_taken) begin
//                        save_base <= sp_current - 8'd7;
//                        cnt       <= 3'd0;
//                        state     <= SAVE;
//                    end
//                end
                
                IDLE: begin
                    if (irq_taken) begin
                        cnt   <= 3'd0;
                        state <= SETTLE;
                    end
                end
                
                SETTLE: begin
                    if (cnt == SETTLE_CYCLES - 1) begin
                        save_base <= sp_current - 8'd7;
                        cnt       <= 3'd0;
                        state     <= SAVE;
                    end else begin
                        cnt <= cnt + 3'd1;
                    end
                end
                
                SAVE: begin
                    if (cnt == 3'd7) begin
                        state <= WAIT;
                        cnt   <= 3'd0;
                    end else begin
                        cnt <= cnt + 3'd1;
                    end
                end

                WAIT: begin
                    if (ex_ctx_restore) begin
                        restore_base <= ex_rs1_corrected;
                        cnt          <= 3'd0;
                        state        <= RESTORE;
                    end
                end

                RESTORE: begin
                    if (cnt == 3'd7) begin
                        state <= IDLE;
                        cnt   <= 3'd0;
                    end else begin
                        cnt <= cnt + 3'd1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign fsm_save_active    = (state == SAVE);
    assign fsm_restore_active = (state == RESTORE);
    assign fsm_active         = fsm_save_active || fsm_restore_active;
    assign fsm_busy           = fsm_active && (cnt != 3'd7);

    assign fsm_save_done      = fsm_save_active    && (cnt == 3'd7);
    assign fsm_restore_done   = fsm_restore_active && (cnt == 3'd7);

    assign fsm_mem_addr = fsm_save_active    ? (save_base + {5'b0, cnt}) :
                           fsm_restore_active ? (restore_base + {5'b0, cnt}) :
                                                 8'h00;

    assign fsm_gpr_addr = cnt + 3'd1;   // valid only when cnt != 7 (caller gates this)

    assign fsm_save_base_out = save_base;

    assign fsm_restore_base_out = restore_base;   // NEW
    
    assign fsm_settle = (state == SETTLE);

endmodule