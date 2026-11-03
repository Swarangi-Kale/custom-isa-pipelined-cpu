// hazard_detection_unit.v
// -----------------------------------------------------------------------
// GPR load-use hazard, only. The SP interlock originally called for in
// the spec is confirmed NOT needed: sp_unit commits its write in EX, the
// exact same pipeline stage the ALU commits at, so ADDSP immediately
// followed by STORESP/LOADSP are always exactly one cycle apart at that
// stage by construction - the producer's write has already landed by the
// time the consumer reaches EX, with no scenario (stalls only add slack,
// never remove it) that closes that gap. Confirmed and the spec updated
// accordingly - this unit does not implement an SP condition.
//
// uses_rs1/uses_rs2 are decoded locally from id_opcode alone, rather than
// extending control_unit_pipelined, to keep this a self-contained,
// minimal-footprint addition. This exists specifically to avoid a false
// stall trigger on instruction formats where the ID-stage bit positions
// this unit would otherwise compare aren't real register reads at all -
// e.g. LDI's bits are immediate bits, not rs1/rs2, and could numerically
// coincide with a pending load's destination register by pure chance.
//
// id_rs2_addr is expected to be the ALREADY-MUXED rs2 position (i.e. the
// same signal fed to register_file.rs2_addr at the top level) - this
// unit does not redo that muxing itself.
//
// Stall is a single combinational condition, not a counter/FSM: it
// self-clears the cycle after it fires, because the bubble inserted into
// EX in its place has dmem_re=0/rd_we=0, which never matches on the
// following cycle's check.

//A BUG NOTE:
// 3. Real HDU bug (in hazard_detection_unit.v, not this TB): its
//    uses_rs1 list omitted OP_MOVLR, so LW immediately followed by
//    MOV SP,Rd / MOV LR,Rd (write direction) never stalled. Forwarding
//    fell back to its "never actually selected" EX/MEM alu_result
//    path, handing SP the load's ADDRESS instead of its DATA (e.g.
//    LW R2,0x05(R0); MOV SP,R2 gave SP=0x05 instead of mem[0x05]).
//    Fix: gate on funct[0] (write direction only - read direction has
//    no real rs1 to hazard-check) and add OP_MOVLR to uses_rs1 when
//    funct[0]=1. Needed a new id_funct input on hazard_detection_unit,
//    wired from processor_pipel_haz.v's existing id_funct signal.
// -----------------------------------------------------------------------

module hazard_detection_unit (
    input  wire [3:0] id_opcode,
    input  wire [2:0] id_funct,      // NEW - needed to gate MOV's write direction
    input  wire [2:0] id_rs1_addr,
    input  wire [2:0] id_rs2_addr,   // already-muxed rs2 position

    input  wire [2:0] ex_rd_addr,
    input  wire       ex_dmem_re,
    input  wire       ex_rd_we,

    output wire        stall
);

    localparam OP_RTYPE   = 4'b0000;
    localparam OP_LW      = 4'b0001;
    localparam OP_SW      = 4'b0010;
    localparam OP_BNE     = 4'b0100;
    localparam OP_BEQ     = 4'b0101;
    localparam OP_STORESP = 4'b1001;
    localparam OP_ADDI    = 4'b1011;  
    localparam OP_MOVLR   = 4'b1100;   // NEW
    localparam OP_CTXRESTORE = 4'b1010;

  
    wire mov_write = (id_opcode == OP_MOVLR) && id_funct[0];   // NEW: dir=1 (write) only

// add OP_CTXRESTORE to uses_rs1 (unconditional -- this opcode always reads a GPR):
    wire uses_rs1 = (id_opcode == OP_RTYPE) || (id_opcode == OP_LW) ||
                    (id_opcode == OP_SW)    || (id_opcode == OP_BNE) ||
                    (id_opcode == OP_BEQ)   || (id_opcode == OP_ADDI) ||
                    (id_opcode == OP_CTXRESTORE) ||
                    mov_write;

    wire uses_rs2 = (id_opcode == OP_RTYPE)   || (id_opcode == OP_SW) ||
                    (id_opcode == OP_BNE)     || (id_opcode == OP_BEQ) ||
                    (id_opcode == OP_STORESP);

    assign stall = ex_dmem_re && ex_rd_we &&
                   ( (uses_rs1 && (ex_rd_addr == id_rs1_addr)) ||
                     (uses_rs2 && (ex_rd_addr == id_rs2_addr)) );

endmodule