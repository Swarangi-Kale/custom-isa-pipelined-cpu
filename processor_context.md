# Custom 16-bit Pipelined Processor — Context for Top-Level Datapath Build

This document hands off everything needed to write the top-level Verilog module
that instantiates and wires together the already-built, already-tested modules
for this processor. All modules below are complete and individually verified
with passing self-checking testbenches (Icarus Verilog). **The task remaining
is: instantiate them into one top-level module and wire them per the control-
signal map in this document.**

Current build phase: **single-cycle datapath** (no pipeline registers yet).
Pipelining (IF/ID, ID/EX, EX/MEM, MEM/WB registers), the Hazard Detection Unit,
and the Forwarding Unit are explicitly deferred to a later phase, per the
project's own build order — do not add them now.

---

## 1. Processor overview

| Property | Value |
|---|---|
| Data width | 8-bit |
| Instruction width | 16-bit, fixed-width |
| Target pipeline (future phase) | Classic 5-stage: IF, ID, EX, MEM, WB |
| Current build phase | Single-cycle datapath (no pipeline registers yet) |
| GPR count | 8 (R0–R7), 3-bit index fields, none hardwired to zero |
| Dedicated (non-GPR) registers | SP, LR, Flags (Z,C,N) + shadow, GIE |
| PC / instruction memory address width | 8-bit (256-word address space), confirmed final |
| Instruction memory | 256 x 16-bit, PC-addressed |
| Data memory | 256 x 8-bit |

Addressing is **word-addressed**: PC increments by exactly 1 per instruction
(not by 2). Branch/jump offsets and targets are therefore used **directly, with
no shift** — a MIPS-style shift-left-2 would be wrong here since PC already
counts instructions, not bytes.

---

## 2. Instruction formats (finalized)

All instructions are 16 bits. Opcode is always `instr[15:12]`.

```
Bit:        15  14  13  12 | 11  10  9  |  8   7   6  |  5   4   3   2   1   0
R-type:     [   opcode[4] ]|[  rd[3]   ]|[  rs1[3]   ]|[ rs2[3] ][ funct[3] ]
I-type:     [   opcode[4] ]|[  rd[3]   ]|[  rs1[3]   ]|[      imm[6]        ]
LDI-type:   [   opcode[4] ]|[  rd[3]   ]|[          imm[9]                 ]
B-type:     [   opcode[4] ]|[  rs2[3]  ]|[  rs1[3]   ]|[     offset[6](from curr instr)      ]
J-type:     [   opcode[4] ]|[         addr[12]                             ]
SP-imm:     [   opcode[4] ]|[  (unused)]|[          imm[9], only [7:0] used (ADDSP) ]
SP-mem:     [   opcode[4] ]|[  reg[3]  ]|[ dir[1] ]|[      offset[8]         ]
SPEC-type:  [   opcode[4] ]|[  reg[3]  ]|[         (unused, 6 bits)         ]|[ (unused) ][sel][dir]
```

**Field-consistency** (deliberate, load-bearing for the datapath wiring below):
- `rd` is always at bits `[11:9]` in every format that has a destination
  (R-type, I-type, LDI-type) — and, not coincidentally, this is also where
  I-type's SW and SP-mem's STORESP put the register being **read** as a store
  source, and where B-type puts its **second compared register**. All of these
  route through the same bit position.
- `rs1` is always at bits `[8:6]` in every format that has it (R-type, I-type,
  B-type).
- `rs2` (R-type only) is at bits `[5:3]`.
- `funct` (R-type only) is at bits `[2:0]`.

This is why the datapath only needs ONE 2-way mux on the register file's
`rs2_addr` port (selecting between bit position `[5:3]` and `[11:9]`) rather
than per-instruction special-casing — see Section 5.

---

## 3. Opcode / funct table (finalized — includes a correction to the original spec)

| Mnemonic | Format | Opcode | Funct | Notes |
|---|---|---|---|---|
| ADD Rd, Rs1, Rs2 | R | `0000` | **`101`** | **Moved from 000 to 101** (see below). Sets Z,C,N. |
| SUB Rd, Rs1, Rs2 | R | `0000` | `001` | Sets flags; also backs BEQ/BNE comparisons |
| SHL Rd, Rs1, Rs2 | R | `0000` | `010` | Shift amount = Rs2 value; zero-fill |
| SHR Rd, Rs1, Rs2 | R | `0000` | `011` | Logical (unsigned) right shift, zero-fill |
| SHRA Rd, Rs1, Rs2 | R | `0000` | `100` | Arithmetic (signed) right shift, sign-fill |
| **NOP (all-zero word)** | R | `0000` | **`000`** | **New, deliberate**: freed by moving ADD to 101. `rd_we` and `flags_we` are explicitly suppressed for this exact `{opcode,funct}` pair in the Control Unit. |
| LW Rd, [Rs1+imm] | I | `0001` | — | Register-indirect + 6-bit signed offset |
| SW [Rs1+imm], Rd | I | `0010` | — | Same addressing as LW |
| LDI Rd, imm | LDI | `0011` | — | 9-bit signed immediate field; only low 8 bits meaningful |
| BNE Rs1, Rs2, offset | B | `0100` | — | |
| BEQ Rs1, Rs2, offset | B | `0101` | — | |
| JMP addr | J | `0110` | — | Unconditional; absolute target, no shift |
| RETI | J | `0111` | — | addr field unused; see Section 6 |
| ADDSP imm | SP-imm | `1000` | — | 12-bit field; only low 8 bits meaningful |
| STORESP/LOADSP Rd, offset | SP-mem | `1001` | — | dir_bit: 0 = STORESP, 1 = LOADSP |
| ADDI                     | -|`1011`|- | - |
| MOV (for LR)             | - |`1100`| - |(covers MOV Rd,LR / MOV LR,Rd / MOV Rd,SP / MOV SP,Rd) |
| *(reserved)* | — | `1011`–`1111` | — | 5 opcodes free. Control Unit's `default` case leaves everything inert for these. |

**Why ADD moved to funct 101**: the all-zero instruction word (`16'h0000`) used
to decode as `ADD R0,R0,R0` under the original encoding, meaning unprogrammed/
padding instruction memory silently executed a real, flag-setting instruction.
Moving ADD to the previously-free funct `101` frees up `opcode=0000,funct=000`
to serve as a true NOP.

**Field-width decisions (finalized after discussion)**: LDI's `imm[9]`,
SP-mem's `offset[9]`, ADDSP's `imm[12]`, and J-type's `addr[12]` are all wider
than the 8-bit values they ultimately produce. This is intentional encoding-
space allocation from a fixed 16-bit instruction (unused width costs nothing
extra), **not** a hardware ambiguity — in every case, only the low 8 bits
(`instr[7:0]`) are architecturally meaningful; any higher bits are ignored by
the Sign-Extension Unit, not extended. I-type's `imm[6]` and B-type's
`offset[6]` are the only fields **narrower** than 8 bits and are the only ones
genuinely sign-extended (bit-replicated), not sliced.

funct[1] (i.e. instr[1]): which special register — 0=LR, 1=SP
funct[0] (i.e. instr[0]): direction — 0=read (MOV Rd,LR/SP), 1=write (MOV LR/SP,Rd)

---

## 4. Modules already built and verified (exact port lists)

All of the following compile and pass their own self-checking Icarus Verilog
testbenches. Use these exact port names/widths when instantiating.

### `alu.v`
```verilog
module alu (
    input  wire [7:0] alu_in_a,
    input  wire [7:0] alu_in_b,
    input  wire [2:0] alu_funct,     // 101=ADD 001=SUB 010=SHL 011=SHR 100=SHRA
    output reg  [7:0] alu_result,
    output wire       flag_z,
    output wire       flag_c,
    output wire       flag_n
);
```
Combinational. SUB's carry convention: `C=1` means no borrow (`a>=b`).

### `register_file.v`
```verilog
module register_file (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [2:0] rs1_addr,
    input  wire [2:0] rs2_addr,
    output wire [7:0] rs1_rdata,
    output wire [7:0] rs2_rdata,
    input  wire [2:0] rd_addr,
    input  wire [7:0] rd_wdata,
    input  wire       rd_we
);
```
8 x 8-bit GPRs. Reads asynchronous/combinational; write synchronous. **No
write-first bypass** — a same-cycle read of the address being written returns
the OLD value. (Not an issue yet: no pipeline overlap exists in this
single-cycle phase. Will matter once pipelining is added — flagged for later,
not fixed now.)

### `pc_register.v`
```verilog
module pc_register (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       pc_write_en,       // 1=advance PC+1; 0=hold (stall, unused yet)
    input  wire       pc_redirect,       // 1=load pc_redirect_addr instead of PC+1
    input  wire [7:0] pc_redirect_addr,
    output reg  [7:0] pc_out
);
```
Reset vector: address 0. **`pc_redirect` has priority over `pc_write_en`** if
both were ever asserted together.

### `sp_unit.v`
```verilog
module sp_unit #(
    parameter [7:0] SP_RESET_VAL = 8'h00
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       sp_we,        // 1=commit adder result into SP (ADDSP only)
    input  wire [7:0] sp_addend,    // signed 8-bit addend, already from the SEU
    output wire [7:0] sp_out,       // current committed SP value
    output wire [7:0] sp_addr_out   // SP + sp_addend (STORESP/LOADSP address, or
                                     // the value ADDSP would commit)
);
```
Dedicated adder, separate from the main ALU. Same `sp_addend` port and adder
serve both ADDSP (destructive, `sp_we=1`) and STORESP/LOADSP (non-destructive
address calc, `sp_we=0`).

### `lr_register.v`
```verilog
module lr_register (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       lr_we,     // driven by future interrupt-entry hw — NOT driven yet
    input  wire [7:0] lr_wdata,
    output wire [7:0] lr_out     // read by RETI
);
```
No current instruction writes this. Tie `lr_we`/`lr_wdata` to inactive
(`lr_we=0`) at the top level for now — there's no source for them yet.

### `flags_register.v`
```verilog
module flags_register (
    input  wire clk,
    input  wire rst_n,
    input  wire flags_we,        // from Control Unit; R-type ALU ops only
    input  wire alu_z,
    input  wire alu_c,
    input  wire alu_n,
    input  wire shadow_save,     // future interrupt-entry hw — NOT driven yet
    input  wire shadow_restore,  // from Control Unit; RETI only
    output wire flag_z,
    output wire flag_c,
    output wire flag_n,
    output wire shadow_z,
    output wire shadow_c,
    output wire shadow_n
);
```
`shadow_restore` has priority over a concurrent `flags_we`. Tie `shadow_save=0`
at the top level for now (no interrupt-entry hardware exists yet).

### `sign_extension_unit.v`
```verilog
module sign_extension_unit (
    input  wire [15:0] instr,       // full 16-bit instruction
    input  wire [2:0]  format_sel,  // from Control Unit
    output reg  [7:0]  ext_value
);
```
`format_sel` encoding (must match Control Unit exactly — see Section 5):
`000`=I-type (sign-extend `instr[5:0]`), `001`=B-type (sign-extend
`instr[5:0]`), `010`=LDI (`instr[7:0]`), `011`=SP-mem (`instr[7:0]`),
`100`=J-type (`instr[7:0]`), `101`=SP-imm/ADDSP (`instr[7:0]`).

### `instruction_memory.v`
```verilog
module instruction_memory #(
    parameter MEM_DEPTH = 256,
    parameter INIT_FILE = ""   // optional $readmemh path
) (
    input  wire [7:0]  addr,       // PC value
    output wire [15:0] instr_out
);
```
ROM-like, no runtime write port. Combinational read. Default fill `16'h0000`
is now the intended NOP (see Section 3) — this is correct and current, not a
leftover concern.

### `data_memory.v`
```verilog
module data_memory #(
    parameter MEM_DEPTH = 256
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] addr,
    input  wire [7:0] wdata,
    input  wire       we,
    input  wire       re,      // gates rdata to 0 when low; doesn't gate the array itself
    output wire [7:0] rdata
);
```
Synchronous write, combinational read (same old-value-on-write-cycle behavior
as the register file, same reasoning — not an issue yet).

### `control_unit.v`
```verilog
module control_unit (
    input  wire [3:0] opcode,
    input  wire [2:0] funct,
    input  wire       flag_z,          // live ALU Z output, needed for BEQ/BNE

    output reg  [2:0] alu_funct,
    output reg        alu_src_b_sel,   // 0=rs2_rdata  1=ext_value
    output reg        rs2_addr_sel,    // 0=instr[5:3] 1=instr[11:9]
    output reg  [1:0] wb_sel,          // 00=ALU result 01=dmem rdata 10=ext_value
    output reg        dmem_addr_sel,   // 0=ALU result  1=sp_addr_out
    output reg        dmem_we,
    output reg        dmem_re,
    output reg        rd_we,
    output reg        flags_we,
    output reg        sp_we,
    output reg  [2:0] format_sel,
    output reg        pc_redirect,
    output reg  [1:0] pc_target_sel,   // 00=branch target 01=jump target 10=LR
    output reg        shadow_restore,
    output reg        gie_set,
    output wire       lr_we,           // tied to 0 internally — reserved, unused
    output wire       shadow_save      // tied to 0 internally — reserved, unused
);
```
Pure combinational decode from `{opcode, funct}` plus live `flag_z`. Full
per-opcode signal truth table is in Section 5 below — this is the master
reference for wiring every mux and enable in the top-level file.

### `mux2to1.v` (generic, already exists per user)
```verilog
module mux2to1 #(
    parameter WIDTH = 8
) (
    input  wire             sel,
    input  wire [WIDTH-1:0] in0,
    input  wire [WIDTH-1:0] in1,
    output wire [WIDTH-1:0] out
);
```

### `mux4to1.v` (generic, already exists per user)
```verilog
module mux4to1 #(
    parameter WIDTH = 8
) (
    input  wire [1:0]       sel,
    input  wire [WIDTH-1:0] in0,
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [WIDTH-1:0] in3,
    output reg  [WIDTH-1:0] out
);
```

### `branch_target_adder.v`
```verilog
module branch_target_adder (
    input  wire [7:0] pc_in,
    input  wire [7:0] offset,     // sign-extended B-type offset from the SEU
    output wire [7:0] branch_target
);
```
Purely combinational. Separate from the main ALU because the ALU is busy doing
the SUB-based BEQ/BNE comparison in the same cycle.

### `gie_register.v`
```verilog
module gie_register (
    input  wire clk,
    input  wire rst_n,
    input  wire gie_set,    // from Control Unit, RETI only
    input  wire gie_clear,  // future interrupt-taken hw — NOT driven yet
    output wire gie_out
);
```
Reset value 0 (interrupts disabled at reset). Tie `gie_clear=0` at the top
level for now.

**Note**: 5 named mux wrapper files (`alu_src_b_mux.v`, `rs2_addr_mux.v`,
`wb_mux.v`, `dmem_addr_mux.v`, `pc_target_mux.v`) were designed but are **not
being created as separate files** — instantiate `mux2to1`/`mux4to1` directly
inline in the top-level processor file instead, per the widths/connections in
Section 5.

---

## 5. Complete control signal → mux/module wiring map

This is the authoritative list of every mux the top-level file must instantiate
and every signal that must be connected, cross-checked against
`control_unit.v`'s actual outputs. **Nothing here should be treated as
optional** — this list was explicitly verified for completeness.

### Instruction field wiring (direct, no mux — field-consistency)
- `opcode` = `instr[15:12]` → Control Unit
- `funct` = `instr[2:0]` → Control Unit
- `alu.alu_funct` comes from Control Unit's `alu_funct` output (NOT wired
  directly from `instr[2:0]`) — Control Unit passes `funct` through for
  R-type but overrides it for LW/SW (forces ADD) and BEQ/BNE (forces SUB),
  since those formats have no real funct field of their own.
- `rd_addr` (register file write port) = `instr[11:9]` always, gated by `rd_we`.
- `rs1_addr` (register file) = `instr[8:6]` always (unused/harmless for formats
  without rs1).

### Mux 1 — register file `rs2_addr` source (`mux2to1`, WIDTH=3)
- `sel` = `control_unit.rs2_addr_sel`
- `in0` = `instr[5:3]` (R-type)
- `in1` = `instr[11:9]` (B-type's rs2, SW's/STORESP's store-source register)
- `out` → `register_file.rs2_addr`

### Mux 2 — ALU operand B (`mux2to1`, WIDTH=8)
- `sel` = `control_unit.alu_src_b_sel`
- `in0` = `register_file.rs2_rdata`
- `in1` = `sign_extension_unit.ext_value`
- `out` → `alu.alu_in_b`

`alu.alu_in_a` is always `register_file.rs1_rdata` directly (no mux).

### Mux 3 — write-back data (`mux4to1`, WIDTH=8)
- `sel` = `control_unit.wb_sel`
- `in0` = `alu.alu_result`
- `in1` = `data_memory.rdata`
- `in2` = `sign_extension_unit.ext_value`
- `in3` = tie to `8'b0` (unused, `wb_sel=11` never asserted)
- `out` → `register_file.rd_wdata`

### Mux 4 — Data Memory address (`mux2to1`, WIDTH=8)
- `sel` = `control_unit.dmem_addr_sel`
- `in0` = `alu.alu_result` (LW/SW: rs1+imm)
- `in1` = `sp_unit.sp_addr_out` (STORESP/LOADSP)
- `out` → `data_memory.addr`

### Mux 5 — PC redirect target (`mux4to1`, WIDTH=8)
- `sel` = `control_unit.pc_target_sel`
- `in0` = `branch_target_adder.branch_target`
- `in1` = `sign_extension_unit.ext_value` (JMP's target, already absolute, no adder)
- `in2` = `lr_register.lr_out` (RETI)
- `in3` = tie to `8'b0` (unused, `pc_target_sel=11` never asserted)
- `out` → `pc_register.pc_redirect_addr`

`pc_register.pc_redirect` = `control_unit.pc_redirect` directly (no mux — it's
already a single combined enable).

### Branch-target adder inputs
- `branch_target_adder.pc_in` = `pc_register.pc_out`
- `branch_target_adder.offset` = `sign_extension_unit.ext_value`
  (valid only when `format_sel`=B-type; harmless otherwise since only consumed
  via Mux 5 when `pc_target_sel=00`, which only happens for BEQ/BNE)

### Data Memory write data (no mux)
- `data_memory.wdata` = `register_file.rs2_rdata` directly (using the SAME
  rs2_addr-mux-selected read port as Mux 1 above — for SW/STORESP, that read
  address is already routed to `instr[11:9]`, i.e. the "Rd" position acting as
  a source register). No separate mux needed here.

### Flags register inputs (no mux)
- `alu_z/c/n` = `alu.flag_z/flag_c/flag_n` directly
- `flags_we` = `control_unit.flags_we`
- `shadow_restore` = `control_unit.shadow_restore`
- `shadow_save` = tie to `1'b0` (reserved, no driver yet)

### SP Unit inputs (no mux)
- `sp_unit.sp_addend` = `sign_extension_unit.ext_value` directly (valid when
  `format_sel` = SP-imm or SP-mem; both ADDSP and STORESP/LOADSP share this one
  port, distinguished only by `sp_we`)
- `sp_unit.sp_we` = `control_unit.sp_we`

### LR Register inputs (no mux, currently inert)
- `lr_we` = tie to `1'b0` (no interrupt-entry hardware yet)
- `lr_wdata` = don't-care / tie to `8'b0` (unused while `lr_we=0`)

### GIE Register inputs (no mux)
- `gie_set` = `control_unit.gie_set`
- `gie_clear` = tie to `1'b0` (no interrupt-taken hardware yet)

### Format-select and sign-extension
- `sign_extension_unit.instr` = the full fetched instruction
- `sign_extension_unit.format_sel` = `control_unit.format_sel` directly

### PC advance / stall
- `pc_register.pc_write_en` = tie to `1'b1` for now (no Hazard Detection Unit
  yet — nothing stalls in this phase)

---

## 6. Instantiation checklist (one of each, single-cycle datapath)

| # | Module | Notes |
|---|---|---|
| 1 | `pc_register` | |
| 2 | `instruction_memory` | address = `pc_register.pc_out` |
| 3 | `control_unit` | |
| 4 | `sign_extension_unit` | |
| 5 | `register_file` | |
| 6 | `alu` | |
| 7 | `sp_unit` | |
| 8 | `lr_register` | inert for now |
| 9 | `flags_register` | |
| 10 | `data_memory` | |
| 11 | `gie_register` | inert `gie_clear` for now |
| 12 | `branch_target_adder` | |
| 13 | `mux2to1` x3 | rs2_addr (W=3), ALU-B (W=8), dmem_addr (W=8) |
| 14 | `mux4to1` x2 | wb_mux (W=8), pc_target_mux (W=8) |

That's the complete module set for this phase — nothing else should be
instantiated (no hazard/forwarding logic, no pipeline registers).

---

## 7. Explicitly deferred — do NOT build as part of this task

- **Pipelining**: IF/ID, ID/EX, EX/MEM, MEM/WB pipeline registers. This is a
  single-cycle datapath for now.
- **Hazard Detection Unit**: GPR load-use hazard + SP interlock (two
  independent, OR'd conditions — kept separate deliberately, never merge them).
- **Forwarding Unit**: EX/MEM→EX and MEM/WB→EX paths.
- **Interrupt-entry hardware**: the FSM/logic that would actually assert
  `lr_we`, `shadow_save`, and `gie_clear` on a real interrupt. None of these
  three signals has a live driver yet — tie them inactive at the top level.
  This also means **RETI's decode path can be wired up now, but it is not
  meaningfully end-to-end testable** until this hardware exists later — expect
  `lr_out` to only ever read back whatever inert/reset value `lr_register`
  holds.
- **Banked register sets / hardware context save** (Section 8 milestone) —
  out of scope entirely for now.

---

## 8. Testing expectations for the top-level module

Every module above already has its own passing testbench. The new task is a
**structural/integration test**: write a small hand-assembled test program
(a sequence of 16-bit hex instruction words, matching Section 3's opcode
table), preload it into `instruction_memory` (via `INIT_FILE` or direct
`mem[]` pokes in a testbench, consistent with how `instruction_memory_tb.v`
already does this), run the clock, and confirm register/memory/flag state
matches hand-computed expected results after each instruction. Suggested
minimal program to prove the datapath: a couple of ADD/SUB instructions, an
LDI, a taken and a not-taken branch, a JMP, and a STORESP/LOADSP round-trip.
