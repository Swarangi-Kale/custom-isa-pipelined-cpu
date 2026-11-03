// pc_register.v
// -----------------------------------------------------------------------
// Program Counter register for the custom 16-bit pipelined processor.
// 8-bit, word-addressed (increments by 1 per instruction, since
// instruction memory holds 16-bit-wide words).
//
// Two control inputs, per the spec's Section 5/6 intent:
//   pc_write_en  - gates a plain PC+1 advance. Deasserted to hold the PC
//                  steady during a stall (e.g. future load-use hazard).
//   pc_redirect  - a single reusable "flush + redirect" signal, assertable
//                  by a taken branch/jump now, and by interrupt-taken
//                  later (Section 6: designed for reuse, not duplicated).
//                  Takes priority over a stall: a redirect must always
//                  win, since the redirect itself implies the pipeline
//                  is being flushed regardless of any concurrent stall
//                  condition.
//
// Port names chosen to be instantiation-friendly for the datapath:
//   pc_redirect_addr <- branch/jump target (later: fixed ISR entry addr)
//   pc_out            -> instruction memory address input
// -----------------------------------------------------------------------

module pc_register (
    input  wire       clk,
    input  wire       rst_n,            // active-low synchronous reset

    input  wire       pc_write_en,      // 1 = allow PC+1 advance; 0 = hold (stall)
    input  wire       pc_redirect,      // 1 = load pc_redirect_addr instead of PC+1
    input  wire [7:0] pc_redirect_addr,

    output reg  [7:0] pc_out
);

    always @(posedge clk) begin
        if (!rst_n) begin
            pc_out <= 8'b0;             // fixed reset vector: address 0
        end else if (pc_redirect) begin
            pc_out <= pc_redirect_addr; // redirect wins over a stall
        end else if (pc_write_en) begin
            pc_out <= pc_out + 8'd1;
        end
        // else: pc_write_en=0 and no redirect -> hold current value (stall)
    end

endmodule