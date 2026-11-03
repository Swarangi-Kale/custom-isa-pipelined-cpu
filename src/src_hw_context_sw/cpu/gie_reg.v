// gie_reg.v
// -----------------------------------------------------------------------
// Global Interrupt Enable: a single flip-flop (Section 2/7). Set by RETI
// (re-arms interrupts on return); cleared by future interrupt-taken
// hardware (Section 8, not built yet - gie_clear is currently never
// driven high by anything real).
//
// Priority: gie_clear wins over a same-cycle gie_set. These can't
// actually co-occur in this single-issue in-order design (RETI retiring
// and a new interrupt being taken can't both be the live event in the
// same cycle), so this is defined for robustness rather than a real
// scenario - same spirit as the priority choices already made in
// pc_register.v and flags_register.v. The direction chosen here is the
// fail-safe one: if both were ever asserted together, disabling wins,
// since you never want interrupts left armed while entering an ISR.
//
// Reset value: 0 (interrupts disabled at reset). Common real-world
// convention - avoids taking an interrupt before boot code has set up
// handlers/stack, similar in spirit to ARM Cortex-M's PRIMASK behavior.
// -----------------------------------------------------------------------

module gie_reg (
    input  wire clk,
    input  wire rst_n,     // active-low synchronous reset

    input  wire gie_set,   // RETI
    input  wire gie_clear, // future interrupt-taken hardware (not driven yet)

    output wire gie_out
);

    reg gie_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            gie_reg <= 1'b0;
        end else if (gie_clear) begin
            gie_reg <= 1'b0;   // priority over a concurrent gie_set
        end else if (gie_set) begin
            gie_reg <= 1'b1;
        end
    end

    assign gie_out = gie_reg;

endmodule