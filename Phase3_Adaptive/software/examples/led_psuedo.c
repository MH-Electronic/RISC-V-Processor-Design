#pragma GCC optimize ("O2") // Force compiler to use registers, bypassing the stack
#include "defines.h"

// ---------------------------------------------------------
// Macro Delay Loop (100% Inline, NO Function Call)
// ---------------------------------------------------------
#define DELAY_LOOP() __asm__ volatile ( \
    "csrr t1, 0x800 \n" \
    "andi t1, t1, 1 \n" \
    "beqz t1, 1f \n" \
    "li t1, 4000000 \n" \
    "j 2f \n" \
    "1: \n" \
    "li t1, 3000000 \n" \
    "2: \n" \
    "addi t1, t1, -1 \n" \
    "bnez t1, 2b \n" \
    : : : "t1" \
)

// ---------------------------------------------------------
// Pseudo-Random LED Generator
// ---------------------------------------------------------
int main(void) {
    // FORCE 3-STAGE MODE (25 MHz) FOR MAXIMUM STABILITY
    __asm__ volatile ("csrw 0x800, zero");

    // Explicitly bind the PRNG state to hardware register 't2' (x7).
    // This mathematically guarantees zero stack spills (SW/LW).
    register unsigned int prng_state __asm__("t2") = 0x87654321; 

    while (1) {
        // Xorshift32 Algorithm (Operates entirely within t2)
        prng_state ^= prng_state << 13;
        prng_state ^= prng_state >> 17;
        prng_state ^= prng_state << 5;

        // Mask the lower 8 bits and write to LEDs
        WRITE_REG(GPIO_DATA_REG, prng_state & 0xFF);
        
        DELAY_LOOP();
    }
    
    return 0; 
}