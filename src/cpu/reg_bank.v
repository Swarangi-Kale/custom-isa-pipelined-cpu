// reg_bank.v
// -----------------------------------------------------------------------
// GPR bank for the custom 16-bit pipelined processor: 8 x 8-bit registers
// (R0-R7), 2 combinational read ports, 1 synchronous write port.
//
// Per the ISA spec:
//   - No register is hardwired to zero (unlike RISC-V x0). R0 is an
//     ordinary read/write register here.
//   - SP, LR, and Flags live in separate dedicated units, NOT in this
//     file (kept out deliberately to keep hazard-detection scope limited
//     to these 8 GPRs).
//
// Read/write timing (standard register-file convention, note for later
// hazard/forwarding work): reads are asynchronous/combinational, writes
// are synchronous on the rising clk edge. A read of the same address
// being written in the same cycle returns the PRE-write value (old data),
// since the read is combinational off the current register contents and
// the write hasn't landed until the clock edge. This is the behavior any
// later forwarding logic needs to account for.
//
// Port names chosen to be instantiation-friendly for the datapath:
//   rs1_addr/rs2_addr <- rs1/rs2 fields from decode (ID stage)
//   rd_addr/rd_wdata/rd_we <- destination reg + writeback data/enable
//   (rd_we is driven by the control unit's reg-write signal)
// -----------------------------------------------------------------------

module reg_bank (
    input  wire       clk,
    input  wire       rst_n,      // active-low synchronous reset

    input  wire [2:0] rs1_addr,
    input  wire [2:0] rs2_addr,
    output wire [7:0] rs1_rdata,
    output wire [7:0] rs2_rdata,

    input  wire [2:0] rd_addr,   // output register select
    input  wire [7:0] rd_wdata,  // data to write back
    input  wire       rd_we      // write enable
);

    reg [7:0] regs [0:7];

    integer i;

    // Synchronous write, synchronous reset (resets to all-zero on reset).
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1)
                regs[i] <= 8'b0;
        end else if (rd_we) begin
            regs[rd_addr] <= rd_wdata;
        end
    end

    // Asynchronous (combinational) reads.
    assign rs1_rdata = regs[rs1_addr];
    assign rs2_rdata = regs[rs2_addr];

endmodule