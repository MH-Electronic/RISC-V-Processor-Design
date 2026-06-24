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
// Knight-Rider Sweep Application
// ---------------------------------------------------------
int main(void) {
    // FORCE 3-STAGE MODE (25 MHz) FOR MAXIMUM STABILITY
    __asm__ volatile ("csrw 0x800, zero");

    // Explicitly bind variables to hardware registers 't2' and 't3'.
    // Eliminates the store-to-load data hazard entirely.
    register unsigned int led_mask      __asm__("t2") = 0x01; 
    register unsigned int sweeping_left __asm__("t3") = 1;         

    while (1) {
        WRITE_REG(GPIO_DATA_REG, led_mask);
        
        DELAY_LOOP();

        // Arithmetic operates exclusively in t2 and t3
        if (sweeping_left) {
            led_mask = led_mask << 1;
            if (led_mask >= 0x80) sweeping_left = 0; 
        } else {
            led_mask = led_mask >> 1;
            if (led_mask <= 0x01) sweeping_left = 1; 
        }
    }
    
    return 0; 
}