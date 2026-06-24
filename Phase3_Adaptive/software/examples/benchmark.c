/*
 * main.c  —  4-Phase Power & Performance Benchmark  (Adaptive 3/5-Stage Core)
 * =============================================================================
 * EEE499 FYP  |  Liew Ming Heng (161439)  |  USM
 *
 * -----------------------------------------------------------------------
 * WHAT WAS WRONG IN THE PREVIOUS VERSION (doc6)
 * -----------------------------------------------------------------------
 *   FAIL 1: Only one pass (5-stage only).  Testbench reads a4-a7 and
 *           RAM[12-15] for the 3-stage results — these were never written.
 *   FAIL 2: done_flag reached only 0x0F.  Testbench completion requires
 *           0xFF (8 phases across two passes).
 *   FAIL 3: Tohost address was 0x800FFF00.  Testbench and system_top.v
 *           (after the doc-4 fix) both check 0x803FFF00.  Wrong address
 *           means the simulation hangs at the tohost wait forever.
 *
 * -----------------------------------------------------------------------
 * WHAT THIS FILE DOES
 * -----------------------------------------------------------------------
 *   Pass 1 — 5-stage mode  (default on cold reset: mconfig[0]=1)
 *     Runs phases 1-4, stores delta_cycles in a0-a3 and RAM[0-3].
 *     done_flag accumulates: 0x01 → 0x03 → 0x07 → 0x0F
 *
 *   Mode switch
 *     csrw 0x800, x0  writes mconfig[0]=0 (3-stage, clk_slow).
 *     The riscv_top FSM flushes the pipeline, switches the glitch-free
 *     mux to clk_slow, and settles for ~18 cycles — transparent to
 *     firmware.
 *
 *   Pass 2 — 3-stage mode  (pipeline_mode=0, clk_slow ~25 MHz)
 *     Identical loop bodies to Pass 1.
 *     Stores delta_cycles in a4-a7 and RAM[12-15] (byte offset 0x30).
 *     done_flag accumulates: 0x1F → 0x3F → 0x7F → 0xFF
 *
 *   Completion
 *     (A) done_flag = 0xFF at RAM[16] = 0x80010040
 *     (B) SW to tohost address 0x803FFF00 → testbench tohost_write fires
 *
 * -----------------------------------------------------------------------
 * REGISTER MAP
 * -----------------------------------------------------------------------
 *   s0  RAM_BASE    = 0x80010000  (5-stage results)
 *   s1  SCRATCH     = 0x80010010  (Phase 2 write / Phase 3 read, both passes)
 *   s2  mcycle snapshot — phase START
 *   s3  mcycle snapshot — phase END
 *   s4  done-flag accumulator (0x00 → 0x0F → 0xFF)
 *   s5  loop counter
 *   s6  RAM_3S_BASE = 0x80010030  (3-stage results, words 12-15)
 *   t0–t6  workload / scratch
 *   a0  5-stage Phase 1 delta_cycles → RAM[0]  / reg x10
 *   a1  5-stage Phase 2 delta_cycles → RAM[1]  / reg x11
 *   a2  5-stage Phase 3 delta_cycles → RAM[2]  / reg x12
 *   a3  5-stage Phase 4 delta_cycles → RAM[3]  / reg x13
 *   a4  3-stage Phase 1 delta_cycles → RAM[12] / reg x14
 *   a5  3-stage Phase 2 delta_cycles → RAM[13] / reg x15
 *   a6  3-stage Phase 3 delta_cycles → RAM[14] / reg x16
 *   a7  3-stage Phase 4 delta_cycles → RAM[15] / reg x17
 *
 * -----------------------------------------------------------------------
 * MEMORY MAP  (data RAM, base 0x80010000)
 * -----------------------------------------------------------------------
 *   Word  Byte addr     Contents
 *   [0]   0x80010000    5-stage Ph1 delta_cycles  (a0)
 *   [1]   0x80010004    5-stage Ph2 delta_cycles  (a1)
 *   [2]   0x80010008    5-stage Ph3 delta_cycles  (a2)
 *   [3]   0x8001000C    5-stage Ph4 delta_cycles  (a3)
 *   [4-11]0x80010010    SCRATCH 8 words (Ph2 store / Ph3 load, both passes)
 *   [12]  0x80010030    3-stage Ph1 delta_cycles  (a4)
 *   [13]  0x80010034    3-stage Ph2 delta_cycles  (a5)
 *   [14]  0x80010038    3-stage Ph3 delta_cycles  (a6)
 *   [15]  0x8001003C    3-stage Ph4 delta_cycles  (a7)
 *   [16]  0x80010040    done_flag:
 *                         0x01 5s-Ph1, 0x03 5s-Ph2, 0x07 5s-Ph3, 0x0F 5s-Ph4
 *                         0x1F 3s-Ph1, 0x3F 3s-Ph2, 0x7F 3s-Ph3, 0xFF 3s-Ph4
 *
 * -----------------------------------------------------------------------
 * EXPECTED CYCLE COUNTS  (5-stage and 3-stage passes)
 * -----------------------------------------------------------------------
 *   5-stage (pipeline_mode=1, clk_fast ~50 MHz):
 *     Ph1 ALU:    140000 + 4 init + 19998 (9999x2 BNEZ flush) = 160002
 *     Ph2 Store:  100000 + 1 init + 19998                     = 119999
 *     Ph3 Load:   100000 + 2 init + 40000 (load-use) + 19998  = 160000
 *     Ph4 Branch:  60000 + 4 init + 9998 (BLT) + 19998 (BNEZ) = 90000
 *
 *   3-stage (pipeline_mode=0, clk_slow ~25 MHz):
 *     Branch flush and load-use stall logic unchanged in adaptive RTL.
 *     Cycle COUNTS identical to 5-stage pass.
 *     MIPS lower because 25 MHz / CPI < 50 MHz / CPI.
 *     Power lower because lower frequency + fewer toggling pipeline FFs.
 *
 * -----------------------------------------------------------------------
 * CSR FORWARDING BARRIER (nop after csrr)
 * -----------------------------------------------------------------------
 *   csrr s3, 0xB00  produces: alu_res=0 (x0+0), csr_rdata=mcycle.
 *   The mcycle value travels: ex_csr_rdata → mem_csr_rdata → wb_csr_rdata.
 *   With no nop: SUB in the next cycle catches forward_a=2'b10 from MEM
 *   stage, which gives mem_alu_res=0 instead of the CSR value → delta=0.
 *   With one nop: SUB gets forward_a=2'b01 from WB stage, which gives
 *   wb_csr_rdata=mcycle → correct delta.
 */

#include "defines.h"

__attribute__((naked, noreturn))
int main(void)
{
    __asm__ volatile (

    /* ==================================================================
     * GLOBAL INIT
     * ================================================================== */
        "lui   s0, 0x80010      \n"   /* s0 = 0x80010000  (RAM_BASE)        */
        "addi  s1, s0, 16       \n"   /* s1 = 0x80010010  (SCRATCH)         */
        "li    s4, 0            \n"   /* s4 = 0x00  done-flag accumulator   */

    /* ==================================================================
     * =====================  5-STAGE PASS  =============================
     * Default startup: mconfig[0]=1 (5-stage, clk_fast).
     * No explicit csrw needed — mconfig already 1 on cold reset.
     * ================================================================== */

    /* ------------------------------------------------------------------
     * 5-STAGE PHASE 1  —  ALU-HEAVY
     * 14 instr/iter × 10000 iter = 140000 + 4 init + 19998 BNEZ flush
     * Expected: 160002 cycles
     * ------------------------------------------------------------------ */
        "csrr  s2, 0xB00        \n"   /* s2 = mcycle_start  5s-Ph1          */
        "li    t1, 1            \n"   /* Fibonacci a = 1                    */
        "li    t2, 1            \n"   /* Fibonacci b = 1                    */
        "li    t3, 0            \n"   /* accumulator = 0                    */
        "li    s5, 10000        \n"   /* loop counter                       */
        "ph1s_loop:             \n"
        "add   t4, t1, t2       \n"   /* [1]  c = a+b                       */
        "mv    t1, t2           \n"   /* [2]  a = b                         */
        "mv    t2, t4           \n"   /* [3]  b = c                         */
        "xor   t3, t3, t4       \n"   /* [4]  acc ^= c                      */
        "slli  t5, t4, 2        \n"   /* [5]  t5 = c<<2                     */
        "add   t3, t3, t5       \n"   /* [6]  acc += t5                     */
        "srli  t5, t4, 3        \n"   /* [7]  t5 = c>>3                     */
        "or    t3, t3, t5       \n"   /* [8]  acc |= t5                     */
        "and   t5, t1, t2       \n"   /* [9]  t5 = a&b                      */
        "sub   t3, t3, t5       \n"   /* [10] acc -= t5                     */
        "andi  t1, t1, 0xFF     \n"   /* [11] a &= 0xFF                     */
        "andi  t2, t2, 0xFF     \n"   /* [12] b &= 0xFF                     */
        "addi  s5, s5, -1       \n"   /* [13] counter--                     */
        "bnez  s5, ph1s_loop    \n"   /* [14] taken 9999x                   */
        "csrr  s3, 0xB00        \n"   /* s3 = mcycle_end  5s-Ph1            */
        "nop                    \n"   /* CSR forwarding barrier             */
        "sub   a0, s3, s2       \n"   /* a0 = 5s-Ph1 delta_cycles           */
        "sw    a0,  0(s0)       \n"   /* RAM[0x80010000] = a0               */
        "ori   s4, s4, 0x01     \n"
        "sw    s4, 0x40(s0)     \n"   /* done_flag = 0x01                   */

    /* ------------------------------------------------------------------
     * 5-STAGE PHASE 2  —  STORE-HEAVY
     * 10 instr/iter × 10000 iter = 100000 + 1 init + 19998 BNEZ flush
     * Expected: 119999 cycles
     * ------------------------------------------------------------------ */
        "csrr  s2, 0xB00        \n"   /* s2 = mcycle_start  5s-Ph2          */
        "li    s5, 10000        \n"
        "ph2s_loop:             \n"
        "sw    t0,  0(s1)       \n"   /* [1]                                */
        "sw    t1,  4(s1)       \n"   /* [2]                                */
        "sw    t2,  8(s1)       \n"   /* [3]                                */
        "sw    t3, 12(s1)       \n"   /* [4]                                */
        "sw    t4, 16(s1)       \n"   /* [5]                                */
        "sw    t5, 20(s1)       \n"   /* [6]                                */
        "sw    t0, 24(s1)       \n"   /* [7]                                */
        "sw    t1, 28(s1)       \n"   /* [8]                                */
        "addi  s5, s5, -1       \n"   /* [9]  counter--                     */
        "bnez  s5, ph2s_loop    \n"   /* [10] taken 9999x                   */
        "csrr  s3, 0xB00        \n"
        "nop                    \n"
        "sub   a1, s3, s2       \n"   /* a1 = 5s-Ph2 delta_cycles           */
        "sw    a1,  4(s0)       \n"   /* RAM[0x80010004] = a1               */
        "ori   s4, s4, 0x02     \n"
        "sw    s4, 0x40(s0)     \n"   /* done_flag = 0x03                   */

    /* ------------------------------------------------------------------
     * 5-STAGE PHASE 3  —  LOAD-HEAVY
     * 10 instr/iter × 10000 iter = 100000 + 2 init + 40000 LU + 19998 flush
     * Expected: 160000 cycles
     * ------------------------------------------------------------------ */
        "csrr  s2, 0xB00        \n"
        "li    t3, 0            \n"
        "li    s5, 10000        \n"
        "ph3s_loop:             \n"
        "lw    t0,  0(s1)       \n"   /* [1]  LW -> ADD: load-use stall     */
        "add   t3, t0, t3       \n"   /* [2]                                */
        "lw    t1,  4(s1)       \n"   /* [3]  LW -> ADD: load-use stall     */
        "add   t3, t1, t3       \n"   /* [4]                                */
        "lw    t2,  8(s1)       \n"   /* [5]  LW -> XOR: load-use stall     */
        "xor   t3, t2, t3       \n"   /* [6]                                */
        "lw    t4, 12(s1)       \n"   /* [7]  LW -> OR:  load-use stall     */
        "or    t3, t4, t3       \n"   /* [8]                                */
        "addi  s5, s5, -1       \n"   /* [9]  counter--                     */
        "bnez  s5, ph3s_loop    \n"   /* [10] taken 9999x                   */
        "csrr  s3, 0xB00        \n"
        "nop                    \n"
        "sub   a2, s3, s2       \n"   /* a2 = 5s-Ph3 delta_cycles           */
        "sw    a2,  8(s0)       \n"   /* RAM[0x80010008] = a2               */
        "ori   s4, s4, 0x04     \n"
        "sw    s4, 0x40(s0)     \n"   /* done_flag = 0x07                   */

    /* ------------------------------------------------------------------
     * 5-STAGE PHASE 4  —  BRANCH-HEAVY
     * 6 instr/iter × 10000 iter = 60000 + 4 init + 9998 BLT + 19998 BNEZ
     * Expected: 90000 cycles
     * ------------------------------------------------------------------ */
        "csrr  s2, 0xB00        \n"
        "li    t0, 0            \n"
        "li    t1, 10000        \n"
        "li    t3, 0            \n"
        "li    s5, 10000        \n"
        "ph4s_loop:             \n"
        "addi  t0, t0,  1       \n"   /* [1]  up++                          */
        "addi  t1, t1, -1       \n"   /* [2]  down--                        */
        "blt   t0, t1, ph4s_sk  \n"   /* [3]  taken 4999x                   */
        "ph4s_sk:               \n"
        "xori  t3, t3, 0xFF     \n"   /* [4]  toggle                        */
        "addi  s5, s5, -1       \n"   /* [5]  outer--                       */
        "bnez  s5, ph4s_loop    \n"   /* [6]  taken 9999x                   */
        "csrr  s3, 0xB00        \n"
        "nop                    \n"
        "sub   a3, s3, s2       \n"   /* a3 = 5s-Ph4 delta_cycles           */
        "sw    a3, 12(s0)       \n"   /* RAM[0x8001000C] = a3               */
        "ori   s4, s4, 0x08     \n"
        "sw    s4, 0x40(s0)     \n"   /* done_flag = 0x0F  (5-stage DONE)   */

    /* ==================================================================
     * MODE SWITCH: 5-STAGE -> 3-STAGE
     * ------------------------------------------------------------------
     * csrw 0x800, x0 writes mconfig[0]=0 (pipeline_mode=0 = 3-stage).
     * FSM: ST_RUNNING -> ST_FLUSH_PIPE -> ST_SWITCH_CLK -> ST_SETTLE_DLY
     *      -> ST_RUNNING  (~18 stall cycles, transparent to firmware).
     * Execution resumes at clk_slow after ST_RUNNING re-entered.
     * mcycle keeps incrementing during settle — not inside any phase
     * measurement window so settle cycles do not corrupt deltas.
     * ================================================================== */
        "li    t0, 0            \n"   /* t0 = 0  (3-stage mode value)       */
        "csrw  0x800, t0        \n"   /* mconfig[0]=0 -> 3-stage, FSM runs  */
        /* ~18 stall cycles here (master_stall=1, transparent)              */

        /* 3-stage result base: s6 = 0x80010030 (word 12, byte offset 0x30) */
        "lui   s6, 0x80010      \n"
        "addi  s6, s6, 0x30     \n"   /* s6 = 0x80010030                    */

    /* ==================================================================
     * =====================  3-STAGE PASS  =============================
     * Now at clk_slow (~25 MHz), pipeline_mode=0.
     * Loop bodies IDENTICAL to 5-stage pass.
     * Cycle counts expected SAME (same hazard/flush logic in adaptive RTL).
     * MIPS lower: 25 MHz / CPI  vs  50 MHz / CPI.
     * Power lower: lower frequency + fewer toggling pipeline FFs.
     * ================================================================== */

    /* ------------------------------------------------------------------
     * 3-STAGE PHASE 1  —  ALU-HEAVY
     * Expected: same ~160002 cycles at 25 MHz
     * ------------------------------------------------------------------ */
        "csrr  s2, 0xB00        \n"   /* s2 = mcycle_start  3s-Ph1          */
        "li    t1, 1            \n"
        "li    t2, 1            \n"
        "li    t3, 0            \n"
        "li    s5, 10000        \n"
        "ph1t_loop:             \n"   /* different label to avoid collision  */
        "add   t4, t1, t2       \n"
        "mv    t1, t2           \n"
        "mv    t2, t4           \n"
        "xor   t3, t3, t4       \n"
        "slli  t5, t4, 2        \n"
        "add   t3, t3, t5       \n"
        "srli  t5, t4, 3        \n"
        "or    t3, t3, t5       \n"
        "and   t5, t1, t2       \n"
        "sub   t3, t3, t5       \n"
        "andi  t1, t1, 0xFF     \n"
        "andi  t2, t2, 0xFF     \n"
        "addi  s5, s5, -1       \n"
        "bnez  s5, ph1t_loop    \n"
        "csrr  s3, 0xB00        \n"
        "nop                    \n"
        "sub   a4, s3, s2       \n"   /* a4 = 3s-Ph1 delta_cycles  (x14)    */
        "sw    a4,  0(s6)       \n"   /* RAM[0x80010030] = a4               */
        "ori   s4, s4, 0x10     \n"
        "sw    s4, 0x40(s0)     \n"   /* done_flag = 0x1F                   */

    /* ------------------------------------------------------------------
     * 3-STAGE PHASE 2  —  STORE-HEAVY
     * Expected: same ~119999 cycles at 25 MHz
     * ------------------------------------------------------------------ */
        "csrr  s2, 0xB00        \n"
        "li    s5, 10000        \n"
        "ph2t_loop:             \n"
        "sw    t0,  0(s1)       \n"
        "sw    t1,  4(s1)       \n"
        "sw    t2,  8(s1)       \n"
        "sw    t3, 12(s1)       \n"
        "sw    t4, 16(s1)       \n"
        "sw    t5, 20(s1)       \n"
        "sw    t0, 24(s1)       \n"
        "sw    t1, 28(s1)       \n"
        "addi  s5, s5, -1       \n"
        "bnez  s5, ph2t_loop    \n"
        "csrr  s3, 0xB00        \n"
        "nop                    \n"
        "sub   a5, s3, s2       \n"   /* a5 = 3s-Ph2 delta_cycles  (x15)    */
        "sw    a5,  4(s6)       \n"   /* RAM[0x80010034] = a5               */
        "ori   s4, s4, 0x20     \n"
        "sw    s4, 0x40(s0)     \n"   /* done_flag = 0x3F                   */

    /* ------------------------------------------------------------------
     * 3-STAGE PHASE 3  —  LOAD-HEAVY
     * Reads SCRATCH written by 3-stage Phase 2 (same s1 address).
     * Expected: same ~160000 cycles at 25 MHz
     * ------------------------------------------------------------------ */
        "csrr  s2, 0xB00        \n"
        "li    t3, 0            \n"
        "li    s5, 10000        \n"
        "ph3t_loop:             \n"
        "lw    t0,  0(s1)       \n"
        "add   t3, t0, t3       \n"
        "lw    t1,  4(s1)       \n"
        "add   t3, t1, t3       \n"
        "lw    t2,  8(s1)       \n"
        "xor   t3, t2, t3       \n"
        "lw    t4, 12(s1)       \n"
        "or    t3, t4, t3       \n"
        "addi  s5, s5, -1       \n"
        "bnez  s5, ph3t_loop    \n"
        "csrr  s3, 0xB00        \n"
        "nop                    \n"
        "sub   a6, s3, s2       \n"   /* a6 = 3s-Ph3 delta_cycles  (x16)    */
        "sw    a6,  8(s6)       \n"   /* RAM[0x80010038] = a6               */
        "ori   s4, s4, 0x40     \n"
        "sw    s4, 0x40(s0)     \n"   /* done_flag = 0x7F                   */

    /* ------------------------------------------------------------------
     * 3-STAGE PHASE 4  —  BRANCH-HEAVY
     * Expected: same ~90000 cycles at 25 MHz
     * ------------------------------------------------------------------ */
        "csrr  s2, 0xB00        \n"
        "li    t0, 0            \n"
        "li    t1, 10000        \n"
        "li    t3, 0            \n"
        "li    s5, 10000        \n"
        "ph4t_loop:             \n"
        "addi  t0, t0,  1       \n"
        "addi  t1, t1, -1       \n"
        "blt   t0, t1, ph4t_sk  \n"
        "ph4t_sk:               \n"
        "xori  t3, t3, 0xFF     \n"
        "addi  s5, s5, -1       \n"
        "bnez  s5, ph4t_loop    \n"
        "csrr  s3, 0xB00        \n"
        "nop                    \n"
        "sub   a7, s3, s2       \n"   /* a7 = 3s-Ph4 delta_cycles  (x17)    */
        "sw    a7, 12(s6)       \n"   /* RAM[0x8001003C] = a7               */
        "ori   s4, s4, 0x80     \n"
        "sw    s4, 0x40(s0)     \n"   /* done_flag = 0xFF  (ALL DONE)       */

    /* ==================================================================
     * SIGNAL COMPLETION
     * ------------------------------------------------------------------
     * (A) done_flag = 0xFF already at RAM[0x80010040].
     *     Testbench polls: u_system.u_ram.mem[16] for 0xFF.
     *
     * (B) RISCOF tohost write -> asserts test_finished in system_top.v
     *     and fires tohost_write in the testbench.
     *     0x803FFF00 = lui 0x80400 (->0x80400000) + addi -256
     *
     *     NOTE: doc6 used 0x800FFF00 (WRONG).
     *     system_top.v (doc4 version) checks 0x803FFF00.
     *     Testbench checks h_addr == 32'h803F_FF00.
     *     Both require 0x803FFF00 — use that here.
     * ================================================================== */
        "lui   t0, 0x80400      \n"   /* t0 = 0x80400000                    */
        "addi  t0, t0, -256     \n"   /* t0 = 0x803FFF00  (tohost address)  */
        "li    t1, 1            \n"
        "sw    t1,  0(t0)       \n"   /* tohost=1 -> testbench detects      */

        "bench_end:             \n"
        "j     bench_end        \n"   /* spin forever                       */

        /* ----------------------------------------------------------------
         * Register clobbers
         * s0 (x8/fp) intentionally omitted: GCC rejects it as a clobber
         * even in naked functions. Safe here because naked+noreturn
         * suppresses the prologue/epilogue that would use fp.
         * ---------------------------------------------------------------- */
        :
        :
        : "t0","t1","t2","t3","t4","t5","t6",
          "s1","s2","s3","s4","s5","s6",
          "a0","a1","a2","a3","a4","a5","a6","a7",
          "memory"
    );
    __builtin_unreachable();
}