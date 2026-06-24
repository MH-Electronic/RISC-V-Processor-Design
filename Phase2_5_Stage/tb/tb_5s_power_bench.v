`timescale 1ns/1ps
// =============================================================================
// tb_5s_power_bench_50mhz.v  --  4-Phase Power Benchmark (5-Stage Pipeline)
// EEE499 FYP | Liew Ming Heng (161439) | USM
//
// CHANGE LOG vs original tb_5s_power_bench.v
// ============================================
//  [CLK]  cpu_clk forced to exactly 50 MHz (10 ns half-period) in the
//         testbench, overriding the PLL output.
//         Reason: PLL behavioural model passes clk_in/2 = 62.5 MHz through
//         in simulation, causing the Lattice Power Calculator to read the
//         wrong frequency from VCD timestamps and inflate all dynamic power
//         estimates.
//         On silicon, update pll_clock: CLKI_DIV=1, CLKFB_DIV=4, CLKOP_DIV=10
//         -> VCO = 500 MHz (in-range), f_out = 50 MHz.
//
//  [VCD]  Replaced $dumpvars(0, u_system) with explicit per-signal list.
//         Reason: recursive dump includes instr_rom.mem[0:32767] and
//         data_ram.mem[0:32767] -- ~8 MB of static state that bloats
//         the VCD file and crashes Lattice Power Calculator.
//         The explicit list covers all 86 toggling signals across all 5
//         pipeline stages without touching any memory array.
//
//  [VCD]  VCD capture starts only AFTER the settle phase.
//         Reason: PLL spin-up and crt0.s startup produce burst switching
//         that would inflate the toggle-rate / AF% estimate.
//
//  [VCD]  $dumplimit(256 MB) added as a hard file-size safety net.
//         $dumpflush added after $dumpoff and in the timeout handler.
//
//  [AF]   Toggle counters added for key datapath signals.
//         Simulation prints an AF% report at completion that you can use
//         to manually set Logic Block AF% in Lattice Power Calculator,
//         since behavioural VCD signal names don't match post-synthesis
//         netlist primitives (causing AF=0 in the tool).
//
//  [PCS]  16 mW spurious PCS static power: disable in Power Calculator ->
//         PCS section -> set active lanes to 0. (No testbench change needed.)
//
//  [TIMEOUT]  Watchdog now counts cpu_clk cycles, not clk_in cycles.
//             Limit = 5_300_000 cpu_clk cycles (10x total expected = 530001).
//
//  [5-STAGE SPECIFIC]
//         * system_top has NO test_finished output port -- accessed via
//           hierarchical wire: u_system.test_finished
//         * leds driven by GPIO register (0x90000000), not by PC bits
//         * Phase logger reads h_wr_data (MEM-stage store value) to avoid
//           WB-stage race on reg_s4
//         * Pipeline stall + flush counters added for diagnostic cross-check
//         * Expected CPI values account for pipeline penalties:
//             Ph1 ALU:    CPI 1.143 (branch flush only)
//             Ph2 Store:  CPI 1.200 (branch flush only)
//             Ph3 Load:   CPI 1.600 (load-use stall + branch flush)
//             Ph4 Branch: CPI 1.500 (BLT + BNEZ flushes)
// =============================================================================

module tb_5s_power_bench;

    // =========================================================================
    // PARAMETERS
    // =========================================================================
    // Board input clock: 125 MHz (unchanged -- PCB oscillator)
    localparam real    CLK_IN_HALF_NS   = 4.0;

    // CPU clock: 50 MHz baseline  (10 ns half-period)
    localparam real    CPU_CLK_HALF_NS  = 10.0;
    localparam real    CPU_CLK_MHZ      = 50.0;

    localparam integer RST_CYCLES       = 20;          // clk_in cycles in reset
    localparam integer SETTLE_CLK_IN    = 1000;        // clk_in cycles for PLL + crt0

    // Timeout: 10x total expected cpu_clk cycles
    //   Total expected: 160002+119999+160000+90000 = 530001
    localparam integer TIMEOUT_CPU_CYC  = 5_300_000;

    // Instruction counts (benchmark loop body, denominator for CPI)
    localparam integer PH1_INSTRS       = 140_000;
    localparam integer PH2_INSTRS       = 100_000;
    localparam integer PH3_INSTRS       = 100_000;
    localparam integer PH4_INSTRS       =  60_000;

    // Expected delta_cycles including pipeline penalties:
    //   Ph1: 140000 + branch_flush(9999x2=19998)       + init(4) = 160002
    //   Ph2: 100000 + branch_flush(9999x2=19998)       + init(1) = 119999
    //   Ph3: 100000 + load_use(4x10000=40000)
    //               + branch_flush(9999x2=19998)       + init(2) = 160000
    //   Ph4:  60000 + BLT_flush(4999x2=9998)
    //               + BNEZ_flush(9999x2=19998)         + init(4) =  90000
    localparam integer PH1_EXPECTED     = 160_002;
    localparam integer PH2_EXPECTED     = 119_999;
    localparam integer PH3_EXPECTED     = 160_000;
    localparam integer PH4_EXPECTED     =  90_000;
    localparam integer TOLERANCE        =     200;

    // =========================================================================
    // DUT SIGNALS
    // =========================================================================
    reg        clk_in;
    reg        rst_n;
    wire [7:0] leds;
    // NOTE: test_finished is NOT a port on the 5-stage system_top.
    //       Accessed via hierarchical reference: u_system.test_finished

    // =========================================================================
    // TESTBENCH-GENERATED cpu_clk  (50 MHz -- overrides PLL output in sim)
    // =========================================================================
    // The PLL behavioural model outputs clk_in/2 = 62.5 MHz in simulation,
    // which makes the Lattice Power Calculator read the wrong frequency from
    // VCD timestamps and produce inflated dynamic power numbers.
    //
    // By generating cpu_clk_tb at exactly 50 MHz and forcing it onto the
    // internal cpu_clk net, every flip-flop toggle in the VCD occurs at the
    // correct 20 ns period, and the Power Calculator auto-detects 50 MHz.
    //
    // On silicon: update pll_clock with CLKI_DIV=1, CLKFB_DIV=4, CLKOP_DIV=10
    //   VCO = 125 * 4 / 1 = 500 MHz (valid 400-800 MHz range)
    //   f_out = 500 / 10 = 50 MHz
    reg cpu_clk_tb;
    initial cpu_clk_tb = 1'b0;
    always  #(CPU_CLK_HALF_NS) cpu_clk_tb = ~cpu_clk_tb;

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
    // CLOCK OVERRIDE: inject 50 MHz testbench clock into DUT
    // =========================================================================
    // Forces the internal cpu_clk wire (driven by PLL) to follow cpu_clk_tb.
    initial begin
        #0;
        force u_system.cpu_clk = cpu_clk_tb;
    end

    // =========================================================================
    // HIERARCHICAL PROBES
    // =========================================================================
    // SHORTHAND -- avoids repeating the long path in every $dumpvars call
    // and keeps the signal declarations easy to read.
    //
    // Rule: one wire per signal, named to match the RTL internal wire.
    // Memory arrays (instr_rom.mem, data_ram.mem) are deliberately excluded.
    // CSR 64-bit registers are split: only lower 32 bits are probed.

    wire        cpu_clk         = cpu_clk_tb;         // 50 MHz reference
    wire        pll_lock        = u_system.pll_lock;

    // -- IF Stage --
    wire [31:0] if_pc           = u_system.u_core.pc_out;
    wire [31:0] if_pc_plus4     = u_system.u_core.if_pc_plus4;
    wire [31:0] if_pc_next      = u_system.u_core.if_pc_next;
    wire [31:0] if_instr        = u_system.u_core.instr;

    // -- IF/ID Pipeline Register --
    wire [31:0] id_pc           = u_system.u_core.id_pc;
    wire [31:0] id_instr        = u_system.u_core.id_instr;

    // -- ID Stage: decode outputs --
    wire [31:0] id_rs1_data     = u_system.u_core.id_rs1_data;
    wire [31:0] id_rs2_data     = u_system.u_core.id_rs2_data;
    wire [31:0] id_imm          = u_system.u_core.id_imm;
    wire        id_reg_write    = u_system.u_core.id_reg_write;
    wire        id_alu_src      = u_system.u_core.id_alu_src;
    wire        id_mem_to_reg   = u_system.u_core.id_mem_to_reg;
    wire        id_mem_write    = u_system.u_core.id_mem_write;
    wire        id_branch       = u_system.u_core.id_branch;
    wire        id_jal_sel      = u_system.u_core.id_jal_sel;
    wire        id_jalr_sel     = u_system.u_core.id_jalr_sel;
    wire [1:0]  id_alu_op       = u_system.u_core.id_alu_op;
    wire        id_csr_we       = u_system.u_core.id_csr_we;

    // -- Hazard & Flush --
    wire        h_stall         = u_system.u_core.stall;
    wire        h_flush         = u_system.u_core.flush;

    // -- ID/EX Pipeline Register --
    wire [31:0] ex_pc           = u_system.u_core.ex_pc;
    wire [31:0] ex_instr        = u_system.u_core.ex_instr;
    wire [31:0] ex_rs1_data     = u_system.u_core.ex_rs1_data;
    wire [31:0] ex_rs2_data     = u_system.u_core.ex_rs2_data;
    wire [31:0] ex_imm          = u_system.u_core.ex_imm;
    wire [4:0]  ex_rd_addr      = u_system.u_core.ex_rd_addr;
    wire [4:0]  ex_rs1_addr     = u_system.u_core.ex_rs1_addr;
    wire [4:0]  ex_rs2_addr     = u_system.u_core.ex_rs2_addr;
    wire        ex_reg_write    = u_system.u_core.ex_reg_write;
    wire        ex_alu_src      = u_system.u_core.ex_alu_src;
    wire        ex_mem_to_reg   = u_system.u_core.ex_mem_to_reg;
    wire        ex_mem_write    = u_system.u_core.ex_mem_write;
    wire        ex_branch       = u_system.u_core.ex_branch;
    wire        ex_jal_sel      = u_system.u_core.ex_jal_sel;
    wire        ex_jalr_sel     = u_system.u_core.ex_jalr_sel;
    wire [1:0]  ex_alu_op       = u_system.u_core.ex_alu_op;
    wire        ex_csr_we       = u_system.u_core.ex_csr_we;

    // -- EX Stage: ALU + forwarding --
    wire [1:0]  forward_a       = u_system.u_core.forward_a;
    wire [1:0]  forward_b       = u_system.u_core.forward_b;
    wire [31:0] ex_rs1_fwd      = u_system.u_core.ex_rs1_forwarded;
    wire [31:0] ex_rs2_fwd      = u_system.u_core.ex_rs2_forwarded;
    wire [31:0] ex_alu_a        = u_system.u_core.ex_alu_a;
    wire [31:0] ex_alu_b        = u_system.u_core.ex_alu_b;
    wire [31:0] ex_alu_res      = u_system.u_core.ex_alu_res;
    wire [4:0]  ex_alu_ctrl     = u_system.u_core.ex_alu_ctrl;
    wire        ex_zero         = u_system.u_core.ex_zero;
    wire        ex_less_than    = u_system.u_core.ex_less_than;
    wire        ex_take_branch  = u_system.u_core.ex_take_branch;
    wire [31:0] ex_branch_tgt   = u_system.u_core.ex_branch_target;
    wire [31:0] ex_jalr_tgt     = u_system.u_core.ex_jalr_target;
    wire [31:0] ex_csr_rdata    = u_system.u_core.ex_csr_rdata;

    // -- EX/MEM Pipeline Register --
    wire [31:0] mem_alu_res     = u_system.u_core.mem_alu_res;
    wire [31:0] mem_rs2_data    = u_system.u_core.mem_rs2_data;
    wire [4:0]  mem_rd_addr     = u_system.u_core.mem_rd_addr;
    wire [2:0]  mem_funct3      = u_system.u_core.mem_funct3;
    wire        mem_reg_write   = u_system.u_core.mem_reg_write;
    wire        mem_mem_to_reg  = u_system.u_core.mem_mem_to_reg;
    wire        mem_mem_write   = u_system.u_core.mem_mem_write;
    wire        mem_csr_we      = u_system.u_core.mem_csr_we;

    // -- MEM Stage: system_top memory bus --
    wire [31:0] h_addr          = u_system.alu_result_out;
    wire        h_mem_we        = u_system.mem_write_en;
    wire [31:0] h_wr_data       = u_system.mem_write_data;
    wire [31:0] h_rd_data       = u_system.final_read_data;
    wire [2:0]  h_funct3        = u_system.funct3_out;
    wire [3:0]  h_ram_byte_we   = u_system.ram_byte_we;

    // -- MEM/WB Pipeline Register --
    wire [31:0] wb_alu_res      = u_system.u_core.wb_alu_res;
    wire [31:0] wb_read_data    = u_system.u_core.wb_read_data;
    wire [4:0]  wb_rd_addr      = u_system.u_core.wb_rd_addr;
    wire        wb_reg_write    = u_system.u_core.wb_reg_write;
    wire        wb_mem_to_reg   = u_system.u_core.wb_mem_to_reg;
    wire        wb_csr_we       = u_system.u_core.wb_csr_we;

    // -- WB Stage --
    wire [31:0] wb_write_data   = u_system.u_core.wb_write_data;
    wire [31:0] wb_csr_rdata    = u_system.u_core.wb_csr_rdata;

    // -- CSR counters (lower 32 bits only -- no 64-bit arrays in VCD) --
    wire [31:0] h_mcycle        = u_system.u_core.unit_csr.mcycle_64[31:0];
    wire [31:0] h_minstret      = u_system.u_core.unit_csr.minstret_64[31:0];

    // -- Benchmark result registers --
    wire [31:0] reg_a0          = u_system.u_core.unit_regfile.registers[10];
    wire [31:0] reg_a1          = u_system.u_core.unit_regfile.registers[11];
    wire [31:0] reg_a2          = u_system.u_core.unit_regfile.registers[12];
    wire [31:0] reg_a3          = u_system.u_core.unit_regfile.registers[13];
    wire [31:0] reg_s4          = u_system.u_core.unit_regfile.registers[20];

    // -- Top-level outputs --
    wire [7:0]  h_leds          = u_system.leds;
    wire        h_test_done     = u_system.test_finished;  // internal wire, not a port

    // -- Completion strobes --
    wire tohost_write     = (h_addr == 32'h803F_FF00) && h_mem_we;
    wire phase_done_write = (h_addr == 32'h8001_0040) && h_mem_we;

    // =========================================================================
    // CLOCK GENERATION  (125 MHz board clock)
    // =========================================================================
    initial  clk_in = 1'b0;
    always  #(CLK_IN_HALF_NS) clk_in = ~clk_in;

    // =========================================================================
    // TOGGLE COUNTERS  (used for AF% report -- see bottom of simulation)
    // =========================================================================
    integer vcd_active;        // gate all counters to VCD window only
    integer cpu_cycle_count;
    integer tgl_if_pc;
    integer tgl_id_instr;
    integer tgl_ex_alu_a;
    integer tgl_ex_alu_b;
    integer tgl_ex_alu_res;
    integer tgl_ex_rs1_fwd;
    integer tgl_ex_rs2_fwd;
    integer tgl_mem_alu_res;
    integer tgl_wb_write_data;
    integer tgl_stall;
    integer tgl_flush;
    integer tgl_forward_a;
    integer tgl_forward_b;

    initial begin
        vcd_active      = 0;
        cpu_cycle_count = 0;
        tgl_if_pc       = 0; tgl_id_instr    = 0;
        tgl_ex_alu_a    = 0; tgl_ex_alu_b    = 0; tgl_ex_alu_res  = 0;
        tgl_ex_rs1_fwd  = 0; tgl_ex_rs2_fwd  = 0;
        tgl_mem_alu_res = 0; tgl_wb_write_data = 0;
        tgl_stall       = 0; tgl_flush       = 0;
        tgl_forward_a   = 0; tgl_forward_b   = 0;
    end

    always @(cpu_clk) if (vcd_active && cpu_clk) cpu_cycle_count = cpu_cycle_count + 1;

    // Any bit-change on the bus = one toggle event (realistic for wide buses)
    always @(if_pc)         if (vcd_active) tgl_if_pc        = tgl_if_pc        + 1;
    always @(id_instr)      if (vcd_active) tgl_id_instr     = tgl_id_instr     + 1;
    always @(ex_alu_a)      if (vcd_active) tgl_ex_alu_a     = tgl_ex_alu_a     + 1;
    always @(ex_alu_b)      if (vcd_active) tgl_ex_alu_b     = tgl_ex_alu_b     + 1;
    always @(ex_alu_res)    if (vcd_active) tgl_ex_alu_res   = tgl_ex_alu_res   + 1;
    always @(ex_rs1_fwd)    if (vcd_active) tgl_ex_rs1_fwd   = tgl_ex_rs1_fwd   + 1;
    always @(ex_rs2_fwd)    if (vcd_active) tgl_ex_rs2_fwd   = tgl_ex_rs2_fwd   + 1;
    always @(mem_alu_res)   if (vcd_active) tgl_mem_alu_res  = tgl_mem_alu_res  + 1;
    always @(wb_write_data) if (vcd_active) tgl_wb_write_data= tgl_wb_write_data+ 1;
    always @(h_stall)       if (vcd_active) tgl_stall        = tgl_stall        + 1;
    always @(h_flush)       if (vcd_active) tgl_flush        = tgl_flush        + 1;
    always @(forward_a)     if (vcd_active) tgl_forward_a    = tgl_forward_a    + 1;
    always @(forward_b)     if (vcd_active) tgl_forward_b    = tgl_forward_b    + 1;

    // =========================================================================
    // MODULE-LEVEL VARIABLES
    // =========================================================================
    integer pass_count, fail_count, ph;
    integer delta_cy [0:3];
    real    cpi [0:3], mips [0:3];
    integer instrs, exp_cy;
    integer stall_count, flush_count;
    real    af_pc, af_instr, af_alu_a, af_alu_b, af_alu_res;
    real    af_rs1, af_rs2, af_mem, af_wb;

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
        $display("  Baseline  : %.2f MHz  cpu_clk (testbench-forced)", CPU_CLK_MHZ);
        $display("  Board clk : 125 MHz  (%.1f ns half-period)", CLK_IN_HALF_NS);
        $display("  Pipeline  : 5-stage, full forwarding, branch-in-EX");
        $display("  Expected CPI: Ph1=1.143  Ph2=1.200  Ph3=1.600  Ph4=1.500");
        $display("  (CPI=1.000 all phases = flush/stall NOT working -- check RTL)");
        $display("  PLL note  : cpu_clk forced to 50 MHz in sim for VCD accuracy.");
        $display("              On silicon: CLKI_DIV=1, CLKFB_DIV=4, CLKOP_DIV=10");
        $display("================================================================");

        // -- 1. RESET ----------------------------------------------------------
        rst_n = 1'b0;
        repeat (RST_CYCLES) @(posedge clk_in);
        rst_n = 1'b1;
        $display("[%0t ns] Reset released", $time);

        // -- 2. SETTLE ---------------------------------------------------------
        repeat (SETTLE_CLK_IN) @(posedge clk_in);
        if (!pll_lock)
            @(posedge pll_lock);
        $display("[%0t ns] Settle complete (pll_lock=%b) -- starting VCD capture",
                 $time, pll_lock);

        // -- 3. OPEN VCD AND DECLARE SIGNALS -----------------------------------
        $dumpfile("power_5s_50mhz.vcd");
        $dumplimit(268_435_456);   // 256 MB hard cap

        // === CLOCKS & RESET ===
        $dumpvars(0, cpu_clk_tb);  // 50 MHz reference -- tool reads period here
        $dumpvars(0, clk_in);
        $dumpvars(0, rst_n);
        $dumpvars(0, pll_lock);

        // === IF STAGE ===
        $dumpvars(0, if_pc);
        $dumpvars(0, if_pc_plus4);
        $dumpvars(0, if_pc_next);
        $dumpvars(0, if_instr);

        // === IF/ID REGISTER ===
        $dumpvars(0, id_pc);
        $dumpvars(0, id_instr);

        // === ID STAGE ===
        $dumpvars(0, id_rs1_data);
        $dumpvars(0, id_rs2_data);
        $dumpvars(0, id_imm);
        $dumpvars(0, id_reg_write);
        $dumpvars(0, id_alu_src);
        $dumpvars(0, id_mem_to_reg);
        $dumpvars(0, id_mem_write);
        $dumpvars(0, id_branch);
        $dumpvars(0, id_jal_sel);
        $dumpvars(0, id_jalr_sel);
        $dumpvars(0, id_alu_op);
        $dumpvars(0, id_csr_we);

        // === HAZARD & FLUSH ===
        $dumpvars(0, h_stall);
        $dumpvars(0, h_flush);

        // === ID/EX REGISTER ===
        $dumpvars(0, ex_pc);
        $dumpvars(0, ex_instr);
        $dumpvars(0, ex_rs1_data);
        $dumpvars(0, ex_rs2_data);
        $dumpvars(0, ex_imm);
        $dumpvars(0, ex_rd_addr);
        $dumpvars(0, ex_rs1_addr);
        $dumpvars(0, ex_rs2_addr);
        $dumpvars(0, ex_reg_write);
        $dumpvars(0, ex_alu_src);
        $dumpvars(0, ex_mem_to_reg);
        $dumpvars(0, ex_mem_write);
        $dumpvars(0, ex_branch);
        $dumpvars(0, ex_jal_sel);
        $dumpvars(0, ex_jalr_sel);
        $dumpvars(0, ex_alu_op);
        $dumpvars(0, ex_csr_we);

        // === EX STAGE ===
        $dumpvars(0, forward_a);
        $dumpvars(0, forward_b);
        $dumpvars(0, ex_rs1_fwd);
        $dumpvars(0, ex_rs2_fwd);
        $dumpvars(0, ex_alu_a);
        $dumpvars(0, ex_alu_b);
        $dumpvars(0, ex_alu_res);
        $dumpvars(0, ex_alu_ctrl);
        $dumpvars(0, ex_zero);
        $dumpvars(0, ex_less_than);
        $dumpvars(0, ex_take_branch);
        $dumpvars(0, ex_branch_tgt);
        $dumpvars(0, ex_jalr_tgt);
        $dumpvars(0, ex_csr_rdata);

        // === EX/MEM REGISTER ===
        $dumpvars(0, mem_alu_res);
        $dumpvars(0, mem_rs2_data);
        $dumpvars(0, mem_rd_addr);
        $dumpvars(0, mem_funct3);
        $dumpvars(0, mem_reg_write);
        $dumpvars(0, mem_mem_to_reg);
        $dumpvars(0, mem_mem_write);
        $dumpvars(0, mem_csr_we);

        // === MEM STAGE (system_top memory bus) ===
        $dumpvars(0, h_addr);
        $dumpvars(0, h_mem_we);
        $dumpvars(0, h_wr_data);
        $dumpvars(0, h_rd_data);
        $dumpvars(0, h_funct3);
        $dumpvars(0, h_ram_byte_we);

        // === MEM/WB REGISTER ===
        $dumpvars(0, wb_alu_res);
        $dumpvars(0, wb_read_data);
        $dumpvars(0, wb_rd_addr);
        $dumpvars(0, wb_reg_write);
        $dumpvars(0, wb_mem_to_reg);
        $dumpvars(0, wb_csr_we);

        // === WB STAGE ===
        $dumpvars(0, wb_write_data);
        $dumpvars(0, wb_csr_rdata);

        // === CSR (lower 32 bits only -- exclude raw 64-bit counters) ===
        $dumpvars(0, h_mcycle);
        $dumpvars(0, h_minstret);

        // === BENCHMARK RESULT REGISTERS ===
        $dumpvars(0, reg_a0);
        $dumpvars(0, reg_a1);
        $dumpvars(0, reg_a2);
        $dumpvars(0, reg_a3);
        $dumpvars(0, reg_s4);

        // === TOP-LEVEL OUTPUTS ===
        $dumpvars(0, h_leds);
        $dumpvars(0, h_test_done);

        // Arm toggle counters at the same moment VCD opens
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
        $display("  RESULTS -- 5-STAGE @ %.2f MHz", CPU_CLK_MHZ);
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

        // -- 8. SWITCHING ACTIVITY REPORT --------------------------------------
        if (cpu_cycle_count > 0) begin
            af_pc    = ($itor(tgl_if_pc)        / ($itor(cpu_cycle_count)*2.0))*100.0;
            af_instr = ($itor(tgl_id_instr)     / ($itor(cpu_cycle_count)*2.0))*100.0;
            af_alu_a = ($itor(tgl_ex_alu_a)     / ($itor(cpu_cycle_count)*2.0))*100.0;
            af_alu_b = ($itor(tgl_ex_alu_b)     / ($itor(cpu_cycle_count)*2.0))*100.0;
            af_alu_res=($itor(tgl_ex_alu_res)   / ($itor(cpu_cycle_count)*2.0))*100.0;
            af_rs1   = ($itor(tgl_ex_rs1_fwd)   / ($itor(cpu_cycle_count)*2.0))*100.0;
            af_rs2   = ($itor(tgl_ex_rs2_fwd)   / ($itor(cpu_cycle_count)*2.0))*100.0;
            af_mem   = ($itor(tgl_mem_alu_res)  / ($itor(cpu_cycle_count)*2.0))*100.0;
            af_wb    = ($itor(tgl_wb_write_data) / ($itor(cpu_cycle_count)*2.0))*100.0;
        end

        $display("");
        $display("================================================================");
        $display("  SWITCHING ACTIVITY REPORT  (for Lattice Power Calculator)");
        $display("  VCD window : %0d cpu_clk cycles @ %.2f MHz",
                 cpu_cycle_count, CPU_CLK_MHZ);
        $display("  (5-stage: pipeline registers add extra toggle activity vs SC)");
        $display("----------------------------------------------------------------");
        $display("  %-22s | %-10s | AF (%%)", "Signal", "Toggles");
        $display("  %-22s | %-10s | ------", "----------------------", "----------");
        $display("  %-22s | %-10d | %0.1f", "if_pc [31:0]",          tgl_if_pc,        af_pc);
        $display("  %-22s | %-10d | %0.1f", "id_instr [31:0]",       tgl_id_instr,     af_instr);
        $display("  %-22s | %-10d | %0.1f", "ex_alu_a [31:0]",       tgl_ex_alu_a,     af_alu_a);
        $display("  %-22s | %-10d | %0.1f", "ex_alu_b [31:0]",       tgl_ex_alu_b,     af_alu_b);
        $display("  %-22s | %-10d | %0.1f", "ex_alu_res [31:0]",     tgl_ex_alu_res,   af_alu_res);
        $display("  %-22s | %-10d | %0.1f", "ex_rs1_forwarded[31:0]",tgl_ex_rs1_fwd,   af_rs1);
        $display("  %-22s | %-10d | %0.1f", "ex_rs2_forwarded[31:0]",tgl_ex_rs2_fwd,   af_rs2);
        $display("  %-22s | %-10d | %0.1f", "mem_alu_res [31:0]",    tgl_mem_alu_res,  af_mem);
        $display("  %-22s | %-10d | %0.1f", "wb_write_data [31:0]",  tgl_wb_write_data,af_wb);
        $display("  %-22s | %-10d | (1-bit)", "stall",               tgl_stall);
        $display("  %-22s | %-10d | (1-bit)", "flush",               tgl_flush);
        $display("  %-22s | %-10d | (2-bit)", "forward_a",           tgl_forward_a);
        $display("  %-22s | %-10d | (2-bit)", "forward_b",           tgl_forward_b);
        $display("----------------------------------------------------------------");
        $display("  >> Average the AF%% values above for manual entry into");
        $display("     Lattice Power Calculator -> Logic Block -> AF(%%) field.");
        $display("  >> 5-stage typically runs HIGHER AF than single-cycle because");
        $display("     pipeline registers toggle every cycle even during stalls.");
        $display("  >> Recommended starting point: AF = 30%% (conservative) to");
        $display("     45%% (typical pipelined workload with forwarding activity).");
        $display("================================================================");

        // -- 9. SUMMARY --------------------------------------------------------
        $display("");
        $display("================================================================");
        $display("  %0d PASSED   %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("  ALL WITHIN TOLERANCE (+-200 cycles) -- OK");
        else begin
            $display("  FAILURES -- diagnosis hints:");
            $display("  * CPI=1.000 all phases  : flush=0, check ex_take_branch");
            $display("  * Ph3 CPI near 1.2      : load-use stall not inserting");
            $display("  * Ph4 CPI near 1.2      : branch flush not firing");
            $display("  * delta_cy = 0          : RAM write failed, check is_ram_addr");
            $display("  * All zeros             : firmware hung (check $readmemh path)");
        end
        $display("================================================================");
        $display("  VCD : power_5s_50mhz.vcd  (86 signals, no memory arrays)");
        $display("  Freq: %.2f MHz  (cpu_clk forced in testbench)", CPU_CLK_MHZ);
        $display("================================================================");
        $display("");

        $finish;
    end

    // =========================================================================
    // TIMEOUT WATCHDOG  (counts cpu_clk, not clk_in)
    // =========================================================================
    initial begin
        repeat (TIMEOUT_CPU_CYC) @(posedge cpu_clk);
        $display("[TIMEOUT] %0d cpu_clk cycles -- tohost write never occurred.",
                 TIMEOUT_CPU_CYC);
        $display("  PC          = 0x%h", if_pc);
        $display("  ID instr    = 0x%h", id_instr);
        $display("  mcycle      = %0d",  h_mcycle);
        $display("  stall_count = %0d  (expected ~40000)", stall_count);
        $display("  flush_count = %0d  (expected ~69992)", flush_count);
        $display("  a0 Ph1      = %0d  (expect ~%0d)", reg_a0, PH1_EXPECTED);
        $display("  a1 Ph2      = %0d  (expect ~%0d)", reg_a1, PH2_EXPECTED);
        $display("  a2 Ph3      = %0d  (expect ~%0d)", reg_a2, PH3_EXPECTED);
        $display("  a3 Ph4      = %0d  (expect ~%0d)", reg_a3, PH4_EXPECTED);
        vcd_active = 0;
        $dumpoff;
        $dumpflush;
        $finish;
    end

endmodule