#include "defines.h"

// ---------------------------------------------------------
// Zero-Memory Assembly Delay Loop
// ---------------------------------------------------------
static void delay(void) {
    // This strictly uses the t1 register. No RAM is touched.
    __asm__ volatile (
        "csrr t1, 0x800 \n"        // Read pipeline mode
        "andi t1, t1, 1 \n"        // Check if 5-stage or 3-stage
        "beqz t1, 1f \n"           // If 0 (3-stage), jump to label 1
        "li t1, 6000000 \n"        // 5-stage count (Fast Clock)
        "j 2f \n"                  // Jump to countdown loop
        "1: \n"
        "li t1, 3000000 \n"        // 3-stage count (Slow Clock)
        "2: \n"
        "addi t1, t1, -1 \n"       // count--
        "bnez t1, 2b \n"           // Loop until zero
        :
        :
        : "t1"                     // Tell GCC we used the t1 register
    );
}

// ---------------------------------------------------------
// Blink Application
// ---------------------------------------------------------
int main(void) {
    // Force 3-stage mode (25 MHz)
    __asm__ volatile ("csrw 0x800, zero");

    while (1) {
        WRITE_REG(GPIO_DATA_REG, 0xFF); // Turn ALL LEDs ON
        delay();
        
        WRITE_REG(GPIO_DATA_REG, 0x00); // Turn ALL LEDs OFF
        delay();
    }
    
    return 0; 
}