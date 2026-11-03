`timescale 1ns/1ps
// -----------------------------------------------------------------------
// sp_roundtrip_tb.v
// Round-trip test for the merged STORESP/LOADSP opcode, ADDSP, and the
// MOV SPEC (SP read/write) datapath.
//
// SP0 is captured live from the DUT after reset rather than assumed,
// since SP_RESET_VAL is a parameter this TB doesn't hardcode.
//
// Encodings (hand-derived, verified nibble-by-nibble):
//   LDI R1,0xAA        -> 32AA
//   STORESP R1,#0      -> 9200   (dir=0: store)
//   MOV  R2,SP  (read) -> C402   (funct=010: SP,read)
//   ADDSP #-1          -> 80FF
//   MOV  R3,SP         -> C602
//   LDI  R4,0x55       -> 3855
//   STORESP R4,#0      -> 9800
//   LOADSP  R5,#0      -> 9B00   (dir=1: load)
//   LOADSP  R6,#1      -> 9D01
//   ADDSP #+1          -> 8001
//   MOV  R1,SP         -> C202
//   LDI  R7,0x10       -> 3E10
//   MOV  SP,R7 (write) -> CE03   (funct=011: SP,write)
//   MOV  R6,SP         -> CC02
//   MOV  R5,SP         -> CA02
//   ADDI R5,#5 (no NOP -> distance-1 EX/MEM forward of SP-sourced value)
//                      -> BA05
//
// ASSUMPTIONS (verify against your files):
//   - uut.u_sp.sp_out is the hierarchical path to sp_unit's raw SP value
//   - uut.u_dmem.mem[addr] is data_memory's array
//   - uut.u_rf.regs[n] is reg_bank's array


// bugs faced = forgetting to initialize wires to zero, the checks are placed at the wrong time
// -----------------------------------------------------------------------
module sp_roundtrip_tb;

    reg clk, rst_n;
    integer errors = 0;
    integer i;
    reg [7:0] sp0;

    processor_pipel_haz uut (
        .clk    (clk),
        .rst_n  (rst_n),
        .irq_in (1'b0)
    );

    always #5 clk = ~clk;

    task check8(input [255:0] name, input [7:0] a, input [7:0] e);
        begin
            if (a !== e) begin
                $display("FAIL: %0s = 0x%02h, expected 0x%02h", name, a, e);
                errors = errors + 1;
            end else $display("PASS: %0s = 0x%02h", name, a);
        end
    endtask

    initial begin
        clk = 0; rst_n = 0;

        for (i = 0; i < 256; i = i + 1) uut.u_imem.mem[i] = 16'h0000;

        uut.u_imem.mem[0]  = 16'h32AA; // LDI  R1,0xAA
        uut.u_imem.mem[3]  = 16'h9200; // STORESP R1,#0   ; mem[SP0+0]=0xAA
        uut.u_imem.mem[6]  = 16'hC402; // MOV  R2,SP      ; R2=SP0
        uut.u_imem.mem[7]  = 16'h80FF; // ADDSP #-1       ; SP=SP0-1
        uut.u_imem.mem[10] = 16'hC602; // MOV  R3,SP      ; R3=SP0-1
        uut.u_imem.mem[11] = 16'h3855; // LDI  R4,0x55
        uut.u_imem.mem[14] = 16'h9800; // STORESP R4,#0   ; mem[SP0-1+0]=0x55
        uut.u_imem.mem[17] = 16'h9B00; // LOADSP  R5,#0   ; R5=0x55
        uut.u_imem.mem[18] = 16'h9D01; // LOADSP  R6,#1   ; R6=0xAA
        uut.u_imem.mem[19] = 16'h8001; // ADDSP #+1       ; SP=SP0
        uut.u_imem.mem[22] = 16'hC202; // MOV  R1,SP      ; R1=SP0 (post-restore)
        uut.u_imem.mem[23] = 16'h3E10; // LDI  R7,0x10
        uut.u_imem.mem[26] = 16'hCE03; // MOV  SP,R7      ; SP=0x10
        uut.u_imem.mem[29] = 16'hCC02; // MOV  R6,SP      ; R6=0x10
        uut.u_imem.mem[30] = 16'hCA02; // MOV  R5,SP      ; R5=0x10
        uut.u_imem.mem[31] = 16'hBA05; // ADDI R5,#5      ; R5=0x15 (fwd test, no NOP)

        #12 rst_n = 1;

        // Capture SP0 before any instruction touches SP (instr 7 is the
        // first to change it, so anytime before that is safe).
        repeat (4) @(posedge clk); #1;
        sp0 = uut.u_sp.sp_out;
        $display("INFO: captured SP0 = 0x%02h", sp0);

        // ---- Checkpoint A: ADDSP round trip + STORESP/LOADSP addressing ----
        repeat (19) @(posedge clk); #1;
        check8("R1 (pre-restore, =0xAA)",     uut.u_rf.regs[1], 8'hAA);
        check8("R2 (SP0)",                    uut.u_rf.regs[2], sp0);
        check8("R3 (SP0-1)",                  uut.u_rf.regs[3], sp0 - 8'd1);
        check8("R4 (0x55)",                   uut.u_rf.regs[4], 8'h55);
        check8("R5 (LOADSP from SP0-1+0)",    uut.u_rf.regs[5], 8'h55);
        check8("R6 (LOADSP from SP0-1+1)",    uut.u_rf.regs[6], 8'hAA);
        check8("mem[SP0-1] (STORESP R4)",     uut.u_dmem.mem[sp0-8'd1],   8'h55);
        check8("mem[SP0]   (STORESP R1)",     uut.u_dmem.mem[sp0],        8'hAA);
        
        // ---- Checkpoint A2: ADDSP restore, checked BEFORE MOV SP,R7 overwrites it ----
        repeat (4) @(posedge clk); #1;   // enough cycles for instr 19 to reach WB, not enough to reach instr 26
        check8("R1 (SP restored to SP0)",     uut.u_rf.regs[1], sp0);
        check8("SP after ADDSP #+1 (raw)",    uut.u_sp.sp_out,  sp0);
        
        // ---- Checkpoint B: MOV SP,Rd write path ----
        repeat (8) @(posedge clk); #1;   // remaining cycles to reach instr 26 and beyond
        check8("R6 (MOV SP,R7 then MOV R6,SP -> 0x10)", uut.u_rf.regs[6], 8'h10);
        check8("SP after MOV SP,R7 (raw)",    uut.u_sp.sp_out,  8'h10);
        
        // ---- Checkpoint C: distance-1 EX/MEM forward of SP-sourced value ----
        repeat (4) @(posedge clk); #1;
        check8("R5 (MOV R5,SP + ADDI, fwd)",  uut.u_rf.regs[5], 8'h15);

        if (errors == 0) $display("\n=== ALL SP ROUND-TRIP TESTS PASSED ===");
        else             $display("\n=== %0d TEST(S) FAILED ===", errors);
        $finish;
    end

endmodule