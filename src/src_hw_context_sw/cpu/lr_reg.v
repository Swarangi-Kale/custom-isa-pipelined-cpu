// lr_reg.v
// -----------------------------------------------------------------------
// Link Register for the custom 16-bit pipelined processor. Single 8-bit
// register. No current instruction writes it - per the spec (Section 7),
// LR is written only by future interrupt-entry hardware (LR <= PC_next
// on interrupt-taken), and is read only by RETI (PC <= LR).
//
// This module just builds the register + its write/read ports now, so
// the datapath has somewhere to plug into later. lr_we/lr_wdata will sit
// unused by any current instruction until Section 8's interrupt-entry
// hardware exists - that's expected, not a bug (the spec explicitly says
// RETI isn't end-to-end testable until then).
// -----------------------------------------------------------------------

module lr_reg (
    input  wire       clk,
    input  wire       rst_n,     // active-low synchronous reset

    input  wire       lr_we,     // driven by future interrupt-entry hardware
    input  wire [7:0] lr_wdata,  // PC_next captured on interrupt-taken

    output wire [7:0] lr_out     // read by RETI: PC <= lr_out
);

    reg [7:0] lr_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            lr_reg <= 8'b0;
        end else if (lr_we) begin
            lr_reg <= lr_wdata;
        end
    end

    assign lr_out = lr_reg;

endmodule