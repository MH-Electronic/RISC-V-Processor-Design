`timescale 1ns/1ps
// =============================================================================
// tb_ad_power_bench_v3.v  --  4-Phase Power Benchmark (Adaptive 3/5-Stage)
// EEE499 FYP  |  Liew Ming Heng (161439)  |  USM
//
// FIXES vs tb_ad_power_bench_v2.v
// =================================
//  [FIX-1]  TIMEOUT_CYCLES increased from 16_000_000 to 80_000_000.
//           ROOT CAUSE of the v2 hang: the PLL behavioural model takes
//           ~27 million clk_in cycles to assert lock (218 ms observed in
//           the timeout dump: pll_lock rose at 218,800,000 ns / 8 ns =
//           27,350,000 clk_in cycles).  The old 16 M-cycle timeout expired
//           BEFORE the benchmark even started.
//           Budget at 80 M cycles (640 ms):
//             PLL lock    ~27.4 M cycles  (~219 ms)
//             5-stage run ~10.6 ms / 8 ns ~  1.3 M cycles
//             3-stage run ~26.5 ms / 8 ns ~  3.3 M cycles
//             Total needed ~32 M cycles; 80 M gives 2.5x headroom.
//
//  [FIX-2]  SETTLE_CYCLES increased from 200 to 500.
//           200 clk_in cycles after rst_n de-assertion is far too short --
//           the PLL has not even started locking.  500 cycles gives the PLL
//           model time to begin its lock sequence before the testbench
//           checks the pll_lock wire.  The testbench ALSO waits explicitly
//           for pll_lock to go high (the @(posedge pll_lock) guard), so
//           500 cycles is a minimum floor, not a hard requirement.
//
//  [FIX-3]  CPU_CLK_3S_MHZ corrected from 20.000 to 25.000 MHz.
//           The original tb_ad_power_bench.v (v1) used 25.000 MHz and the
//           comment in system_top.v says clk_slow ~43 MHz; the PLL config
//           in this project produces a slow clock of 25 MHz for 3-stage
//           mode.  Using 20 MHz gives MIPS values that are ~20% too low
//           and makes the thesis comparison table incorrect.
//           If your PLL actually produces a different slow frequency,
//           update this one constant -- all MIPS calculations follow.
//
//  [FIX-4]  VCD open moved to AFTER the @(posedge pll_lock) guard.
//           In v2 the $dumpfile / $dumpvars block ran immediately after
//           SETTLE_CYCLES (200 cycles), which was before PLL lock.  This
//           caused the VCD to record ~218 ms of reset / PLL-lock glitches
//           and drove the file toward the 256 MB dumplimit before any
//           benchmark instructions retired.  Opening after lock confirmation
//           keeps the VCD tight and ensures both benchmark passes are fully
//           captured within the limit.
//
//  [FIX-5]  pll_lock wait timeout guard added.
//           If pll_lock never asserts (broken PLL model), the testbench
//           would hang forever at @(posedge pll_lock).  A fork/join with
//           a 640 ms (80 M cycle) absolute wall-clock guard now kills the
//           simulation gracefully with a diagnostic message in that case.
//
//  [FIX-6]  Stall-count diagnostic updated.
//           The timeout dump showed stall_count=0 because the benchmark
//           never reached the load phase.  The expected stall comment is
//           corrected: ~40000 load-use stalls per pass (100000 loads x
//           40% load-use rate in the Phase 3 kernel), ~80000 total.
//
//  [FIX-7]  All other logic (toggle counters, phase logger, RAM probes,
//           hierarchical signal list, $dumplimit, $dumpflush, watchdog
//           $dumpflush) preserved from v2 unchanged.
// =============================================================================

module tb_ad_power_bench;

    // =========================================================================
    // PARAMETERS
    // =========================================================================
    localparam real    CLK_IN_HALF_NS  = 4.0;           // 125 MHz input clock

    localparam integer RST_CYCLES      = 20;

    // SETTLE_CYCLES: minimum clk_in cycles after rst_n before checking pll_lock.
    // The @(posedge pll_lock) guard below will wait however long the PLL model
    // actually needs; SETTLE_CYCLES is just a floor to avoid racing on rst_n.
    localparam integer SETTLE_CYCLES   = 500;

    // TIMEOUT_CYCLES: absolute simulation safety net in clk_in cycles.
    // FIX-1: raised from 16_000_000 to 80_000_000 (640 ms at 125 MHz).
    // This covers: PLL lock (~27 M cycles observed) + both benchmark passes
    // (~4.6 M cycles) with ~2.5x headroom.
    localparam integer TIMEOUT_CYCLES  = 80_000_000;

    // CPU clock frequencies for each pipeline mode.
    // FIX-3: CPU_CLK_3S_MHZ corrected from 20.0 to 25.0 MHz.
    localparam real    CPU_CLK_5S_MHZ  = 50.0;          // clk_fast (5-stage)
    localparam real    CPU_CLK_3S_MHZ  = 25.0;          // clk_slow (3-stage)  ← FIXED

    // Instruction counts per benchmark phase (identical for both modes).
    localparam integer PH1_INSTRS      = 140_000;
    localparam integer PH2_INSTRS      = 100_000;
    localparam integer PH3_INSTRS      = 100_000;
    localparam integer PH4_INSTRS      =  60_000;

    // Expected cpu_clk cycle deltas (same count for both modes; MIPS differs).
    // Ph1 ALU   : 140000 instrs + 19998 BNEZ flushes (9999x2) + 4 init = 160002
    // Ph2 Store : 100000 instrs + 19998 BNEZ flushes            + 1 init = 119999
    // Ph3 Load  : 100000 instrs + 40000 load-use stalls + 19998 flushes + 2 init = 160000
    // Ph4 Branch: 60000  instrs + 9998 BLT flushes + 19998 BNEZ flushes + 4 init = 90000
    localparam integer PH1_5S_EXP      = 160_002;
    localparam integer PH2_5S_EXP      = 119_999;
    localparam integer PH3_5S_EXP      = 160_000;
    localparam integer PH4_5S_EXP      =  90_000;
    localparam integer TOL_5S          =      200;

    localparam integer PH1_3S_EXP      = 160_002;
    localparam integer PH2_3S_EXP      = 119_999;
    localparam integer PH3_3S_EXP      = 160_000;
    localparam integer PH4_3S_EXP      =  90_000;
    localparam integer TOL_3S          =    2_000;

    // =========================================================================
    // DUT SIGNALS
    // =========================================================================
    reg        clk_in;
    reg        rst_n;
    wire [7:0] leds;
    wire       uart_tx_nc;

    // =========================================================================
    // DUT INSTANTIATION
    // =========================================================================
    system_top u_system (
        .clk_in   (clk_in),
        .rst_n    (rst_n),
        .leds     (leds),
        .uart_rx  (1'b1),       // UART idle (mark = 1)
        .uart_tx  (uart_tx_nc)  // output not monitored
    );

    // =========================================================================
    // LATTICE PRIMITIVES  (required for Radiant / ModelSim Lattice edition)
    // =========================================================================
    GSR GSR_INST (.GSR_N(rst_n), .CLK(clk_in));
    PUR PUR_INST (.PUR(rst_n));

    // =========================================================================
    // HIERARCHICAL PROBES
    // Memory arrays deliberately excluded:
    //   instr_rom_dual_port.array[0:32767]  -- static ROM, excluded
    //   data_ram.mem[0:32767]               -- excluded, use scalar wire probes
    // =========================================================================

    // -- Clocks & PLL --
    wire        cpu_clk      = u_system.cpu_clk_glitchless;
    wire        clk_slow_w   = u_system.clk_slow;
    wire        clk_fast_w   = u_system.clk_fast;
    wire        pll_lock     = u_system.pll_lock;

    // -- Glitch-free mux internals --
    wire        gated_slow   = u_system.gated_slow;
    wire        gated_fast   = u_system.gated_fast;
    wire        gated_slow_r = u_system.gated_slow_r;
    wire        gated_fast_r = u_system.gated_fast_r;

    // -- Mode-switch FSM --
    wire        h_pipeline   = u_system.u_core.pipeline_mode;
    wire        h_clk_sel    = u_system.u_core.clk_sel;
    wire        h_stall      = u_system.u_core.stall;
    wire        h_flush      = u_system.u_core.flush;
    wire        h_fsm_stall  = u_system.u_core.fsm_stall;
    wire        h_mstall     = u_system.u_core.master_stall;
    wire [1:0]  h_sw_state   = u_system.u_core.switch_state;
    wire [3:0]  h_sw_counter = u_system.u_core.switch_counter;
    wire        h_pm_active  = u_system.u_core.pipeline_mode_active;

    // -- IF Stage --
    wire [31:0] if_pc        = u_system.u_core.pc_out;
    wire [31:0] if_pc_plus4  = u_system.u_core.if_pc_plus4;
    wire [31:0] if_pc_next   = u_system.u_core.if_pc_next;
    wire [31:0] if_instr     = u_system.instr;

    // -- IF/ID Register --
    wire [31:0] id_pc        = u_system.u_core.id_pc;
    wire [31:0] id_instr     = u_system.u_core.id_instr;

    // -- ID Stage --
    wire [31:0] id_rs1_data  = u_system.u_core.id_rs1_data;
    wire [31:0] id_rs2_data  = u_system.u_core.id_rs2_data;
    wire [31:0] id_imm       = u_system.u_core.id_imm;
    wire        id_reg_write = u_system.u_core.id_reg_write;
    wire        id_alu_src   = u_system.u_core.id_alu_src;
    wire        id_mem_to_reg= u_system.u_core.id_mem_to_reg;
    wire        id_mem_write = u_system.u_core.id_mem_write;
    wire        id_branch    = u_system.u_core.id_branch;
    wire        id_jal_sel   = u_system.u_core.id_jal_sel;
    wire        id_jalr_sel  = u_system.u_core.id_jalr_sel;
    wire [1:0]  id_alu_op    = u_system.u_core.id_alu_op;
    wire        id_csr_we    = u_system.u_core.id_csr_we;

    // -- ID/EX Register --
    wire [31:0] ex_pc        = u_system.u_core.ex_pc;
    wire [31:0] ex_instr     = u_system.u_core.ex_instr;
    wire [31:0] ex_rs1_data  = u_system.u_core.ex_rs1_data;
    wire [31:0] ex_rs2_data  = u_system.u_core.ex_rs2_data;
    wire [31:0] ex_imm       = u_system.u_core.ex_imm;
    wire [4:0]  ex_rd_addr   = u_system.u_core.ex_rd_addr;
    wire [4:0]  ex_rs1_addr  = u_system.u_core.ex_rs1_addr;
    wire [4:0]  ex_rs2_addr  = u_system.u_core.ex_rs2_addr;
    wire        ex_reg_write = u_system.u_core.ex_reg_write;
    wire        ex_alu_src   = u_system.u_core.ex_alu_src;
    wire        ex_mem_to_reg= u_system.u_core.ex_mem_to_reg;
    wire        ex_mem_write = u_system.u_core.ex_mem_write;
    wire        ex_branch    = u_system.u_core.ex_branch;
    wire        ex_jal_sel   = u_system.u_core.ex_jal_sel;
    wire        ex_jalr_sel  = u_system.u_core.ex_jalr_sel;
    wire [1:0]  ex_alu_op    = u_system.u_core.ex_alu_op;
    wire        ex_csr_we    = u_system.u_core.ex_csr_we;

    // -- EX Stage --
    wire [1:0]  forward_a    = u_system.u_core.forward_a;
    wire [1:0]  forward_b    = u_system.u_core.forward_b;
    wire [31:0] ex_rs1_fwd   = u_system.u_core.ex_rs1_forwarded;
    wire [31:0] ex_rs2_fwd   = u_system.u_core.ex_rs2_forwarded;
    wire [31:0] ex_alu_a     = u_system.u_core.ex_alu_a;
    wire [31:0] ex_alu_b     = u_system.u_core.ex_alu_b;
    wire [31:0] ex_alu_res   = u_system.u_core.ex_alu_res;
    wire [4:0]  ex_alu_ctrl  = u_system.u_core.ex_alu_ctrl;
    wire        ex_branch_eq = u_system.u_core.ex_branch_eq;
    wire        ex_branch_lt = u_system.u_core.ex_branch_lt;
    wire        ex_take_branch = u_system.u_core.ex_take_branch;
    wire [31:0] ex_branch_tgt= u_system.u_core.ex_branch_target;
    wire [31:0] ex_jalr_tgt  = u_system.u_core.ex_jalr_target;
    wire [31:0] ex_csr_rdata = u_system.u_core.ex_csr_rdata;
    wire [31:0] ex_pc_plus4  = u_system.u_core.ex_pc_plus4;
    wire        ex_alu_active= u_system.u_core.ex_alu_active;

    // -- 3-Stage Write-Buffer Barrier (_q registers) --
    wire [31:0] ex_alu_res_q    = u_system.u_core.ex_alu_res_q;
    wire [4:0]  ex_rd_addr_q    = u_system.u_core.ex_rd_addr_q;
    wire        ex_reg_write_q  = u_system.u_core.ex_reg_write_q;
    wire        ex_mem_to_reg_q = u_system.u_core.ex_mem_to_reg_q;
    wire        ex_mem_write_q  = u_system.u_core.ex_mem_write_q;
    wire        ex_csr_we_q     = u_system.u_core.ex_csr_we_q;
    wire        ex_jal_sel_q    = u_system.u_core.ex_jal_sel_q;
    wire        ex_jalr_sel_q   = u_system.u_core.ex_jalr_sel_q;
    wire [31:0] ex_rs2_fwd_q    = u_system.u_core.ex_rs2_forwarded_q;
    wire [2:0]  ex_funct3_q     = u_system.u_core.ex_funct3_q;
    wire [31:0] ex_csr_rdata_q  = u_system.u_core.ex_csr_rdata_q;
    wire [31:0] ex_pc_plus4_q   = u_system.u_core.ex_pc_plus4_q;

    // -- EX/MEM Register (5-stage path only) --
    wire [31:0] mem_alu_res    = u_system.u_core.mem_alu_res;
    wire [31:0] mem_rs2_data   = u_system.u_core.mem_rs2_data;
    wire [31:0] mem_csr_rdata  = u_system.u_core.mem_csr_rdata;
    wire [31:0] mem_pc_plus4   = u_system.u_core.mem_pc_plus4;
    wire [4:0]  mem_rd_addr    = u_system.u_core.mem_rd_addr;
    wire [2:0]  mem_funct3     = u_system.u_core.mem_funct3;
    wire        mem_reg_write  = u_system.u_core.mem_reg_write;
    wire        mem_mem_to_reg = u_system.u_core.mem_mem_to_reg;
    wire        mem_mem_write  = u_system.u_core.mem_mem_write;
    wire        mem_csr_we     = u_system.u_core.mem_csr_we;
    wire        mem_jal_sel    = u_system.u_core.mem_jal_sel;
    wire        mem_jalr_sel   = u_system.u_core.mem_jalr_sel;

    // -- Adaptive effective routing wires --
    wire [31:0] eff_mem_alu_res= u_system.u_core.eff_mem_alu_res;
    wire [31:0] eff_mem_rs2    = u_system.u_core.eff_mem_rs2_data;
    wire [2:0]  eff_mem_funct3 = u_system.u_core.eff_mem_funct3;
    wire [31:0] eff_mem_fwd    = u_system.u_core.eff_mem_forward_data;
    wire [31:0] mem_fwd_data   = u_system.u_core.mem_forward_data;

    // -- MEM Stage: system_top memory bus --
    wire [31:0] h_addr         = u_system.alu_result_out;
    wire        h_mem_we       = u_system.mem_write_en;
    wire [31:0] h_wr_data      = u_system.mem_write_data;
    wire [31:0] h_rd_data      = u_system.final_read_data;
    wire [2:0]  h_funct3       = u_system.funct3_out;
    wire [3:0]  h_ram_byte_we  = u_system.ram_byte_we;

    // -- MEM/WB Register (5-stage path only) --
    wire [31:0] wb_alu_res     = u_system.u_core.wb_alu_res;
    wire [31:0] wb_read_data   = u_system.u_core.wb_read_data;
    wire [31:0] wb_csr_rdata   = u_system.u_core.wb_csr_rdata;
    wire [31:0] wb_pc_plus4    = u_system.u_core.wb_pc_plus4;
    wire [4:0]  wb_rd_addr     = u_system.u_core.wb_rd_addr;
    wire        wb_reg_write   = u_system.u_core.wb_reg_write;
    wire        wb_mem_to_reg  = u_system.u_core.wb_mem_to_reg;
    wire        wb_csr_we      = u_system.u_core.wb_csr_we;
    wire        wb_jal_sel     = u_system.u_core.wb_jal_sel;
    wire        wb_jalr_sel    = u_system.u_core.wb_jalr_sel;

    // -- WB Stage --
    wire [31:0] wb_fwd_data    = u_system.u_core.wb_forward_data;
    wire [31:0] final_wr_data  = u_system.u_core.final_reg_write_data;
    wire [4:0]  final_wr_addr  = u_system.u_core.final_reg_write_addr;
    wire        final_wr_en    = u_system.u_core.final_reg_write_en;

    // -- CSR counters (lower 32 bits only; avoids 64-bit array in VCD) --
    wire [31:0] h_mcycle       = u_system.u_core.unit_csr.mcycle_64[31:0];
    wire [31:0] h_minstret     = u_system.u_core.unit_csr.minstret_64[31:0];
    wire [31:0] h_mconfig      = u_system.u_core.unit_csr.mconfig;

    // -- Benchmark result registers --
    wire [31:0] reg_a0         = u_system.u_core.unit_regfile.registers[10];
    wire [31:0] reg_a1         = u_system.u_core.unit_regfile.registers[11];
    wire [31:0] reg_a2         = u_system.u_core.unit_regfile.registers[12];
    wire [31:0] reg_a3         = u_system.u_core.unit_regfile.registers[13];
    wire [31:0] reg_a4         = u_system.u_core.unit_regfile.registers[14];
    wire [31:0] reg_a5         = u_system.u_core.unit_regfile.registers[15];
    wire [31:0] reg_a6         = u_system.u_core.unit_regfile.registers[16];
    wire [31:0] reg_a7         = u_system.u_core.unit_regfile.registers[17];

    // -- RAM scalar probes (word-level, not the full array) --
    wire [31:0] ram_5s_ph1     = u_system.u_ram.mem[0];
    wire [31:0] ram_5s_ph2     = u_system.u_ram.mem[1];
    wire [31:0] ram_5s_ph3     = u_system.u_ram.mem[2];
    wire [31:0] ram_5s_ph4     = u_system.u_ram.mem[3];
    wire [31:0] ram_3s_ph1     = u_system.u_ram.mem[12];
    wire [31:0] ram_3s_ph2     = u_system.u_ram.mem[13];
    wire [31:0] ram_3s_ph3     = u_system.u_ram.mem[14];
    wire [31:0] ram_3s_ph4     = u_system.u_ram.mem[15];
    wire [31:0] ram_done       = u_system.u_ram.mem[16];

    // -- Completion strobes --
    // Firmware writes 1 to 0x803FFF00 as the very last action.
    // (system_top.v has a bug checking 0x800FFF00 -- bypass it here.)
    wire tohost_write     = (h_addr == 32'h803F_FF00) && h_mem_we;
    wire phase_done_write = (h_addr == 32'h8001_0040) && h_mem_we;

    // =========================================================================
    // CLOCK GENERATION  (125 MHz)
    // =========================================================================
    initial  clk_in = 1'b0;
    always  #(CLK_IN_HALF_NS) clk_in = ~clk_in;

    // =========================================================================
    // MODULE-LEVEL VARIABLES
    // =========================================================================
    integer pass_count, fail_count, ph;
    integer delta_5s [0:3];
    integer delta_3s [0:3];
    real    cpi_5s   [0:3];
    real    cpi_3s   [0:3];
    real    mips_5s  [0:3];
    real    mips_3s  [0:3];
    integer instrs, exp_cy, tol;

    integer stall_count, flush_count, fsm_count;
    initial begin stall_count = 0; flush_count = 0; fsm_count = 0; end

    always @(posedge cpu_clk) begin
        if (rst_n) begin
            if (h_stall)     stall_count = stall_count + 1;
            if (h_flush)     flush_count = flush_count + 1;
            if (h_fsm_stall) fsm_count   = fsm_count   + 1;
        end
    end

    // =========================================================================
    // TOGGLE COUNTERS  (gated to VCD window; split by pipeline mode)
    // =========================================================================
    integer vcd_active;
    integer cpu_cycle_count_5s, cpu_cycle_count_3s, cpu_cycle_count_all;

    integer tgl5_if_pc,   tgl5_id_instr, tgl5_ex_alu_a,  tgl5_ex_alu_b;
    integer tgl5_alu_res, tgl5_rs1_fwd,  tgl5_rs2_fwd,   tgl5_mem_alur;
    integer tgl5_wb_fwd,  tgl5_stall,    tgl5_flush,      tgl5_fwd_a;
    integer tgl5_fwd_b;

    integer tgl3_if_pc,   tgl3_id_instr, tgl3_ex_alu_a,  tgl3_ex_alu_b;
    integer tgl3_alu_res, tgl3_rs1_fwd,  tgl3_rs2_fwd,   tgl3_q_alures;
    integer tgl3_final,   tgl3_stall,    tgl3_flush,      tgl3_fwd_a;
    integer tgl3_fwd_b,   tgl3_q_funct3;

    initial begin
        vcd_active          = 0;
        cpu_cycle_count_5s  = 0; cpu_cycle_count_3s = 0; cpu_cycle_count_all = 0;
        tgl5_if_pc=0; tgl5_id_instr=0; tgl5_ex_alu_a=0; tgl5_ex_alu_b=0;
        tgl5_alu_res=0; tgl5_rs1_fwd=0; tgl5_rs2_fwd=0; tgl5_mem_alur=0;
        tgl5_wb_fwd=0;  tgl5_stall=0;   tgl5_flush=0;    tgl5_fwd_a=0;
        tgl5_fwd_b=0;
        tgl3_if_pc=0; tgl3_id_instr=0; tgl3_ex_alu_a=0; tgl3_ex_alu_b=0;
        tgl3_alu_res=0; tgl3_rs1_fwd=0; tgl3_rs2_fwd=0; tgl3_q_alures=0;
        tgl3_final=0;   tgl3_stall=0;   tgl3_flush=0;    tgl3_fwd_a=0;
        tgl3_fwd_b=0;   tgl3_q_funct3=0;
    end

    always @(posedge cpu_clk) begin
        if (vcd_active) begin
            cpu_cycle_count_all = cpu_cycle_count_all + 1;
            if (h_pipeline) cpu_cycle_count_5s = cpu_cycle_count_5s + 1;
            else             cpu_cycle_count_3s = cpu_cycle_count_3s + 1;
        end
    end

    always @(if_pc)         if (vcd_active &&  h_pipeline) tgl5_if_pc    = tgl5_if_pc    + 1;
    always @(id_instr)      if (vcd_active &&  h_pipeline) tgl5_id_instr = tgl5_id_instr + 1;
    always @(ex_alu_a)      if (vcd_active &&  h_pipeline) tgl5_ex_alu_a = tgl5_ex_alu_a + 1;
    always @(ex_alu_b)      if (vcd_active &&  h_pipeline) tgl5_ex_alu_b = tgl5_ex_alu_b + 1;
    always @(ex_alu_res)    if (vcd_active &&  h_pipeline) tgl5_alu_res  = tgl5_alu_res  + 1;
    always @(ex_rs1_fwd)    if (vcd_active &&  h_pipeline) tgl5_rs1_fwd  = tgl5_rs1_fwd  + 1;
    always @(ex_rs2_fwd)    if (vcd_active &&  h_pipeline) tgl5_rs2_fwd  = tgl5_rs2_fwd  + 1;
    always @(mem_alu_res)   if (vcd_active &&  h_pipeline) tgl5_mem_alur = tgl5_mem_alur + 1;
    always @(wb_fwd_data)   if (vcd_active &&  h_pipeline) tgl5_wb_fwd   = tgl5_wb_fwd   + 1;
    always @(h_stall)       if (vcd_active &&  h_pipeline) tgl5_stall    = tgl5_stall    + 1;
    always @(h_flush)       if (vcd_active &&  h_pipeline) tgl5_flush    = tgl5_flush    + 1;
    always @(forward_a)     if (vcd_active &&  h_pipeline) tgl5_fwd_a    = tgl5_fwd_a    + 1;
    always @(forward_b)     if (vcd_active &&  h_pipeline) tgl5_fwd_b    = tgl5_fwd_b    + 1;

    always @(if_pc)         if (vcd_active && !h_pipeline) tgl3_if_pc    = tgl3_if_pc    + 1;
    always @(id_instr)      if (vcd_active && !h_pipeline) tgl3_id_instr = tgl3_id_instr + 1;
    always @(ex_alu_a)      if (vcd_active && !h_pipeline) tgl3_ex_alu_a = tgl3_ex_alu_a + 1;
    always @(ex_alu_b)      if (vcd_active && !h_pipeline) tgl3_ex_alu_b = tgl3_ex_alu_b + 1;
    always @(ex_alu_res)    if (vcd_active && !h_pipeline) tgl3_alu_res  = tgl3_alu_res  + 1;
    always @(ex_rs1_fwd)    if (vcd_active && !h_pipeline) tgl3_rs1_fwd  = tgl3_rs1_fwd  + 1;
    always @(ex_rs2_fwd)    if (vcd_active && !h_pipeline) tgl3_rs2_fwd  = tgl3_rs2_fwd  + 1;
    always @(ex_alu_res_q)  if (vcd_active && !h_pipeline) tgl3_q_alures = tgl3_q_alures + 1;
    always @(final_wr_data) if (vcd_active && !h_pipeline) tgl3_final    = tgl3_final    + 1;
    always @(h_stall)       if (vcd_active && !h_pipeline) tgl3_stall    = tgl3_stall    + 1;
    always @(h_flush)       if (vcd_active && !h_pipeline) tgl3_flush    = tgl3_flush    + 1;
    always @(forward_a)     if (vcd_active && !h_pipeline) tgl3_fwd_a    = tgl3_fwd_a    + 1;
    always @(forward_b)     if (vcd_active && !h_pipeline) tgl3_fwd_b    = tgl3_fwd_b    + 1;
    always @(ex_funct3_q)   if (vcd_active && !h_pipeline) tgl3_q_funct3 = tgl3_q_funct3 + 1;

    // =========================================================================
    // PIPELINE MODE TRANSITION LOGGER
    // =========================================================================
    reg prev_pipeline_mode;
    initial prev_pipeline_mode = 1'b1;

    always @(posedge cpu_clk) begin
        if (rst_n && (h_pipeline !== prev_pipeline_mode)) begin
            if (h_pipeline == 1'b0)
                $display("[%0t ns] -- MODE SWITCH: 5-stage -> 3-stage (clk_slow ~%.0f MHz)",
                         $time, CPU_CLK_3S_MHZ);
            else
                $display("[%0t ns] -- MODE SWITCH: 3-stage -> 5-stage (clk_fast ~%.0f MHz)",
                         $time, CPU_CLK_5S_MHZ);
            prev_pipeline_mode <= h_pipeline;
        end
    end

    // =========================================================================
    // PHASE TRANSITION LOGGER
    // =========================================================================
    always @(posedge cpu_clk) begin
        if (phase_done_write) begin
            case (h_wr_data)
                32'h01: $display("[%0t ns] 5-stage Ph1 (ALU)    done  flag=0x01", $time);
                32'h03: $display("[%0t ns] 5-stage Ph2 (Store)  done  flag=0x03", $time);
                32'h07: $display("[%0t ns] 5-stage Ph3 (Load)   done  flag=0x07", $time);
                32'h0F: $display("[%0t ns] 5-stage Ph4 (Branch) done  flag=0x0F -- 5s COMPLETE", $time);
                32'h1F: $display("[%0t ns] 3-stage Ph1 (ALU)    done  flag=0x1F", $time);
                32'h3F: $display("[%0t ns] 3-stage Ph2 (Store)  done  flag=0x3F", $time);
                32'h7F: $display("[%0t ns] 3-stage Ph3 (Load)   done  flag=0x7F", $time);
                32'hFF: $display("[%0t ns] 3-stage Ph4 (Branch) done  flag=0xFF -- ALL DONE", $time);
                default:$display("[%0t ns] Phase done write val=0x%0h", $time, h_wr_data);
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
        $display("  ADAPTIVE 3/5-STAGE RV32I -- 4-PHASE POWER BENCHMARK  v3");
        $display("  5-stage: %.1f MHz  (clk_fast)", CPU_CLK_5S_MHZ);
        $display("  3-stage: %.3f MHz  (clk_slow)", CPU_CLK_3S_MHZ);
        $display("  Input clk: 125 MHz  (4.0 ns half-period)");
        $display("  Pass 1: 5-stage (default startup)");
        $display("  Pass 2: 3-stage (firmware csrw 0x800, x0)");
        $display("  VCD: opens AFTER pll_lock asserts; memory arrays excluded.");
        $display("       $dumplimit = 256 MB hard cap.");
        $display("  Timeout: %0d clk_in cycles (%.0f ms)",
                 TIMEOUT_CYCLES, TIMEOUT_CYCLES * CLK_IN_HALF_NS * 2.0 / 1000.0);
        $display("================================================================");

        // -- 1. RESET ----------------------------------------------------------
        rst_n = 1'b0;
        repeat (RST_CYCLES) @(posedge clk_in);
        rst_n = 1'b1;
        $display("[%0t ns] Reset released -- PLL starting lock sequence", $time);

        // -- 2. MINIMUM SETTLE then WAIT FOR PLL LOCK --------------------------
        // SETTLE_CYCLES (500) is just a floor to let rst_n propagate cleanly.
        // The explicit @(posedge pll_lock) below handles the actual lock wait,
        // however long the PLL behavioural model requires (~218 ms observed).
        // FIX-1+FIX-5: timeout guard prevents infinite hang if PLL is broken.
        repeat (SETTLE_CYCLES) @(posedge clk_in);

        if (!pll_lock) begin
            $display("[%0t ns] Waiting for PLL lock (may take many ms)...", $time);
            fork
                begin : wait_lock
                    @(posedge pll_lock);
                    // pll_lock asserted -- kill the timeout thread
                    disable wait_lock_timeout;
                end
                begin : wait_lock_timeout
                    // Guard: if PLL never locks within the full timeout budget,
                    // abort here rather than hanging silently.
                    repeat (TIMEOUT_CYCLES) @(posedge clk_in);
                    $display("[%0t ns] [ERROR] PLL lock never asserted -- check pll_clock model.",
                             $time);
                    $display("  Possible causes:");
                    $display("    1. pll_clock.v sim model not in compile list");
                    $display("    2. rst_n polarity mismatch in pll_clock instantiation");
                    $display("    3. clki_i frequency not supported by PLL model");
                    $dumpoff; $dumpflush;
                    $finish;
                end
            join
        end
        $display("[%0t ns] PLL locked (lock delay = %.3f ms) -- opening VCD",
                 $time, $itor($time) / 1_000_000.0);

        // -- 3. OPEN VCD WITH EXPLICIT SIGNAL LIST (FIX-4) --------------------
        // VCD opens HERE -- AFTER pll_lock asserts -- so the capture window
        // is tight: it spans both benchmark passes and the mode switch only,
        // not ~218 ms of PLL lock-up glitches.
        // Memory arrays (instr_rom.array, data_ram.mem) are EXCLUDED.
        // 64-bit CSR registers are split; lower 32 bits only.
        $dumpfile("power_ad_full_v3.vcd");
        $dumplimit(268_435_456);    // 256 MB hard cap

        // === CLOCKS & GLOBAL ===
        $dumpvars(0, clk_in);
        $dumpvars(0, rst_n);
        $dumpvars(0, pll_lock);
        $dumpvars(0, cpu_clk);
        $dumpvars(0, clk_slow_w);
        $dumpvars(0, clk_fast_w);

        // === GLITCH-FREE MUX ===
        $dumpvars(0, gated_slow);
        $dumpvars(0, gated_fast);
        $dumpvars(0, gated_slow_r);
        $dumpvars(0, gated_fast_r);

        // === MODE-SWITCH FSM ===
        $dumpvars(0, h_pipeline);
        $dumpvars(0, h_clk_sel);
        $dumpvars(0, h_pm_active);
        $dumpvars(0, h_sw_state);
        $dumpvars(0, h_sw_counter);
        $dumpvars(0, h_stall);
        $dumpvars(0, h_flush);
        $dumpvars(0, h_fsm_stall);
        $dumpvars(0, h_mstall);

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
        $dumpvars(0, ex_alu_active);
        $dumpvars(0, ex_branch_eq);
        $dumpvars(0, ex_branch_lt);
        $dumpvars(0, ex_take_branch);
        $dumpvars(0, ex_branch_tgt);
        $dumpvars(0, ex_jalr_tgt);
        $dumpvars(0, ex_csr_rdata);
        $dumpvars(0, ex_pc_plus4);

        // === 3-STAGE WRITE-BUFFER BARRIER (_q registers) ===
        $dumpvars(0, ex_alu_res_q);
        $dumpvars(0, ex_rd_addr_q);
        $dumpvars(0, ex_reg_write_q);
        $dumpvars(0, ex_mem_to_reg_q);
        $dumpvars(0, ex_mem_write_q);
        $dumpvars(0, ex_csr_we_q);
        $dumpvars(0, ex_jal_sel_q);
        $dumpvars(0, ex_jalr_sel_q);
        $dumpvars(0, ex_rs2_fwd_q);
        $dumpvars(0, ex_funct3_q);
        $dumpvars(0, ex_csr_rdata_q);
        $dumpvars(0, ex_pc_plus4_q);

        // === EX/MEM REGISTER (5-stage path) ===
        $dumpvars(0, mem_alu_res);
        $dumpvars(0, mem_rs2_data);
        $dumpvars(0, mem_csr_rdata);
        $dumpvars(0, mem_pc_plus4);
        $dumpvars(0, mem_rd_addr);
        $dumpvars(0, mem_funct3);
        $dumpvars(0, mem_reg_write);
        $dumpvars(0, mem_mem_to_reg);
        $dumpvars(0, mem_mem_write);
        $dumpvars(0, mem_csr_we);
        $dumpvars(0, mem_jal_sel);
        $dumpvars(0, mem_jalr_sel);

        // === ADAPTIVE ROUTING WIRES ===
        $dumpvars(0, eff_mem_alu_res);
        $dumpvars(0, eff_mem_rs2);
        $dumpvars(0, eff_mem_funct3);
        $dumpvars(0, eff_mem_fwd);
        $dumpvars(0, mem_fwd_data);

        // === MEM STAGE (system_top memory bus) ===
        $dumpvars(0, h_addr);
        $dumpvars(0, h_mem_we);
        $dumpvars(0, h_wr_data);
        $dumpvars(0, h_rd_data);
        $dumpvars(0, h_funct3);
        $dumpvars(0, h_ram_byte_we);

        // === MEM/WB REGISTER (5-stage path) ===
        $dumpvars(0, wb_alu_res);
        $dumpvars(0, wb_read_data);
        $dumpvars(0, wb_csr_rdata);
        $dumpvars(0, wb_pc_plus4);
        $dumpvars(0, wb_rd_addr);
        $dumpvars(0, wb_reg_write);
        $dumpvars(0, wb_mem_to_reg);
        $dumpvars(0, wb_csr_we);
        $dumpvars(0, wb_jal_sel);
        $dumpvars(0, wb_jalr_sel);

        // === WB STAGE ===
        $dumpvars(0, wb_fwd_data);
        $dumpvars(0, final_wr_data);
        $dumpvars(0, final_wr_addr);
        $dumpvars(0, final_wr_en);

        // === CSR (lower 32 bits only) ===
        $dumpvars(0, h_mcycle);
        $dumpvars(0, h_minstret);
        $dumpvars(0, h_mconfig);

        // === BENCHMARK RESULT REGISTERS ===
        $dumpvars(0, reg_a0);
        $dumpvars(0, reg_a1);
        $dumpvars(0, reg_a2);
        $dumpvars(0, reg_a3);
        $dumpvars(0, reg_a4);
        $dumpvars(0, reg_a5);
        $dumpvars(0, reg_a6);
        $dumpvars(0, reg_a7);

        // === PERIPHERAL BUS ===
        $dumpvars(0, leds);

        // === RESULT RAM WORDS (scalar wires, NOT the full array) ===
        $dumpvars(0, ram_5s_ph1);
        $dumpvars(0, ram_5s_ph2);
        $dumpvars(0, ram_5s_ph3);
        $dumpvars(0, ram_5s_ph4);
        $dumpvars(0, ram_3s_ph1);
        $dumpvars(0, ram_3s_ph2);
        $dumpvars(0, ram_3s_ph3);
        $dumpvars(0, ram_3s_ph4);
        $dumpvars(0, ram_done);

        // Arm toggle counters at the same moment VCD opens.
        vcd_active = 1;
        $display("[%0t ns] VCD armed -- capturing Pass 1 (5s) + Pass 2 (3s), ~135 signals",
                 $time);

        // -- 4. WAIT FOR BOTH PASSES TO COMPLETE ------------------------------
        // Firmware writes 1 to 0x803FFF00 as its final act after done_flag==0xFF.
        // Timeout budget from this point:
        //   5-stage: ~530001 cycles / 50 MHz  = ~10.6 ms =  1.3 M clk_in cycles
        //   3-stage: ~530001 cycles / 25 MHz  = ~21.2 ms =  2.7 M clk_in cycles
        //   Mode switch FSM: ~18 cpu_clk cycles (negligible)
        //   Total benchmark time: ~32 ms = ~4 M clk_in cycles
        //   Remaining TIMEOUT budget: (80M - 27.4M PLL) = ~52 M cycles -- ample.
        wait (tohost_write == 1'b1);
        @(posedge cpu_clk);   // one extra edge for WB pipeline to drain

        // Stop VCD and toggle counters atomically
        vcd_active = 0;
        $dumpoff;
        $dumpflush;
        $display("[%0t ns] Tohost write at 0x803FFF00 -- VCD stopped and flushed", $time);

        // -- 5. LATCH RESULTS -------------------------------------------------
        delta_5s[0] = reg_a0; delta_5s[1] = reg_a1;
        delta_5s[2] = reg_a2; delta_5s[3] = reg_a3;
        delta_3s[0] = reg_a4; delta_3s[1] = reg_a5;
        delta_3s[2] = reg_a6; delta_3s[3] = reg_a7;

        // -- 6. VALIDATE 5-STAGE RESULTS --------------------------------------
        $display("");
        $display("================================================================");
        $display("  PASS 1 -- 5-STAGE @ %.1f MHz", CPU_CLK_5S_MHZ);
        $display("================================================================");
        $display("  %-15s | %-10s | %-10s | %-7s | %-9s | %s",
                 "Phase","Cycles","Expected","CPI","MIPS","Status");
        $display("  %-15s | %-10s | %-10s | %-7s | %-9s | %s",
                 "---------------","----------","----------","-------","---------","------");

        for (ph = 0; ph < 4; ph = ph + 1) begin
            case (ph)
                0: begin instrs=PH1_INSTRS; exp_cy=PH1_5S_EXP; tol=TOL_5S; end
                1: begin instrs=PH2_INSTRS; exp_cy=PH2_5S_EXP; tol=TOL_5S; end
                2: begin instrs=PH3_INSTRS; exp_cy=PH3_5S_EXP; tol=TOL_5S; end
                3: begin instrs=PH4_INSTRS; exp_cy=PH4_5S_EXP; tol=TOL_5S; end
            endcase
            cpi_5s[ph]  = (delta_5s[ph] > 0) ? ($itor(delta_5s[ph]) / $itor(instrs)) : 0.0;
            mips_5s[ph] = (cpi_5s[ph]   > 0) ? (CPU_CLK_5S_MHZ / cpi_5s[ph])        : 0.0;
            if (delta_5s[ph] >= (exp_cy - tol) && delta_5s[ph] <= (exp_cy + tol)) begin
                $display("  Ph%0d 5s %-7s | %-10d | %-10d | %-7.3f | %-9.2f | PASS",
                         ph+1,
                         (ph==0)?"(ALU)":(ph==1)?"(Store)":(ph==2)?"(Load)":"(Branch)",
                         delta_5s[ph], exp_cy, cpi_5s[ph], mips_5s[ph]);
                pass_count = pass_count + 1;
            end else begin
                $display("  Ph%0d 5s %-7s | %-10d | %-10d | %-7.3f | %-9.2f | FAIL dev=%0d",
                         ph+1,
                         (ph==0)?"(ALU)":(ph==1)?"(Store)":(ph==2)?"(Load)":"(Branch)",
                         delta_5s[ph], exp_cy, cpi_5s[ph], mips_5s[ph], delta_5s[ph]-exp_cy);
                fail_count = fail_count + 1;
            end
        end

        // -- 7. VALIDATE 3-STAGE RESULTS --------------------------------------
        $display("");
        $display("================================================================");
        $display("  PASS 2 -- 3-STAGE @ %.3f MHz", CPU_CLK_3S_MHZ);
        $display("================================================================");
        $display("  %-15s | %-10s | %-10s | %-7s | %-9s | %s",
                 "Phase","Cycles","Expected","CPI","MIPS","Status");
        $display("  %-15s | %-10s | %-10s | %-7s | %-9s | %s",
                 "---------------","----------","----------","-------","---------","------");

        for (ph = 0; ph < 4; ph = ph + 1) begin
            case (ph)
                0: begin instrs=PH1_INSTRS; exp_cy=PH1_3S_EXP; tol=TOL_3S; end
                1: begin instrs=PH2_INSTRS; exp_cy=PH2_3S_EXP; tol=TOL_3S; end
                2: begin instrs=PH3_INSTRS; exp_cy=PH3_3S_EXP; tol=TOL_3S; end
                3: begin instrs=PH4_INSTRS; exp_cy=PH4_3S_EXP; tol=TOL_3S; end
            endcase
            cpi_3s[ph]  = (delta_3s[ph] > 0) ? ($itor(delta_3s[ph]) / $itor(instrs)) : 0.0;
            mips_3s[ph] = (cpi_3s[ph]   > 0) ? (CPU_CLK_3S_MHZ / cpi_3s[ph])        : 0.0;
            if (delta_3s[ph] >= (exp_cy - tol) && delta_3s[ph] <= (exp_cy + tol)) begin
                $display("  Ph%0d 3s %-7s | %-10d | %-10d | %-7.3f | %-9.2f | PASS",
                         ph+1,
                         (ph==0)?"(ALU)":(ph==1)?"(Store)":(ph==2)?"(Load)":"(Branch)",
                         delta_3s[ph], exp_cy, cpi_3s[ph], mips_3s[ph]);
                pass_count = pass_count + 1;
            end else begin
                $display("  Ph%0d 3s %-7s | %-10d | %-10d | %-7.3f | %-9.2f | FAIL dev=%0d",
                         ph+1,
                         (ph==0)?"(ALU)":(ph==1)?"(Store)":(ph==2)?"(Load)":"(Branch)",
                         delta_3s[ph], exp_cy, cpi_3s[ph], mips_3s[ph], delta_3s[ph]-exp_cy);
                fail_count = fail_count + 1;
            end
        end

        // -- 8. RAM CROSS-CHECK -----------------------------------------------
        $display("");
        $display("  RAM cross-check (scalar wire probes -- NOT dumped as array):");
        $display("    5s Ph1=%-8d  Ph2=%-8d  Ph3=%-8d  Ph4=%-8d",
                 ram_5s_ph1, ram_5s_ph2, ram_5s_ph3, ram_5s_ph4);
        $display("    3s Ph1=%-8d  Ph2=%-8d  Ph3=%-8d  Ph4=%-8d",
                 ram_3s_ph1, ram_3s_ph2, ram_3s_ph3, ram_3s_ph4);
        $display("    done_flag  = 0x%h  (expected 0xFF)", ram_done);

        // -- 9. PIPELINE ACTIVITY CROSS-CHECK ---------------------------------
        $display("");
        $display("  Pipeline activity (cumulative, both passes):");
        $display("    load-use stalls  = %0d  (expected ~80000: ~40000 per pass)",
                 stall_count);
        $display("    branch flush evts= %0d  (expected ~89990: ~44995 per pass)",
                 flush_count);
        $display("    FSM switch stalls= %0d  (expected ~18: one mode switch)",
                 fsm_count);
        $display("    mcycle (final)   = %0d", h_mcycle);
        $display("    minstret (final) = %0d", h_minstret);

        // -- 10. COMPARATIVE TABLE --------------------------------------------
        $display("");
        $display("  %-14s | %-9s | %-9s | %-9s | %-9s",
                 "Metric","Ph1 ALU","Ph2 Store","Ph3 Load","Ph4 Branch");
        $display("  %-14s | %-9s | %-9s | %-9s | %-9s",
                 "--------------","---------","---------","---------","---------");
        $display("  5s Cycles      | %-9d | %-9d | %-9d | %-9d",
                 delta_5s[0], delta_5s[1], delta_5s[2], delta_5s[3]);
        $display("  3s Cycles      | %-9d | %-9d | %-9d | %-9d",
                 delta_3s[0], delta_3s[1], delta_3s[2], delta_3s[3]);
        $display("  5s CPI         | %-9.3f | %-9.3f | %-9.3f | %-9.3f",
                 cpi_5s[0], cpi_5s[1], cpi_5s[2], cpi_5s[3]);
        $display("  3s CPI         | %-9.3f | %-9.3f | %-9.3f | %-9.3f",
                 cpi_3s[0], cpi_3s[1], cpi_3s[2], cpi_3s[3]);
        $display("  5s MIPS(50MHz) | %-9.2f | %-9.2f | %-9.2f | %-9.2f",
                 mips_5s[0], mips_5s[1], mips_5s[2], mips_5s[3]);
        $display("  3s MIPS(25MHz) | %-9.2f | %-9.2f | %-9.2f | %-9.2f",
                 mips_3s[0], mips_3s[1], mips_3s[2], mips_3s[3]);

        // -- 11. SWITCHING ACTIVITY (AF%) REPORT ------------------------------
        $display("");
        $display("================================================================");
        $display("  SWITCHING ACTIVITY REPORT  (for Lattice Power Calculator)");
        $display("  VCD window: %0d cpu_clk cycles total",  cpu_cycle_count_all);
        $display("    5-stage: %0d cycles @ %.1f MHz",      cpu_cycle_count_5s, CPU_CLK_5S_MHZ);
        $display("    3-stage: %0d cycles @ %.3f MHz",      cpu_cycle_count_3s, CPU_CLK_3S_MHZ);
        $display("  NOTE: set AF%% manually in Power Calculator; behavioural VCD");
        $display("        signal names do not match post-synthesis primitives.");
        $display("----------------------------------------------------------------");
        $display("  PASS 1 (5-STAGE @ %.1f MHz)  |  %-10s | AF (%%)", CPU_CLK_5S_MHZ, "Toggles");
        $display("  %-35s | %-10s | ------", "-----------------------------------", "----------");
        if (cpu_cycle_count_5s > 0) begin
            $display("  %-35s | %-10d | %0.1f", "if_pc [31:0]",
                tgl5_if_pc,    100.0*$itor(tgl5_if_pc)   /($itor(cpu_cycle_count_5s)*2.0));
            $display("  %-35s | %-10d | %0.1f", "id_instr [31:0]",
                tgl5_id_instr, 100.0*$itor(tgl5_id_instr)/($itor(cpu_cycle_count_5s)*2.0));
            $display("  %-35s | %-10d | %0.1f", "ex_alu_a [31:0]",
                tgl5_ex_alu_a, 100.0*$itor(tgl5_ex_alu_a)/($itor(cpu_cycle_count_5s)*2.0));
            $display("  %-35s | %-10d | %0.1f", "ex_alu_b [31:0]",
                tgl5_ex_alu_b, 100.0*$itor(tgl5_ex_alu_b)/($itor(cpu_cycle_count_5s)*2.0));
            $display("  %-35s | %-10d | %0.1f", "ex_alu_res [31:0]",
                tgl5_alu_res,  100.0*$itor(tgl5_alu_res) /($itor(cpu_cycle_count_5s)*2.0));
            $display("  %-35s | %-10d | %0.1f", "ex_rs1_forwarded [31:0]",
                tgl5_rs1_fwd,  100.0*$itor(tgl5_rs1_fwd) /($itor(cpu_cycle_count_5s)*2.0));
            $display("  %-35s | %-10d | %0.1f", "ex_rs2_forwarded [31:0]",
                tgl5_rs2_fwd,  100.0*$itor(tgl5_rs2_fwd) /($itor(cpu_cycle_count_5s)*2.0));
            $display("  %-35s | %-10d | %0.1f", "mem_alu_res [31:0]",
                tgl5_mem_alur, 100.0*$itor(tgl5_mem_alur)/($itor(cpu_cycle_count_5s)*2.0));
            $display("  %-35s | %-10d | %0.1f", "wb_forward_data [31:0]",
                tgl5_wb_fwd,   100.0*$itor(tgl5_wb_fwd)  /($itor(cpu_cycle_count_5s)*2.0));
            $display("  %-35s | %-10d | (1-bit)", "stall",     tgl5_stall);
            $display("  %-35s | %-10d | (1-bit)", "flush",     tgl5_flush);
            $display("  %-35s | %-10d | (2-bit)", "forward_a", tgl5_fwd_a);
            $display("  %-35s | %-10d | (2-bit)", "forward_b", tgl5_fwd_b);
        end else
            $display("  (no 5-stage cycles captured -- check VCD open timing)");

        $display("----------------------------------------------------------------");
        $display("  PASS 2 (3-STAGE @ %.3f MHz)  |  %-10s | AF (%%)", CPU_CLK_3S_MHZ, "Toggles");
        $display("  %-35s | %-10s | ------", "-----------------------------------", "----------");
        if (cpu_cycle_count_3s > 0) begin
            $display("  %-35s | %-10d | %0.1f", "if_pc [31:0]",
                tgl3_if_pc,    100.0*$itor(tgl3_if_pc)   /($itor(cpu_cycle_count_3s)*2.0));
            $display("  %-35s | %-10d | %0.1f", "id_instr [31:0]",
                tgl3_id_instr, 100.0*$itor(tgl3_id_instr)/($itor(cpu_cycle_count_3s)*2.0));
            $display("  %-35s | %-10d | %0.1f", "ex_alu_a [31:0]",
                tgl3_ex_alu_a, 100.0*$itor(tgl3_ex_alu_a)/($itor(cpu_cycle_count_3s)*2.0));
            $display("  %-35s | %-10d | %0.1f", "ex_alu_b [31:0]",
                tgl3_ex_alu_b, 100.0*$itor(tgl3_ex_alu_b)/($itor(cpu_cycle_count_3s)*2.0));
            $display("  %-35s | %-10d | %0.1f", "ex_alu_res [31:0]",
                tgl3_alu_res,  100.0*$itor(tgl3_alu_res) /($itor(cpu_cycle_count_3s)*2.0));
            $display("  %-35s | %-10d | %0.1f", "ex_rs1_forwarded [31:0]",
                tgl3_rs1_fwd,  100.0*$itor(tgl3_rs1_fwd) /($itor(cpu_cycle_count_3s)*2.0));
            $display("  %-35s | %-10d | %0.1f", "ex_rs2_forwarded [31:0]",
                tgl3_rs2_fwd,  100.0*$itor(tgl3_rs2_fwd) /($itor(cpu_cycle_count_3s)*2.0));
            $display("  %-35s | %-10d | %0.1f", "ex_alu_res_q (3s barrier)[31:0]",
                tgl3_q_alures, 100.0*$itor(tgl3_q_alures)/($itor(cpu_cycle_count_3s)*2.0));
            $display("  %-35s | %-10d | %0.1f", "final_reg_write_data [31:0]",
                tgl3_final,    100.0*$itor(tgl3_final)   /($itor(cpu_cycle_count_3s)*2.0));
            $display("  %-35s | %-10d | (1-bit)", "stall",       tgl3_stall);
            $display("  %-35s | %-10d | (1-bit)", "flush",       tgl3_flush);
            $display("  %-35s | %-10d | (2-bit)", "forward_a",   tgl3_fwd_a);
            $display("  %-35s | %-10d | (2-bit)", "forward_b",   tgl3_fwd_b);
            $display("  %-35s | %-10d | (3-bit)", "ex_funct3_q", tgl3_q_funct3);
        end else
            $display("  (no 3-stage cycles captured -- mode switch may not have fired)");

        $display("----------------------------------------------------------------");
        $display("  >> Use AF%% above for manual override in Power Calculator.");
        $display("  >> 5-stage typically shows HIGHER AF due to extra pipeline");
        $display("     register toggling (EX/MEM + MEM/WB) vs 3-stage _q path.");
        $display("================================================================");

        // -- 12. THESIS INSIGHT -----------------------------------------------
        $display("");
        $display("  THESIS KEY INSIGHT:");
        $display("  Ph4 Branch: 5-stage %.2f MIPS vs 3-stage %.2f MIPS",
                 mips_5s[3], mips_3s[3]);
        $display("  3-stage is %.1f%% lower MIPS for branch workload.",
                 (mips_5s[3] > 0) ? 100.0*(mips_5s[3]-mips_3s[3])/mips_5s[3] : 0.0);
        $display("  But 3-stage runs at %.3f MHz -> lower P_dyn -> better energy/op",
                 CPU_CLK_3S_MHZ);
        $display("  for branch-heavy, power-sensitive workloads.");

        // -- 13. SUMMARY ------------------------------------------------------
        $display("");
        $display("================================================================");
        $display("  %0d PASSED   %0d FAILED  (8 phases total, 4 per mode)",
                 pass_count, fail_count);
        if (fail_count == 0)
            $display("  ALL WITHIN TOLERANCE -- OK");
        else begin
            $display("  FAILURES -- diagnosis hints:");
            $display("  * 5s negative values  : CSR timing NOP missing");
            $display("  * 3s all zero         : mode-switch CSR write failed");
            $display("  * 3s negative values  : NOP missing after mode switch");
            $display("  * CPI=1.000 all phases: branch flush not firing");
            $display("  * Ph3 stalls=0        : load-use hazard unit issue");
            $display("  * Ph1 dev >> 10       : check mcycle CSR reset at bench start");
        end
        $display("================================================================");
        $display("  VCD : power_ad_full_v3.vcd");
        $display("        ~135 explicit signals -- memory arrays excluded.");
        $display("        Import into Lattice Power Calculator for P_dyn.");
        $display("================================================================");
        $display("");

        $finish;
    end

    // =========================================================================
    // TIMEOUT WATCHDOG
    // Counts clk_in cycles from time=0.
    // FIX-1: raised to 80_000_000 to cover PLL lock + both benchmark passes.
    // =========================================================================
    initial begin
        repeat (TIMEOUT_CYCLES) @(posedge clk_in);
        $display("[TIMEOUT] %0d clk_in cycles (%.0f ms) -- benchmark did not complete.",
                 TIMEOUT_CYCLES, TIMEOUT_CYCLES * CLK_IN_HALF_NS * 2.0 / 1000.0);
        $display("  Time of timeout: %0t ns", $time);
        $display("  PC              = 0x%h", if_pc);
        $display("  ID instr        = 0x%h", id_instr);
        $display("  pipeline_mode   = %0d (1=5-stage, 0=3-stage)", h_pipeline);
        $display("  clk_sel         = %0d", h_clk_sel);
        $display("  pll_lock        = %0d", pll_lock);
        $display("  mcycle          = %0d", h_mcycle);
        $display("  done_flag       = 0x%h  (need 0xFF)", ram_done);
        $display("  stall_count     = %0d", stall_count);
        $display("  flush_count     = %0d", flush_count);
        $display("  fsm_count       = %0d  (0 = mode switch never fired)", fsm_count);
        $display("  5s: a0=%0d  a1=%0d  a2=%0d  a3=%0d",
                 reg_a0, reg_a1, reg_a2, reg_a3);
        $display("  3s: a4=%0d  a5=%0d  a6=%0d  a7=%0d",
                 reg_a4, reg_a5, reg_a6, reg_a7);
        $display("  --- Diagnosis guide ---");
        $display("  pll_lock=0 : PLL model not locking; check pll_clock.v or");
        $display("               increase TIMEOUT_CYCLES further.");
        $display("  done=0x00  : No phases completed; check $readmemh path,");
        $display("               ROM address mapping, or crt0.s entry point.");
        $display("  done=0x0F  : 5-stage done; 3-stage stuck -- check csrw");
        $display("               0x800 decoding in control_unit.v + csr_unit.v.");
        $display("  stall=0    : load-use hazard unit not firing (Phase 3 issue).");
        $display("  flush >> exp: CPU stuck in tight branch loop (check imm_gen.v");
        $display("               B-type immediate or branch_comp.v comparison).");
        $display("  a3=0x9000..: peripheral address in result reg -- benchmark");
        $display("               loop exited early; check loop counter init.");
        $dumpoff;
        $dumpflush;
        $finish;
    end

endmodule