// sp_unit.v
// -----------------------------------------------------------------------
// Dedicated Stack Pointer unit ("Option B", Section 6): SP lives outside
// the GPR file with its own small 8-bit adder, NOT the shared ALU. One
// register + one adder is enough since only one thing reads/writes SP
// per cycle.
//
// The same adder serves two instructions:
//   - ADDSP imm   : sp_we=1, sp_addend=extended imm12 -> commits new SP
//   - STORESP/LOADSP Rd, offset : sp_we=0, sp_addend=extended offset9
//                                 -> sp_addr_out is the effective memory
//                                 address; SP itself is NOT modified
//                                 (non-destructive, per spec)
//
// sp_addend is expected to already be sign-extended down to 8 bits by
// the Sign-Extension Unit (not yet built) before reaching this module -
// SP is only 8 bits wide, so both the 12-bit ADDSP immediate and the
// 9-bit SP-mem offset must be narrowed to 8-bit two's-complement first.
//
// SP_RESET_VAL is a parameter (default 0x00) since the spec doesn't
// define a reset value for SP - override at instantiation if you want
// e.g. a top-of-stack reset instead.
// -----------------------------------------------------------------------

module sp_unit #(
    parameter [7:0] SP_RESET_VAL = 8'h00
) (
    input  wire       clk,
    input  wire       rst_n,        // active-low synchronous reset

    input  wire       sp_we,        // 1 = commit adder result into SP (ADDSP only)
    input  wire [7:0] sp_addend,    // signed 8-bit addend (already extended)
    
    input wire       sp_direct_we,
    input wire [7:0] sp_direct_wdata,

    output wire [7:0] sp_out,       // current committed SP value
    output wire [7:0] sp_addr_out   // SP + sp_addend (mem address for STORESP/LOADSP,
                                     // or the value ADDSP would commit)
);

    reg [7:0] sp_reg;

    assign sp_addr_out = sp_reg + sp_addend;

    always @(posedge clk) begin
        if (!rst_n)              sp_reg <= SP_RESET_VAL;
        else if (sp_direct_we)   sp_reg <= sp_direct_wdata;   // MOV SP,Rd
        else if (sp_we)          sp_reg <= sp_addr_out;       // ADDSP (unchanged)
    end

    assign sp_out = sp_reg;

endmodule