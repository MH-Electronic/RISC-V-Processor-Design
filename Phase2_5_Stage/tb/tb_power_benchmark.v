`timescale 1ns/1ps
// =============================================================================
// tb_5s_power_bench.v  --  4-Phase Power Benchmark Testbench (5-Stage Core)
// EEE499 FYP  |  Liew Ming Heng (161439)  |  USM
// =============================================================================
//
// FIRMWARE
//   Uses the SAME instr.mem produced by  make  with the benchmark main.c.
//   Results are stored in a0–a3 (register file) and a0 RAM[0..3].
//   Done flag at 0x80010040, tohost at 0x803FFF00.
//
// HOW TO RUN (QuestaSim)
//   vlog  rtl/*.v  tb_5s_power_bench.v
//   vsim  -t 1ns  tb_5s_power_bench  -do "run -all"
//
// KEY DIFFERENCES FROM SINGLE-CYCLE TESTBENCH
//   1. system_top (5-stage) does NOT have a test_finished OUTPUT PORT.
//      It is an internal wire -- use h_test_done = u_system.test_finished.
//      Completion is detected via  tohost_write  (same address 0x803FFF00).
//   2. Expected delta_cycles are HIGHER because of pipeline hazards:
//        Ph1  branch flush  9 999 x 2          +19 998 cycles  CPI 1.143
//        Ph2  branch flush  9 999 x 2          +19 998 cycles  CPI 1.200
//        Ph3  load-use      4 x 10 000         +40 000 cycles  )
//             branch flush  9 999 x 2          +19 998 cycles  ) CPI 1.600
//        Ph4  BLT flush     4 999 x 2 +         +9 998 cycles  )
//             BNEZ flush    9 999 x 2          +19 998 cycles  ) CPI 1.500
//   3. CPU target is 50 MHz; MIPS is calculated from that frequency.
//   4. Phase transition logger uses mem_write_data (the forwarded store
//      value) instead of reg_s4 to avoid the 5-stage WB-stage race.
//   5. Pipeline stall/flush counters added for diagnostic display.
//
// =============================================================================

module tb_5s_power_bench;

    // =========================================================================
    // PARAMETERS
    // =========================================================================
    localparam real    CLK_IN_HALF_NS  = 4.0;        // 125 MHz input clock
    localparam real    CPU_CLK_MHZ     = 50.0;        // 5-stage PLL target
    localparam integer RST_CYCLES      = 20;
    localparam integer SETTLE_CYCLES   = 500;         // PLL lock + crt0.s
    localparam integer TIMEOUT_CYCLES  = 8_000_000;   // 64 ms @ 125 MHz

    // Instruction counts (denominator for CPI -- exact loop body counts)
    localparam integer PH1_INSTRS  = 140_000;   // 10000 x 14
    localparam integer PH2_INSTRS  = 100_000;   // 10000 x 10
    localparam integer PH3_INSTRS  = 100_000;   // 10000 x 10
    localparam integer PH4_INSTRS  =  60_000;   // 10000 x 6

    // Expected delta_cycles = base + load-use stalls + branch flush + init
    //   Ph1: 140000 + 0      + 19998 + 4  = 160002
    //   Ph2: 100000 + 0      + 19998 + 1  = 119999
    //   Ph3: 100000 + 40000  + 19998 + 2  = 160000
    //   Ph4:  60000 + 0      + 29996 + 4  =  90000
    //         (BLT 4999x2=9998 + BNEZ 9999x2=19998 = 29996)
    localparam integer PH1_EXPECTED  = 160_002;
    localparam integer PH2_EXPECTED  = 119_999;
    localparam integer PH3_EXPECTED  = 160_000;
    localparam integer PH4_EXPECTED  =  90_000;
    localparam integer TOLERANCE     =      200;

    // =========================================================================
    // DUT SIGNALS
    // =========================================================================
    reg        clk_in;
    reg        rst_n;
    wire [7:0] leds;
    // NOTE: test_finished is NOT a port on the 5-stage system_top.
    //       Accessed via hierarchical reference h_test_done below.

    // =========================================================================
    // DUT
    // =========================================================================
    system_top u_system (
        .clk_in  (clk_in),
        .rst_n   (rst_n),
        .leds    (leds)
    );

    // =========================================================================
    // LATTICE PRIMITIVES
    // =========================================================================
    GSR GSR_INST (.GSR_N(rst_n), .CLK(clk_in));
    PUR PUR_INST (.PUR(rst_n));

    // =========================================================================
    // HIERARCHICAL PROBES
    // =========================================================================
    wire        cpu_clk     = u_system.cpu_clk;

    // Memory-bus signals (come from the MEM pipeline stage -- already
    // registered into EX/MEM, so stable well before posedge cpu_clk)
    wire [31:0] h_addr      = u_system.alu_result_out;   // MEM-stage address
    wire        h_mem_we    = u_system.mem_write_en;      // MEM-stage write-en
    wire [31:0] h_wr_data   = u_system.mem_write_data;   // MEM-stage store data

    // Program counter and instruction in IF/ID stages
    wire [31:0] h_pc        = u_system.u_core.pc_out;
    wire [31:0] h_id_instr  = u_system.u_core.id_instr;

    // Register file -- phase delta_cycles stored in a0-a3 by firmware
    wire [31:0] reg_a0      = u_system.u_core.unit_regfile.registers[10];
    wire [31:0] reg_a1      = u_system.u_core.unit_regfile.registers[11];
    wire [31:0] reg_a2      = u_system.u_core.unit_regfile.registers[12];
    wire [31:0] reg_a3      = u_system.u_core.unit_regfile.registers[13];

    // CSR performance counters
    wire [31:0] h_mcycle    = u_system.u_core.unit_csr.mcycle_64[31:0];
    wire [31:0] h_minstret  = u_system.u_core.unit_csr.minstret_64[31:0];

    // Pipeline hazard signals -- useful for diagnostic display
    wire        h_stall     = u_system.u_core.stall;   // load-use stall
    wire        h_flush     = u_system.u_core.flush;   // branch / jump flush

    // test_finished as internal-wire hierarchical reference
    wire        h_test_done = u_system.test_finished;

    // Completion event: firmware writes 1 to 0x803FFF00 as last action
    wire tohost_write     = (h_addr == 32'h803F_FF00) && h_mem_we;

    // Phase-boundary event: firmware writes s4 to 0x80010040 after each phase
    // h_wr_data holds the forwarded store value (avoids WB-stage race on reg_s4)
    wire phase_done_write = (h_addr == 32'h8001_0040) && h_mem_we;

    // =========================================================================
    // CLOCK GENERATION  (125 MHz input)
    // =========================================================================
    initial  clk_in = 1'b0;
    always  #(CLK_IN_HALF_NS) clk_in = ~clk_in;

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

    // Pipeline activity counters -- incremented during the benchmark window
    integer stall_count;
    integer flush_count;

    initial begin stall_count = 0; flush_count = 0; end

    always @(posedge cpu_clk) begin
        if (rst_n) begin
            if (h_stall) stall_count = stall_count + 1;
            if (h_flush) flush_count = flush_count + 1;
        end
    end

    // =========================================================================
    // PHASE TRANSITION LOGGER
    // =========================================================================
    // Reads h_wr_data (the forwarded store value in the MEM stage) rather than
    // the register file, because in 5-stage the WB write to s4 happens one
    // cycle AFTER the SW reaches MEM, so reg_s4 is still stale at that edge.
    always @(posedge cpu_clk) begin
        if (phase_done_write) begin
            case (h_wr_data)
                32'h01: $display("[%0t ns] Phase 1 (ALU)    complete  flag=0x01", $time);
                32'h03: $display("[%0t ns] Phase 2 (Store)  complete  flag=0x03", $time);
                32'h07: $display("[%0t ns] Phase 3 (Load)   complete  flag=0x07", $time);
                32'h0F: $display("[%0t ns] Phase 4 (Branch) complete  flag=0x0F  ALL DONE", $time);
                default:$display("[%0t ns] Phase done write  val=0x%0h", $time, h_wr_data);
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
        $display("  5-STAGE PIPELINED RV32I -- 4-PHASE POWER BENCHMARK");
        $display("  CPU Fmax  : %.0f MHz  (5-stage target)", CPU_CLK_MHZ);
        $display("  Input clk : 125 MHz  (4.0 ns half-period)");
        $display("  Expected  : CPI 1.143 / 1.200 / 1.600 / 1.500");
        $display("  (all CPI = 1.000 means forwarding / flush not working)");
        $display("================================================================");

        // -- 1. RESET ----------------------------------------------------------
        rst_n = 1'b0;
        repeat (RST_CYCLES) @(posedge clk_in);
        rst_n = 1'b1;
        $display("[%0t ns] Reset released -- PLL locking + crt0.s running", $time);

        // -- 2. SETTLE ---------------------------------------------------------
        repeat (SETTLE_CYCLES) @(posedge clk_in);
        $display("[%0t ns] Settle complete -- starting full VCD capture", $time);

        // -- 3. START FULL-BENCHMARK VCD ---------------------------------------
        $dumpfile("power_5s_full.vcd");
        $dumpvars(0, u_system);

        // -- 4. WAIT FOR COMPLETION --------------------------------------------
        // Firmware writes 1 to tohost address 0x803FFF00 as its final action.
        // Detected combinationally via h_addr / h_mem_we (EX/MEM registered
        // signals, stable at posedge cpu_clk).
        wait (tohost_write == 1'b1);
        @(posedge cpu_clk);

        $dumpoff;
        $display("[%0t ns] Tohost write detected -- VCD stopped", $time);

        // -- 5. LATCH RESULTS FROM REGISTER FILE -------------------------------
        // a0-a3 (registers 10-13) hold Phase 1-4 delta_cycles.
        // By the time tohost_write fires, all four SW instructions that stored
        // results to RAM have passed through WB, so a0-a3 are stable.
        delta_cy[0] = reg_a0;
        delta_cy[1] = reg_a1;
        delta_cy[2] = reg_a2;
        delta_cy[3] = reg_a3;

        // -- 6. PRINT AND VALIDATE ---------------------------------------------
        $display("");
        $display("================================================================");
        $display("  RESULTS -- 5-STAGE @ %.0f MHz", CPU_CLK_MHZ);
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

        // -- 7. PIPELINE ACTIVITY CROSS-CHECK ----------------------------------
        $display("");
        $display("  Pipeline activity (full benchmark):");
        $display("    stall cycles (load-use)  = %0d  (expected ~40000 from Ph3)",
                 stall_count);
        $display("    flush cycles (branch)    = %0d  (expected ~69992 total)",
                 flush_count);
        $display("    mcycle                   = %0d  (includes settle + overhead)",
                 h_mcycle);
        $display("    minstret                 = %0d", h_minstret);
        $display("    sum delta_cycles         = %0d",
                 delta_cy[0]+delta_cy[1]+delta_cy[2]+delta_cy[3]);

        // -- 8. SUMMARY --------------------------------------------------------
        $display("");
        $display("================================================================");
        $display("  %0d PASSED   %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("  ALL WITHIN TOLERANCE (+-200 cycles) -- OK");
        else begin
            $display("  FAILURES -- diagnosis hints:");
            $display("  * CPI = 1.000 all phases  : flush=0, check ex_take_branch");
            $display("  * Ph3 CPI near 1.2        : load-use stall missing");
            $display("  * Ph4 CPI near 1.2        : branch flush not firing");
            $display("  * Cycles = 0              : RAM write failed, check is_ram_addr");
            $display("  * All zeros               : firmware hung (check $readmemh path)");
        end
        $display("================================================================");
        $display("  VCD: power_5s_full.vcd -- import into Lattice Power Calculator");
        $display("================================================================");
        $display("");

        $finish;
    end

    // =========================================================================
    // TIMEOUT WATCHDOG
    // =========================================================================
    initial begin
        repeat (TIMEOUT_CYCLES) @(posedge clk_in);
        $display("[TIMEOUT] %0d clk_in cycles -- tohost write never occurred.",
                 TIMEOUT_CYCLES);
        $display("  PC          = 0x%h", h_pc);
        $display("  ID instr    = 0x%h", h_id_instr);
        $display("  mcycle      = %0d",  h_mcycle);
        $display("  stall_count = %0d",  stall_count);
        $display("  flush_count = %0d",  flush_count);
        $display("  a0 Ph1      = %0d  (expect ~%0d)", reg_a0, PH1_EXPECTED);
        $display("  a1 Ph2      = %0d  (expect ~%0d)", reg_a1, PH2_EXPECTED);
        $display("  a2 Ph3      = %0d  (expect ~%0d)", reg_a2, PH3_EXPECTED);
        $display("  a3 Ph4      = %0d  (expect ~%0d)", reg_a3, PH4_EXPECTED);
        $finish;
    end

endmodule