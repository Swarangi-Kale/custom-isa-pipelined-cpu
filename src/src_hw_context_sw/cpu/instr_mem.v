// instr_mem.v
// -----------------------------------------------------------------------
// Instruction memory for the custom 16-bit pipelined processor.
// "Simple ROM/RAM, PC-addressed, 16-bit instruction output" (Section 5).
// 256 entries (2^8), matching the 8-bit PC address space we locked in.
//
// Modeled as ROM-like: no runtime write port. A program is loaded either
// via the INIT_FILE parameter ($readmemh at elaboration time) or by
// poking the mem[] array directly in a testbench/top-level - there's no
// STORE-to-instruction-memory instruction in this ISA, so no write port
// is needed for normal operation.
//
// Read is combinational (async), same convention as register_file.v -
// the IF stage needs the instruction available within the same cycle
// PC presents its address, feeding the IF/ID pipeline register on the
// next clock edge.
// -----------------------------------------------------------------------

module instr_mem #(
    parameter MEM_DEPTH = 256,
    parameter INIT_FILE = ""    // optional $readmemh file path to preload a program
) (
    input  wire [7:0]  addr,       // PC value
    output wire [15:0] instr_out   // instruction word at that address
);

    reg [15:0] mem [0:MEM_DEPTH-1];

    // NOTE: default fill is 16'h0000. Per the ISA table, opcode 0000 is
    // R-type, and funct 000 is ADD - so an unprogrammed/padding word
    // decodes as "ADD R0, R0, R0", NOT a true no-op (it still writes R0
    // and sets Z/C/N). No dedicated NOP opcode is defined in the spec
    // yet. Harmless for most test programs (R0 unused elsewhere, and
    // flags get overwritten by the next real ALU op) but worth knowing
    // before relying on trailing memory as a safe landing zone.
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            mem[i] = 16'h0000;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    assign instr_out = mem[addr];

endmodule