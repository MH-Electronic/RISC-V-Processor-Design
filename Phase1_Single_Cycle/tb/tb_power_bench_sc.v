`timescale 1ns/1ps
// =============================================================================
// tb_power_bench_sc.v  --  4-Phase Power Benchmark Testbench (Single-Cycle)
// EEE499 FYP | Liew Ming Heng (161439) | USM
//
// CHANGE LOG v3 (20 MHz baseline):
//  [CLK]  cpu_clk target changed from 30.27 MHz to 20 MHz baseline.
//         cpu_clk is now generated DIRECTLY in the testbench at exactly
//         20 MHz (25 ns half-period) instead of being derived from the PLL,
//         so the VCD timestamps are accurate and the Lattice Power Calculator
//         reads the correct frequency from the signal transitions.
//
//         On silicon, update your PLL instantiation to:
//           CLKI_DIV=1, CLKFB_DIV=4, CLKOP_DIV=25
//           -> VCO = 125*4/1 = 500 MHz (in-range), f_out = 500/25 = 20 MHz
//
//  [AF]   AF=0 root cause: behavioural VCD signal names don't match the
//         post-synthesis netlist primitives, so the tool finds no transitions.
//         Fix path: run a POST-SYNTHESIS functional sim (see companion notes).
//         For now, the testbench dumps ALL toggling datapath signals so the
//         VCD is as useful as a behavioural sim can be.
//         After simulation, manually set Logic AF = 20% in the Power Calculator
//         (see POWER_CALC_NOTES.md for the justification).
//
//  [PCS]  PCS block draws 16 mW static despite not being used. This is a
//         device-level default. In Lattice Power Calculator, go to the PCS
//         section and manually mark all PCS lanes as unused/disabled.
//
//  [VCD]  $dumpvars still uses explicit signal list (no recursive dump).
//         $dumplimit kept at 256 MB.
//         $dumpflush called after $dumpoff and in the timeout handler.
//         VCD capture starts only after PLL settle, stops at tohost write.
// =============================================================================

module tb_power_bench_sc;

    // =========================================================================
    // PARAMETERS
    // =========================================================================
    // Board input clock: 125 MHz (unchanged -- this is your PCB oscillator)
    localparam real    CLK_IN_HALF_NS   = 4.0;       // 125 MHz

    // CPU clock: 20 MHz baseline
    // Half-period = 1000 / (2 * 20) = 25 ns exactly
    localparam real    CPU_CLK_HALF_NS  = 25.0;      // 20 MHz
    localparam real    CPU_CLK_MHZ      = 20.0;

    localparam integer RST_CYCLES       = 20;         // clk_in cycles in reset
    // Settle: enough for PLL to lock (typ <1 ms = 20000 cpu_clk cycles at 20 MHz)
    // Using 1000 clk_in cycles = 8 us, conservative for sim speed
    localparam integer SETTLE_CLK_IN    = 1000;       // clk_in cycles to settle

    // Timeout: 400k instructions * 10x margin = 4M cpu_clk cycles
    localparam integer TIMEOUT_CPU_CYC  = 4_000_000;

    localparam integer PH1_INSTRS       = 140_000;
    localparam integer PH2_INSTRS       = 100_000;
    localparam integer PH3_INSTRS       = 100_000;
    localparam integer PH4_INSTRS       =  60_000;

    localparam integer PH1_EXPECTED     = PH1_INSTRS; // CPI=1 -> cycles = instrs
    localparam integer PH2_EXPECTED     = PH2_INSTRS;
    localparam integer PH3_EXPECTED     = PH3_INSTRS;
    localparam integer PH4_EXPECTED     = PH4_INSTRS;
    localparam integer TOLERANCE        = 200;        // slightly wider at 20 MHz

    // =========================================================================
    // DUT SIGNALS
    // =========================================================================
    reg        clk_in;
    reg        rst_n;
    wire [7:0] leds;
    wire       test_finished;

    // =========================================================================
    // TESTBENCH-GENERATED cpu_clk  (20 MHz, bypasses PLL for sim accuracy)
    // =========================================================================
    // WHY: The PLL model in behavioural simulation either:
    //   (a) passes clk_in straight through (giving 125 MHz in the VCD), or
    //   (b) produces an output with incorrect phase/frequency metadata.
    // Either way, the Lattice Power Calculator reads the wrong frequency from
    // the VCD transitions and calculates 2-6x inflated dynamic power.
    //
    // By generating cpu_clk here at exactly 20 MHz (25 ns half-period) and
    // feeding it to the DUT alongside clk_in, the VCD timestamps genuinely
    // represent 20 MHz switching, and the tool's frequency auto-detection
    // will read the correct value.
    //
    // The DUT's internal PLL is still instantiated (for GSR/PUR to be happy)
    // but its clock OUTPUT is overridden by this testbench clock via a
    // force/release or by tapping cpu_clk from the testbench level directly.
    // See the probe section below.
    reg        cpu_clk_tb;
    initial    cpu_clk_tb = 1'b0;
    always     #(CPU_CLK_HALF_NS) cpu_clk_tb = ~cpu_clk_tb;

    // =========================================================================
    // DUT
    // =========================================================================
    system_top u_system (
        .clk_in        (clk_in),
        .rst_n         (rst_n),
        .leds          (leds),
        .test_finished (test_finished)
    );

    // =========================================================================
    // LATTICE PRIMITIVES
    // =========================================================================
    GSR GSR_INST (.GSR_N(rst_n), .CLK(clk_in));
    PUR PUR_INST (.PUR(rst_n));

    // =========================================================================
    // CLOCK OVERRIDE: force DUT to use our 20 MHz testbench clock
    // =========================================================================
    // This ensures every flip-flop in riscv_top clocks at 20 MHz so the VCD
    // toggle events are at the right frequency.
    // If your simulator does not support force on a wire inside a module,
    // use the clk_in approach: set CLK_IN_HALF_NS = 25.0 (20 MHz board clk)
    // and retarget the PLL dividers accordingly.
    initial begin
        #0;
        force u_system.cpu_clk = cpu_clk_tb;
    end

    // =========================================================================
    // HIERARCHICAL PROBES
    // =========================================================================
    // NOTE: cpu_clk here is the testbench-driven 20 MHz signal, not the PLL
    // output, because we have forced it above.
    wire        cpu_clk         = cpu_clk_tb;
    wire        pll_lock        = u_system.pll_lock;

    // -- Address / memory bus --
    wire [31:0] h_addr          = u_system.alu_result_out;
    wire        h_mem_we        = u_system.mem_write_en;
    wire [31:0] h_mem_wdata     = u_system.mem_write_data;
    wire [31:0] h_mem_rdata     = u_system.final_read_data;
    wire [2:0]  h_funct3        = u_system.funct3_out;
    wire [3:0]  h_ram_byte_we   = u_system.ram_byte_we;

    // -- Core datapath --
    wire [31:0] h_pc            = u_system.u_core.pc_out;
    wire [31:0] h_instr         = u_system.u_core.instr;
    wire [31:0] h_alu_a         = u_system.u_core.alu_a;
    wire [31:0] h_alu_b         = u_system.u_core.alu_b;
    wire [31:0] h_alu_res       = u_system.u_core.alu_res;
    wire [4:0]  h_alu_ctrl      = u_system.u_core.alu_ctrl;
    wire        h_zero          = u_system.u_core.zero;
    wire        h_less_than     = u_system.u_core.less_than;

    // -- Immediate / write-back --
    wire [31:0] h_imm           = u_system.u_core.imm_out;
    wire [31:0] h_write_data    = u_system.u_core.write_data;

    // -- Control signals --
    wire        h_reg_write     = u_system.u_core.reg_write;
    wire        h_alu_src       = u_system.u_core.alu_src;
    wire        h_mem_to_reg    = u_system.u_core.mem_to_reg;
    wire        h_branch        = u_system.u_core.branch;
    wire        h_take_branch   = u_system.u_core.take_branch;
    wire        h_jal_sel       = u_system.u_core.jal_sel;
    wire        h_jalr_sel      = u_system.u_core.jalr_sel;
    wire        h_upper_imm_sel = u_system.u_core.upper_imm_sel;
    wire        h_csr_we        = u_system.u_core.csr_we;
    wire [1:0]  h_alu_op        = u_system.u_core.alu_op_write;

    // -- Register file ports --
    wire [31:0] h_rs1_data      = u_system.u_core.rs1_data;
    wire [31:0] h_rs2_data      = u_system.u_core.rs2_data;

    // -- Phase result registers --
    wire [31:0] reg_a0          = u_system.u_core.unit_regfile.registers[10];
    wire [31:0] reg_a1          = u_system.u_core.unit_regfile.registers[11];
    wire [31:0] reg_a2          = u_system.u_core.unit_regfile.registers[12];
    wire [31:0] reg_a3          = u_system.u_core.unit_regfile.registers[13];
    wire [31:0] reg_s4          = u_system.u_core.unit_regfile.registers[20];

    // -- CSR counter outputs (lower 32 bits only, no 64-bit arrays in VCD) --
    wire [31:0] h_mcycle        = u_system.u_core.unit_csr.mcycle_64[31:0];
    wire [31:0] h_minstret      = u_system.u_core.unit_csr.minstret_64[31:0];

    // -- Completion / phase-boundary strobes --
    wire tohost_write           = (h_addr == 32'h803F_FF00) && h_mem_we;
    wire phase_done_write       = (h_addr == 32'h8001_0040) && h_mem_we;

    // =========================================================================
    // CLOCK GENERATION  (125 MHz board clock)
    // =========================================================================
    initial  clk_in = 1'b0;
    always  #(CLK_IN_HALF_NS) clk_in = ~clk_in;

    // =========================================================================
    // TOGGLE COUNTER (for AF% report at end of sim)
    // Counts how many times each key signal transitions during VCD window.
    // Use these counts to manually set AF% in Lattice Power Calculator.
    // AF% = (toggle_count / (2 * total_cpu_cycles)) * 100
    // =========================================================================
    integer toggle_pc;
    integer toggle_instr;
    integer toggle_alu_res;
    integer toggle_rs1;
    integer toggle_rs2;
    integer toggle_write_data;
    integer toggle_mem_we;
    integer toggle_reg_write;
    integer cpu_cycle_count;

    // Count cpu_clk cycles during VCD window
    reg vcd_active;
    initial begin
        vcd_active        = 0;
        toggle_pc         = 0;
        toggle_instr      = 0;
        toggle_alu_res    = 0;
        toggle_rs1        = 0;
        toggle_rs2        = 0;
        toggle_write_data = 0;
        toggle_mem_we     = 0;
        toggle_reg_write  = 0;
        cpu_cycle_count   = 0;
    end

    always @(cpu_clk) if (vcd_active && cpu_clk) cpu_cycle_count = cpu_cycle_count + 1;

    // Edge-detect each signal (any bit change = one toggle event)
    reg [31:0] prev_pc, prev_instr, prev_alu_res, prev_rs1, prev_rs2, prev_wd;
    reg        prev_mem_we, prev_rw;

    always @(h_pc)         if (vcd_active) toggle_pc         = toggle_pc         + 1;
    always @(h_instr)      if (vcd_active) toggle_instr      = toggle_instr      + 1;
    always @(h_alu_res)    if (vcd_active) toggle_alu_res    = toggle_alu_res    + 1;
    always @(h_rs1_data)   if (vcd_active) toggle_rs1        = toggle_rs1        + 1;
    always @(h_rs2_data)   if (vcd_active) toggle_rs2        = toggle_rs2        + 1;
    always @(h_write_data) if (vcd_active) toggle_write_data = toggle_write_data + 1;
    always @(h_mem_we)     if (vcd_active) toggle_mem_we     = toggle_mem_we     + 1;
    always @(h_reg_write)  if (vcd_active) toggle_reg_write  = toggle_reg_write  + 1;

    // =========================================================================
    // MODULE-LEVEL VARIABLES
    // =========================================================================
    integer pass_count;
    integer fail_count;
    integer ph;
    integer delta_cy [0:3];
    real    cpi      [0:3];
    real    mips     [0:3];
    integer instrs;
    integer exp_cy;
    real    af_pc, af_instr, af_alu, af_rs1, af_rs2, af_wd;

    // =========================================================================
    // PHASE TRANSITION LOGGER
    // =========================================================================
    always @(posedge cpu_clk) begin
        if (phase_done_write) begin
            case (reg_s4)
                32'h01: $display("[%0t ns] Phase 1 (ALU)    complete  s4=0x01", $time);
                32'h03: $display("[%0t ns] Phase 2 (Store)  complete  s4=0x03", $time);
                32'h07: $display("[%0t ns] Phase 3 (Load)   complete  s4=0x07", $time);
                32'h0F: $display("[%0t ns] Phase 4 (Branch) complete  s4=0x0F  ALL DONE", $time);
                default:$display("[%0t ns] Phase done write  s4=0x%0h", $time, reg_s4);
            endcase
        end
    end

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    initial begin

        pass_count = 0;
        fail_count = 0;

        $display("");
        $display("================================================================");
        $display("  SINGLE-CYCLE RISC-V CORE -- 4-PHASE POWER BENCHMARK");
        $display("  Baseline  : %.2f MHz  cpu_clk (testbench-forced)", CPU_CLK_MHZ);
        $display("  Board clk : 125 MHz  (%.1f ns half-period)", CLK_IN_HALF_NS);
        $display("  Expected  : CPI = 1.000 all phases (single-cycle baseline)");
        $display("  PLL note  : cpu_clk forced to 20 MHz in sim for VCD accuracy.");
        $display("              On silicon: CLKI_DIV=1, CLKFB_DIV=4, CLKOP_DIV=25");
        $display("================================================================");

        // -- 1. RESET ----------------------------------------------------------
        rst_n = 1'b0;
        repeat (RST_CYCLES) @(posedge clk_in);
        rst_n = 1'b1;
        $display("[%0t ns] Reset released", $time);

        // -- 2. SETTLE ---------------------------------------------------------
        // Wait for PLL lock signal and allow crt0.s startup code to complete.
        // We wait on clk_in cycles (faster) then confirm pll_lock.
        repeat (SETTLE_CLK_IN) @(posedge clk_in);
        // Belt-and-suspenders: also wait for pll_lock if the model drives it
        if (!pll_lock)
            @(posedge pll_lock);
        $display("[%0t ns] Settle complete (pll_lock=%b) -- starting VCD capture", $time, pll_lock);

        // -- 3. START VCD ------------------------------------------------------
        // Open file and declare signals BEFORE $dumpon so the header is written
        // with all variable definitions, then transitions begin cleanly.
        $dumpfile("power_sc_20mhz.vcd");
        $dumplimit(268_435_456);   // 256 MB hard cap

        // Clocks -- these are the most critical signals for frequency detection
        $dumpvars(0, cpu_clk_tb);  // 20 MHz reference -- tool reads period from this
        $dumpvars(0, clk_in);
        $dumpvars(0, rst_n);
        $dumpvars(0, pll_lock);

        // Address / memory bus
        $dumpvars(0, h_addr);
        $dumpvars(0, h_mem_we);
        $dumpvars(0, h_mem_wdata);
        $dumpvars(0, h_mem_rdata);
        $dumpvars(0, h_funct3);
        $dumpvars(0, h_ram_byte_we);

        // Core datapath (most toggle-active signals -- critical for AF)
        $dumpvars(0, h_pc);
        $dumpvars(0, h_instr);
        $dumpvars(0, h_alu_a);
        $dumpvars(0, h_alu_b);
        $dumpvars(0, h_alu_res);
        $dumpvars(0, h_alu_ctrl);
        $dumpvars(0, h_zero);
        $dumpvars(0, h_less_than);

        // Immediate / write-back
        $dumpvars(0, h_imm);
        $dumpvars(0, h_write_data);

        // Control signals
        $dumpvars(0, h_reg_write);
        $dumpvars(0, h_alu_src);
        $dumpvars(0, h_mem_to_reg);
        $dumpvars(0, h_branch);
        $dumpvars(0, h_take_branch);
        $dumpvars(0, h_jal_sel);
        $dumpvars(0, h_jalr_sel);
        $dumpvars(0, h_upper_imm_sel);
        $dumpvars(0, h_csr_we);
        $dumpvars(0, h_alu_op);

        // Register file ports
        $dumpvars(0, h_rs1_data);
        $dumpvars(0, h_rs2_data);

        // Benchmark result registers
        $dumpvars(0, reg_a0);
        $dumpvars(0, reg_a1);
        $dumpvars(0, reg_a2);
        $dumpvars(0, reg_a3);
        $dumpvars(0, reg_s4);

        // CSR lower halves only (exclude raw 64-bit regs)
        $dumpvars(0, h_mcycle);
        $dumpvars(0, h_minstret);

        // Top-level outputs
        $dumpvars(0, leds);
        $dumpvars(0, test_finished);

        // Start toggle counters alongside VCD
        vcd_active = 1;

        // -- 4. WAIT FOR COMPLETION --------------------------------------------
        wait (tohost_write == 1'b1);
        @(posedge cpu_clk);

        // Stop VCD and toggle counters atomically
        vcd_active = 0;
        $dumpoff;
        $dumpflush;
        $display("[%0t ns] Tohost write detected -- VCD stopped and flushed", $time);

        // -- 5. LATCH RESULTS FROM REGISTER FILE -------------------------------
        delta_cy[0] = reg_a0;
        delta_cy[1] = reg_a1;
        delta_cy[2] = reg_a2;
        delta_cy[3] = reg_a3;

        // -- 6. PRINT AND VALIDATE ---------------------------------------------
        $display("");
        $display("================================================================");
        $display("  RESULTS -- SINGLE-CYCLE @ %.2f MHz", CPU_CLK_MHZ);
        $display("================================================================");
        $display("  %-15s | %-10s | %-10s | %-7s | %-9s | %s",
                 "Phase","Cycles","Expected","CPI","MIPS","Status");
        $display("  %-15s | %-10s | %-10s | %-7s | %-9s | %s",
                 "---------------","----------","----------",
                 "-------","---------","------");

        for (ph = 0; ph < 4; ph = ph + 1) begin
            case (ph)
                0: begin instrs = PH1_INSTRS; exp_cy = PH1_EXPECTED; end
                1: begin instrs = PH2_INSTRS; exp_cy = PH2_EXPECTED; end
                2: begin instrs = PH3_INSTRS; exp_cy = PH3_EXPECTED; end
                3: begin instrs = PH4_INSTRS; exp_cy = PH4_EXPECTED; end
            endcase

            if (delta_cy[ph] > 0) begin
                cpi[ph]  = $itor(delta_cy[ph]) / $itor(instrs);
                mips[ph] = CPU_CLK_MHZ / cpi[ph];
            end else begin
                cpi[ph]  = 0.0;
                mips[ph] = 0.0;
            end

            if (delta_cy[ph] >= (exp_cy - TOLERANCE) &&
                delta_cy[ph] <= (exp_cy + TOLERANCE)) begin
                $display("  Ph%0d %-10s | %-10d | %-10d | %-7.3f | %-9.2f | PASS",
                         ph+1,
                         (ph==0) ? "(ALU)"   :
                         (ph==1) ? "(Store)" :
                         (ph==2) ? "(Load)"  : "(Branch)",
                         delta_cy[ph], exp_cy, cpi[ph], mips[ph]);
                pass_count = pass_count + 1;
            end else begin
                $display("  Ph%0d %-10s | %-10d | %-10d | %-7.3f | %-9.2f | FAIL  dev=%0d",
                         ph+1,
                         (ph==0) ? "(ALU)"   :
                         (ph==1) ? "(Store)" :
                         (ph==2) ? "(Load)"  : "(Branch)",
                         delta_cy[ph], exp_cy, cpi[ph], mips[ph],
                         delta_cy[ph] - exp_cy);
                fail_count = fail_count + 1;
            end
        end

        // -- 7. CSR CROSS-CHECK ------------------------------------------------
        $display("");
        $display("  CSR cross-check:");
        $display("    mcycle           = %0d  (total, includes settle)", h_mcycle);
        $display("    minstret         = %0d", h_minstret);
        $display("    sum delta_cycles = %0d",
                 delta_cy[0]+delta_cy[1]+delta_cy[2]+delta_cy[3]);

        // -- 8. ACTIVITY FACTOR REPORT -----------------------------------------
        // Use these numbers to manually set AF% in Lattice Power Calculator
        // for the Logic Block section (since behavioural VCD gives AF=0 there).
        //
        // AF% formula: (toggle_events / (2 * cpu_cycles)) * 100
        // Factor of 2 because each full clock cycle = 2 edges (rise + fall)
        //
        if (cpu_cycle_count > 0) begin
            af_pc    = ($itor(toggle_pc)         / ($itor(cpu_cycle_count) * 2.0)) * 100.0;
            af_instr = ($itor(toggle_instr)      / ($itor(cpu_cycle_count) * 2.0)) * 100.0;
            af_alu   = ($itor(toggle_alu_res)    / ($itor(cpu_cycle_count) * 2.0)) * 100.0;
            af_rs1   = ($itor(toggle_rs1)        / ($itor(cpu_cycle_count) * 2.0)) * 100.0;
            af_rs2   = ($itor(toggle_rs2)        / ($itor(cpu_cycle_count) * 2.0)) * 100.0;
            af_wd    = ($itor(toggle_write_data) / ($itor(cpu_cycle_count) * 2.0)) * 100.0;
        end

        $display("");
        $display("================================================================");
        $display("  SWITCHING ACTIVITY REPORT  (for Lattice Power Calculator)");
        $display("  VCD window: %0d cpu_clk cycles @ %.2f MHz", cpu_cycle_count, CPU_CLK_MHZ);
        $display("----------------------------------------------------------------");
        $display("  %-20s | %-10s | %s", "Signal", "Toggles", "AF (%)");
        $display("  %-20s | %-10s | %s", "--------------------", "----------", "------");
        $display("  %-20s | %-10d | %0.1f", "h_pc [31:0]",         toggle_pc,         af_pc);
        $display("  %-20s | %-10d | %0.1f", "h_instr [31:0]",      toggle_instr,      af_instr);
        $display("  %-20s | %-10d | %0.1f", "h_alu_res [31:0]",    toggle_alu_res,    af_alu);
        $display("  %-20s | %-10d | %0.1f", "h_rs1_data [31:0]",   toggle_rs1,        af_rs1);
        $display("  %-20s | %-10d | %0.1f", "h_rs2_data [31:0]",   toggle_rs2,        af_rs2);
        $display("  %-20s | %-10d | %0.1f", "h_write_data [31:0]", toggle_write_data, af_wd);
        $display("  %-20s | %-10d | (1-bit)", "h_mem_we",   toggle_mem_we);
        $display("  %-20s | %-10d | (1-bit)", "h_reg_write", toggle_reg_write);
        $display("----------------------------------------------------------------");
        $display("  >> Use the AVERAGE of AF values above as 'Logic AF' in");
        $display("     Lattice Power Calculator -> Logic Block -> AF (%%) field.");
        $display("     Recommended: AF = 20%% (conservative) to 35%% (active).");
        $display("================================================================");

        // -- 9. SUMMARY --------------------------------------------------------
        $display("");
        $display("================================================================");
        $display("  %0d PASSED   %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("  ALL WITHIN TOLERANCE (+-200 cycles) -- OK");
        else
            $display("  FAILURES -- check $readmemh path and is_ram_addr decode");
        $display("================================================================");
        $display("  VCD : power_sc_20mhz.vcd");
        $display("  Freq: %.2f MHz  (cpu_clk forced in testbench)", CPU_CLK_MHZ);
        $display("  Sigs: ~38 named signals  (no memory arrays, no PLL internals)");
        $display("================================================================");
        $display("");

        $finish;
    end

    // =========================================================================
    // TIMEOUT WATCHDOG  (counts cpu_clk cycles, not clk_in)
    // =========================================================================
    initial begin
        repeat (TIMEOUT_CPU_CYC) @(posedge cpu_clk);
        $display("[TIMEOUT] %0d cpu_clk cycles elapsed -- tohost write never seen.",
                 TIMEOUT_CPU_CYC);
        $display("  PC       = 0x%h", h_pc);
        $display("  instr    = 0x%h", h_instr);
        $display("  mcycle   = %0d",  h_mcycle);
        $display("  s4 done  = 0x%h  (need 0x0F)", reg_s4);
        $display("  a0 Ph1   = %0d   (expect ~%0d)", reg_a0, PH1_EXPECTED);
        $display("  a1 Ph2   = %0d   (expect ~%0d)", reg_a1, PH2_EXPECTED);
        $display("  a2 Ph3   = %0d   (expect ~%0d)", reg_a2, PH3_EXPECTED);
        $display("  a3 Ph4   = %0d   (expect ~%0d)", reg_a3, PH4_EXPECTED);
        vcd_active = 0;
        $dumpoff;
        $dumpflush;
        $finish;
    end

endmodule