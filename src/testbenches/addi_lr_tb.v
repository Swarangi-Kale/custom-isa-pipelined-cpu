// -----------------------------------------------------------------------
// addi_lr_tb.v
// Integration testbench for processor_pipel_haz.v. Covers ADDI and the
// MOVLR (MOV Rd,LR / MOV LR,Rd) instructions. Rewritten in the same
// plain style as processor_pipel_haz_tb.v: instructions are hand-
// assembled hex literals written straight into instruction memory,
// with NO encoder functions and NO `define wrapper macros. This avoids
// the bug in the original enc_ldi/enc_addi functions, where
// {OP_LDI, rd, imm8} / {OP_ADDI, rd, imm8} only add up to 4+3+8=15
// bits. Verilog silently zero-extends that 15-bit value to the 16-bit
// function return by padding a 0 on the MSB side, which shifts every
// field left by one bit and corrupts the opcode. The real layout
// (confirmed against the working LDI/ADD encodings in
// processor_pipel_haz_tb.v, e.g. 16'h3205 = LDI R1,5) is:
//
//   LDI / ADDI : opcode(4) | rd(3) | imm(9)      <- imm9 = {1'b0, imm8}
//   MOVLR      : opcode(4) | reg(3) | 0(6) | funct(3)
//                  funct=000 -> MOV Rd,LR (read)
//                  funct=001 -> MOV LR,Rd (write)
//
// Opcodes: OP_LDI=4'b0011, OP_ADDI=4'b1011, OP_MOVLR=4'b1100
//
// Program (word-addressed, hand-assembled and verified bit-by-bit
// against the layout above):
//    0: LDI    R0,5              ; R0=5
//    1: NOP
//    2: NOP
//    3: MOV    LR,R0             ; LR=5
//    4: NOP
//    5: NOP
//    6: MOV    R1,LR             ; R1=5           (round-trip check)
//    7: ADDI   R2,10             ; R2=0+10=10     (basic ADDI)
//    8: LDI    R3,0xFF           ; R3=0xFF
//    9: NOP
//   10: NOP
//   11: ADDI   R3,1              ; R3=0xFF+1->0x00, Z=1,C=1 (overflow wrap)
//   12: ADDI   R4,0xFF           ; R4=0+(-1)=0xFF, N=1      (negative imm)
//   13: LDI    R5,0x2A           ; R5=0x2A
//   14: NOP
//   15: NOP
//   16: MOV    LR,R5             ; LR=0x2A
//   17: MOV    R6,LR             ; R6=0x2A         (write->read, back-to-back)
//   18: MOV    R7,LR             ; R7=0x2A
//   19: ADDI   R7,1              ; R7=0x2A+1=0x2B  (EX/MEM fwd, distance-1
//                                                    forwarding-bug regression)
//
// Hex derivation (checked by hand, nibble by nibble):
//   0: LDI  R0,5    -> 0011 000 000000101       -> 0011 0000 0000 0101 -> 3005
//   3: MOV  LR,R0   -> 1100 000 000000 001      -> 1100 0000 0000 0001 -> C001
//   6: MOV  R1,LR   -> 1100 001 000000 000      -> 1100 0010 0000 0000 -> C200
//   7: ADDI R2,10   -> 1011 010 000001010       -> 1011 0100 0000 1010 -> B40A
//   8: LDI  R3,0xFF -> 0011 011 011111111       -> 0011 0110 1111 1111 -> 36FF
//  11: ADDI R3,1    -> 1011 011 000000001       -> 1011 0110 0000 0001 -> B601
//  12: ADDI R4,0xFF -> 1011 100 011111111       -> 1011 1000 1111 1111 -> B8FF
//  13: LDI  R5,0x2A -> 0011 101 000101010       -> 0011 1010 0010 1010 -> 3A2A
//  16: MOV  LR,R5   -> 1100 101 000000 001      -> 1100 1010 0000 0001 -> CA01
//  17: MOV  R6,LR   -> 1100 110 000000 000      -> 1100 1100 0000 0000 -> CC00
//  18: MOV  R7,LR   -> 1100 111 000000 000      -> 1100 1110 0000 0000 -> CE00
//  19: ADDI R7,1    -> 1011 111 000000001       -> 1011 1110 0000 0001 -> BE01
//
// Run with Icarus (adjust the file list to your actual module filenames):
//   iverilog -o proc_sim alu.v reg_bank.v pc_register.v sp_unit.v lr_reg.v \
//     flags_reg.v sign_extension_unit.v instr_mem.v data_memory.v \
//     control_unit_pipelined.v mux2to1.v mux4to1.v simple_adder.v gie_reg.v \
//     forwarding_unit.v hazard_detection_unit.v if_id_reg.v id_ex_reg.v \
//     ex_mem_reg.v mem_wb_reg.v processor_pipel_haz.v addi_lr_tb.v
//   vvp proc_sim
// -----------------------------------------------------------------------
`timescale 1ns/1ps

module addi_lr_tb;

    reg clk, rst_n;
    integer errors = 0;

    processor_pipel_haz uut (
        .clk   (clk),
        .rst_n (rst_n)
    );

    always #5 clk = ~clk;

    task check8(input [255:0] name, input [7:0] actual, input [7:0] expected);
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s = 0x%02h, expected 0x%02h", name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = 0x%02h", name, actual);
            end
        end
    endtask

    initial begin
        clk   = 0;
        rst_n = 0;

//        uut.u_imem.mem[0]  = 16'h3005; // LDI  R0,5
        uut.u_imem.mem[0]  = 16'h3a05; // LDI  R5,5
        uut.u_imem.mem[1]  = 16'h0000; // NOP
        uut.u_imem.mem[2]  = 16'h0000; // NOP
//        uut.u_imem.mem[3]  = 16'hC001; // MOV  LR,R0
        uut.u_imem.mem[3]  = 16'hCa01; // MOV  LR,R5
        uut.u_imem.mem[4]  = 16'h0000; // NOP
        uut.u_imem.mem[5]  = 16'h0000; // NOP
        uut.u_imem.mem[6]  = 16'hC200; // MOV  R1,LR
        uut.u_imem.mem[7]  = 16'hB40A; // ADDI R2,10
        uut.u_imem.mem[8]  = 16'h36FF; // LDI  R3,0xFF
        uut.u_imem.mem[9]  = 16'h0000; // NOP
        uut.u_imem.mem[10] = 16'h0000; // NOP
        uut.u_imem.mem[11] = 16'hB601; // ADDI R3,1   (0xFF+1 -> wrap)
        uut.u_imem.mem[12] = 16'hB8FF; // ADDI R4,0xFF (negative imm)
        uut.u_imem.mem[13] = 16'h3A2A; // LDI  R5,0x2A
        uut.u_imem.mem[14] = 16'h0000; // NOP
        uut.u_imem.mem[15] = 16'h0000; // NOP
        uut.u_imem.mem[16] = 16'hCA01; // MOV  LR,R5
        uut.u_imem.mem[17] = 16'hCC00; // MOV  R6,LR  (back-to-back write->read)
        uut.u_imem.mem[18] = 16'hCE00; // MOV  R7,LR
        uut.u_imem.mem[19] = 16'hBE01; // ADDI R7,1   (fwd bug regression)

        #12 rst_n = 1;

        // Enough cycles to drain 20 instructions through 5 stages, with margin.
        repeat (45) @(posedge clk);
        #1;

        // ---- MOV Rd,LR / MOV LR,Rd round-trip ----
        check8("R1 (MOV Rd,LR round-trip)", uut.u_rf.regs[1], 8'd5);   // fix
        check8("LR  (MOV LR,Rd)", uut.lr_out, 8'h2A);   // was 8'd5

        // ---- Basic ADDI ----
        check8("R2 (ADDI basic)",                         uut.u_rf.regs[2], 8'd10);

        // ---- ADDI 8-bit overflow / wrap ----
        check8("R3 (ADDI 8-bit overflow wrap)",           uut.u_rf.regs[3], 8'h00);

        // ---- ADDI negative immediate (sign-extension boundary) ----
        check8("R4 (ADDI negative immediate)",            uut.u_rf.regs[4], 8'hFF);

        // ---- MOVLR write immediately followed by read, back-to-back ----
        check8("R6 (MOVLR write->read back-to-back)",     uut.u_rf.regs[6], 8'h2A);

        // ---- Forwarding regression: MOV Rd,LR consumed by very next instr ----
        check8("R7 (MOVLR read + ADDI, EX/MEM fwd)",      uut.u_rf.regs[7], 8'h2B);

        if (errors == 0)
            $display("\n=== ALL TESTS PASSED ===");
        else
            $display("\n=== %0d TEST(S) FAILED ===", errors);

        $finish;
    end

endmodule