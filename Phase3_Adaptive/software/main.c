#include "defines.h"

// Dynamically adjusts delay length based on the current pipeline mode
static void delay(void) {
    unsigned int mode_val;
    __asm__ volatile ("csrr %0, 0x800" : "=r"(mode_val));
    
    volatile unsigned int count = (mode_val & 0x1U) ? 2000000U : 1000000U;
    
    while (count > 0U) {
        __asm__ volatile ("nop");
        count--;
    }
}

int main(void) {
    unsigned char led_mask = 0x01; // Start at LED 0
    int sweeping_left = 1;         // Direction flag

    // Force 5-stage mode (50 MHz) for the application
    __asm__ volatile ("li t0, 1 \n csrw 0x800, t0" : : : "t0");

    while (1) {
        WRITE_REG(GPIO_DATA_REG, led_mask);
        delay();

        if (sweeping_left) {
            led_mask = led_mask << 1;
            if (led_mask == 0x80) sweeping_left = 0; 
        } else {
            led_mask = led_mask >> 1;
            if (led_mask == 0x01) sweeping_left = 1; 
        }
    }
    
    return 0; 
}