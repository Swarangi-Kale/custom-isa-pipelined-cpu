// flags_reg.v
// -----------------------------------------------------------------------
// Flags (Z, C, N) register + single-level shadow copy, for the custom
// 16-bit pipelined processor.
//
// Main flags are updated by ALU-producing R-type instructions completing
// (flags_we + the ALU's flag outputs). The shadow copy exists purely to
// support interrupt context switching (Section 7/8, not built yet):
//   - shadow_save    : future interrupt-entry hardware copies the
//                       CURRENT architectural flags into the shadow,
//                       before they get clobbered by the ISR.
//   - shadow_restore : RETI restores the architectural flags from the
//                       shadow ("Flags <= flags_shadow").
//
// Priority: shadow_restore wins over a same-cycle flags_we, mirroring
// the redirect-wins-over-stall priority already used in pc_register.v.
// Structurally these can't collide in the real in-order pipeline (only
// one instruction retires per cycle), but the priority is defined here
// for robustness. shadow_save is an independent path (captures the
// pre-edge flag values regardless of what flags_we/shadow_restore do
// this same cycle) since save and restore serve different events
// (interrupt-taken vs. RETI) that also can't co-occur in one cycle.
// -----------------------------------------------------------------------

module flags_reg (
    input  wire clk,
    input  wire rst_n,          // active-low synchronous reset

    input  wire flags_we,       // normal update from an ALU-producing instr
    input  wire alu_z,
    input  wire alu_c,
    input  wire alu_n,

    input  wire shadow_save,    // future interrupt-entry hw: snapshot flags -> shadow
    input  wire shadow_restore, // RETI: shadow -> flags (priority over flags_we)

    output wire flag_z,
    output wire flag_c,
    output wire flag_n,

    output wire shadow_z,       // exposed mainly for debug/verification
    output wire shadow_c,
    output wire shadow_n
);

    reg z_reg, c_reg, n_reg;
    reg shadow_z_reg, shadow_c_reg, shadow_n_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            z_reg <= 1'b0; c_reg <= 1'b0; n_reg <= 1'b0;
            shadow_z_reg <= 1'b0; shadow_c_reg <= 1'b0; shadow_n_reg <= 1'b0;
        end else begin
            // Main flags: restore beats a normal ALU write.
            if (shadow_restore) begin
                z_reg <= shadow_z_reg;
                c_reg <= shadow_c_reg;
                n_reg <= shadow_n_reg;
            end else if (flags_we) begin
                z_reg <= alu_z;
                c_reg <= alu_c;
                n_reg <= alu_n;
            end

            // Shadow: independent path, snapshots the pre-edge main flags.
            if (shadow_save) begin
                shadow_z_reg <= z_reg;
                shadow_c_reg <= c_reg;
                shadow_n_reg <= n_reg;
            end
        end
    end

    assign flag_z = z_reg;
    assign flag_c = c_reg;
    assign flag_n = n_reg;

    assign shadow_z = shadow_z_reg;
    assign shadow_c = shadow_c_reg;
    assign shadow_n = shadow_n_reg;

endmodule