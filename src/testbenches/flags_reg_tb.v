// flags_reg_tb.v
// -----------------------------------------------------------------------
// Self-checking testbench for flags_register.v. Covers reset, normal
// ALU-driven flag updates, hold when flags_we=0, shadow save (interrupt
// entry, simulated), shadow restore (RETI), and restore-over-write
// priority.
//
// Run with Icarus:
//   iverilog -o flags_sim flags_register.v flags_register_tb.v
//   vvp flags_sim
// -----------------------------------------------------------------------

`timescale 1ns/1ps

module flags_reg_tb;

    reg clk;
    reg rst_n;
    reg flags_we;
    reg alu_z, alu_c, alu_n;
    reg shadow_save, shadow_restore;
    wire flag_z, flag_c, flag_n;
    wire shadow_z, shadow_c, shadow_n;

    integer errors = 0;
    integer tests  = 0;

    flags_reg dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .flags_we       (flags_we),
        .alu_z          (alu_z),
        .alu_c          (alu_c),
        .alu_n          (alu_n),
        .shadow_save    (shadow_save),
        .shadow_restore (shadow_restore),
        .flag_z         (flag_z),
        .flag_c         (flag_c),
        .flag_n         (flag_n),
        .shadow_z       (shadow_z),
        .shadow_c       (shadow_c),
        .shadow_n       (shadow_n)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [127:0] name;
        input exp_z, exp_c, exp_n;
        input exp_sz, exp_sc, exp_sn;
        begin
            tests = tests + 1;
            if (flag_z !== exp_z || flag_c !== exp_c || flag_n !== exp_n ||
                shadow_z !== exp_sz || shadow_c !== exp_sc || shadow_n !== exp_sn) begin
                errors = errors + 1;
                $display("FAIL [%0s]: flags=%b%b%b shadow=%b%b%b, expected flags=%b%b%b shadow=%b%b%b",
                    name, flag_z, flag_c, flag_n, shadow_z, shadow_c, shadow_n,
                    exp_z, exp_c, exp_n, exp_sz, exp_sc, exp_sn);
            end else begin
                $display("PASS [%0s]: flags=%b%b%b shadow=%b%b%b", name, flag_z, flag_c, flag_n, shadow_z, shadow_c, shadow_n);
            end
        end
    endtask

    initial begin
        rst_n          = 0;
        flags_we       = 0;
        alu_z = 0; alu_c = 0; alu_n = 0;
        shadow_save    = 0;
        shadow_restore = 0;

        // ---- Reset ----
        @(negedge clk); @(negedge clk);
        check("reset: all flags and shadow zero", 0,0,0, 0,0,0);
        rst_n = 1;

        // ---- flags_we=0: no change even if ALU flags are nonzero ----
        alu_z = 1; alu_c = 1; alu_n = 1;
        @(negedge clk);
        check("flags_we=0 holds all zero", 0,0,0, 0,0,0);

        // ---- Normal ALU-driven update ----
        flags_we = 1;
        alu_z = 1; alu_c = 0; alu_n = 1;
        @(negedge clk);
        check("normal update: Z=1 C=0 N=1", 1,0,1, 0,0,0);

        flags_we = 1;
        alu_z = 0; alu_c = 1; alu_n = 0;
        @(negedge clk);
        check("normal update: Z=0 C=1 N=0", 0,1,0, 0,0,0);

        // ---- Simulated interrupt entry: shadow_save snapshots current flags ----
        flags_we = 0;
        shadow_save = 1;
        @(negedge clk);
        check("shadow_save snapshots Z=0 C=1 N=0", 0,1,0, 0,1,0);

        // ---- ISR clobbers main flags while shadow holds the snapshot ----
        shadow_save = 0;
        flags_we = 1;
        alu_z = 1; alu_c = 1; alu_n = 1;
        @(negedge clk);
        check("ISR clobbers main flags; shadow untouched", 1,1,1, 0,1,0);

        flags_we = 0;
        @(negedge clk);
        check("shadow still holds pre-interrupt snapshot", 1,1,1, 0,1,0);

        // ---- RETI: shadow_restore brings back the snapshot ----
        shadow_restore = 1;
        @(negedge clk);
        check("shadow_restore (RETI) restores Z=0 C=1 N=0", 0,1,0, 0,1,0);

        // ---- Restore-over-write priority: both asserted same cycle ----
        shadow_restore = 1;
        flags_we = 1;
        alu_z = 1; alu_c = 1; alu_n = 1; // would set 1,1,1 if flags_we won
        @(negedge clk);
        check("shadow_restore wins over concurrent flags_we", 0,1,0, 0,1,0);

        // ---- Mid-run reset ----
        shadow_restore = 0;
        flags_we = 0;
        rst_n = 0;
        @(negedge clk);
        check("mid-run reset clears everything", 0,0,0, 0,0,0);

        // ---- Summary ----
        if (errors == 0)
            $display("\nALL %0d TESTS PASSED", tests);
        else
            $display("\n%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule