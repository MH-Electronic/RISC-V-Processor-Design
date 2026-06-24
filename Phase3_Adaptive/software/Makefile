# =============================================================================
# Makefile  --  Hardwired RISC-V Build System ("Bake and Flash")
# =============================================================================

CC      := riscv64-unknown-elf-gcc
OBJCOPY := riscv64-unknown-elf-objcopy
OBJDUMP := riscv64-unknown-elf-objdump
SIZE    := riscv64-unknown-elf-size
PYTHON  := python3

ARCH_FLAGS := -march=rv32i_zicsr -mabi=ilp32 \
              -nostartfiles -nostdlib -ffreestanding -fno-builtin -O0 -g

BUILD_DIR := build
SW_DIR    := software

# -----------------------------------------------------------------------
# Target Source File
# By default, compiles 'main.c'. 
# You can override this: make SRC="software/led_sweep.c"
# -----------------------------------------------------------------------
SRC ?= $(SW_DIR)/main.c

SRCS      := $(SW_DIR)/crt0.s $(SRC)
LD_SCRIPT := $(SW_DIR)/link.ld

ELF := $(BUILD_DIR)/firmware.elf
BIN := $(BUILD_DIR)/firmware.bin
MEM := instr.mem

# -----------------------------------------------------------------------
# Build Rules
# -----------------------------------------------------------------------
.PHONY: all clean disasm

all: $(MEM)

$(BUILD_DIR):
	mkdir -p $@

$(ELF): $(SRCS) $(LD_SCRIPT) | $(BUILD_DIR)
	@echo "Compiling $(SRC)..."
	$(CC) $(ARCH_FLAGS) -T $(LD_SCRIPT) $(SRCS) -o $@
	@$(SIZE) $@

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(MEM): $(BIN)
	@echo "Generating readmemh hex -> $(MEM)"
	@$(PYTHON) -c "import struct; data = open('$<', 'rb').read(); data += b'\x00' * ((-len(data)) % 4); words = [struct.unpack('<I', data[i:i+4])[0] for i in range(0, len(data), 4)]; open('$(MEM)', 'w').write('\n'.join(f'{w:08x}' for w in words) + '\n')"
	@echo "Done! Copy $(MEM) to your Radiant project directory."

disasm: $(ELF)
	$(OBJDUMP) -d -S $<

clean:
	rm -rf $(BUILD_DIR) $(MEM)
	@echo "Cleaned build/ and instr.mem"