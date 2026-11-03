// data_memory.v
// -----------------------------------------------------------------------
// Data memory for the custom 16-bit pipelined processor.
// "8-bit addr/data, read/write enables" (Section 5).
// 256 entries (2^8), matching the 8-bit address width.
//
// Only STORESP/LOADSP exist as memory instructions in this ISA - both
// address this memory via the SP Unit's sp_addr_out (SP-relative, non-
// destructive). Per the spec's own open item: "Address-arbitration mux
// details at the Data Memory interface (GPR-address-gen vs. SP-unit
// address) - identified but not yet formally spec'd as its own module."
// This module deliberately stays agnostic to where `addr` comes from -
// it just takes whatever address it's given. Which source feeds that
// port (SP unit only, for now) is a top-level wiring decision, not
// something resolved here.
//
// Timing: synchronous write, combinational (async) read - same
// convention as register_file.v. A read of the same address being
// written in the same cycle returns the PRE-write (old) value, for the
// same reasons documented there; not fixed here since (like the register
// file) no hazard can actually arise until pipelining exists.
//
// re (read enable) doesn't gate the underlying array lookup itself
// (that's just a combinational read), but gates rdata down to a defined
// 0 when deasserted rather than leaving it as "don't care" - keeps
// waveforms/downstream muxes clean without adding real hardware cost
// beyond a mux, and gives datapath logic elsewhere (e.g. a future
// load-use hazard check) an explicit "a real read is happening this
// cycle" signal to key off.
//
// Reset clears the whole array. Note this is a simulation/FPGA-BRAM-init
// convenience, not how real discrete SRAM behaves (real SRAM powers up
// with arbitrary contents) - worth knowing if you're ever asked about it.
// -----------------------------------------------------------------------

module data_memory #(
    parameter MEM_DEPTH = 256
) (
    input  wire       clk,
    input  wire       rst_n,   // active-low synchronous reset (clears array)

    input  wire [7:0] addr,
    input  wire [7:0] wdata,
    input  wire       we,      // write enable
    input  wire       re,      // read enable (gates rdata to 0 when low)

    output wire [7:0] rdata
);

    reg [7:0] mem [0:MEM_DEPTH-1];

    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < MEM_DEPTH; i = i + 1)
                mem[i] <= 8'h00;
        end else if (we) begin
            mem[addr] <= wdata;
        end
    end

    assign rdata = re ? mem[addr] : 8'h00;

endmodule