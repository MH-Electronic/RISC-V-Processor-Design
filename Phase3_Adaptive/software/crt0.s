# =============================================================================
# crt0.s  --  Minimal RISC-V startup for bare-metal LED blink
#
# Fixes vs previous version:
#   1. la gp, __global_pointer$ now expands to auipc gp/addi gp (same reg,
#      no two-register scratch hazard). NOP moved OUTSIDE .option norelax.
#   2. Stack pointer now loads __stack_top = 0x80011000 directly via lui.
#      This matches the physical 4KB Block RAM synthesized on the FPGA,
#      preventing the bus lockup caused by writing to non-existent memory.
#   3. Two NOPs after the la t0/__bss_start + la t1/__bss_end pair ensure
#      both registers are stable in the 3-stage pipeline before bge reads them.
#   4. "call main" (auipc ra + jalr ra) is kept -- correct, link reg = ra(x1).
#   5. mtvec pointed at hang early so any fault parks the PC visibly.
# =============================================================================

    .section .text.init
    .global  _start

_start:
    # ------------------------------------------------------------------
    # 1. Global pointer -- must be the very first thing.
    #    .option norelax stops the linker from converting the auipc+addi
    #    pair into a single GP-relative instruction (which would be
    #    circular -- GP is not valid yet).
    #    "la gp, sym" with norelax expands to:
    #        auipc gp, %pcrel_hi(sym)
    #        addi  gp, gp, %pcrel_lo(sym)
    #    Both instructions write gp directly -- no scratch register, no
    #    forwarding hazard between the two halves.
    # ------------------------------------------------------------------
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop
    nop                         # pipeline bubble: let addi gp settle before
                                # anything GP-relative is decoded

    # ------------------------------------------------------------------
    # 2. Point mtvec at the hang loop immediately so any fault is
    #    visible in simulation as a stuck PC rather than a jump to 0x0.
    # ------------------------------------------------------------------
    la      t0, hang
    csrw    mtvec, t0

    # ------------------------------------------------------------------
    # 3. Stack pointer -- load top of 4KB RAM exactly.
    #    lui sp, 0x80011  =>  sp = 0x80011000
    #    This is the top of the 4 KB data RAM (0x80010000 + 0x1000).
    #    The stack grows downward into physical Block RAM space.
    # ------------------------------------------------------------------
    lui     sp, 0x80011         # sp = 0x80011000  (__stack_top)

    # ------------------------------------------------------------------
    # 4. Zero the .bss section so C globals start at 0.
    #    Two NOPs after loading t0/t1 give the 3-stage pipeline time to
    #    commit both la results before bge reads them.
    # ------------------------------------------------------------------
    la      t0, __bss_start
    la      t1, __bss_end
    nop                         # let t0 (written by addi at +0x28) settle
    nop                         # let t1 (written by addi at +0x30) settle

bss_loop:
    bge     t0, t1, bss_done   # if t0 >= t1, BSS is zeroed
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       bss_loop
bss_done:

    # ------------------------------------------------------------------
    # 5. Call main.
    #    "call main" expands to:
    #        auipc ra, %pcrel_hi(main)
    #        jalr  ra, ra, %pcrel_lo(main)
    #    rd = ra (x1) in both instructions.  The forwarding unit handles
    #    the one-cycle RAW between auipc writing ra and jalr reading it.
    # ------------------------------------------------------------------
    call    main

    # ------------------------------------------------------------------
    # 6. If main ever returns, fall into the hang loop.
    # ------------------------------------------------------------------
hang:
    j       hang