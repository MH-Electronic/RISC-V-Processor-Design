# Adaptive RISC-V (RV32I) Processor Core

## Project Overview
This repository contains the design, implementation, and verification of a custom RV32I RISC-V processor. Developed entirely in Verilog, the project traces the evolution of a processor core from a fundamental single-cycle architecture into a dynamically scalable, adaptive pipeline capable of switching depths to optimize the Power-Delay Product (PDP).

The project is structured into three distinct phases, demonstrating a progression from baseline functionality to advanced microarchitectural optimization for power-constrained Artificial Intelligence of Things (AIoT) applications.

## Key Features
* **Full RV32I Base Integer Instruction Set:** Support for all 47 standard unprivileged integer instructions.
* **Progressive Pipeline Implementation:** From 1-stage to a classic 5-stage architecture.
* **Hazard Management:** Full operand forwarding, data hazard mitigation, and branch prediction mechanisms.
* **Pipeline Stage Unification (PSU):** A novel adaptive architecture that dynamically merges pipeline stages (e.g., 5-stage to 3-stage) via multiplexer-based bypassing to eliminate redundant register clocking during low-intensity workloads.
* **Bare-Metal Software Support:** Includes a custom C/Assembly software toolchain with examples to compile and execute raw hex memory files on the processor.

---

## Repository Structure

The project is organized sequentially to highlight the architectural progression:

```text
RISC-V_Adaptive_Core/
│
├── Phase1_Single_Cycle/       # Baseline non-pipelined RV32I core
│   ├── rtl/                   # Synthesizable Verilog modules (ALU, PC, Control, etc.)
│   └── tb/                    # Testbenches and basic power profiling benchmarks
│
├── Phase2_5_Stage/            # Classic 5-stage pipelined architecture
│   ├── rtl/                   # Pipelined datapath with IF/ID, ID/EX, EX/MEM, MEM/WB registers
│   └── tb/                    # Testbenches validating hazard mitigation and forwarding
│
└── Phase3_Adaptive/           # The flagship dynamically scalable pipeline
    ├── rtl/                   # Adaptive datapath, bypass multiplexers, and PMU
    ├── tb/                    # Verification for runtime depth transitions
    └── sw/                    # Software stack for the core
        ├── Makefile           # Build system for C/Assembly -> Hex
        ├── crt0.s             # C runtime initialization / Boot code
        ├── main.c             # Primary execution program
        ├── link.ld            # Linker script defining memory boundaries
        └── examples/          # Sample programs (LED blink, benchmarks)
