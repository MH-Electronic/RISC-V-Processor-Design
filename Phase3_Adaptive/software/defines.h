#ifndef _DEFINES_H
#define _DEFINES_H

/* asm keyword -- GCC bare-metal uses __asm__ to avoid conflicts with C++ */
#define asm __asm__

/* -------------------------------------------------------------------------
   Peripheral base addresses
   These must match the bus_decoder address decoding:
     addr[31:20] = 12'h900  ->  peripheral space  (0x90000000 - 0x900FFFFF)
     addr[19:8]  = 12'h000  ->  GPIO   (0x90000000)
     addr[19:8]  = 12'h001  ->  Timer  (0x90000100)
     addr[19:8]  = 12'h002  ->  UART   (0x90000200)
------------------------------------------------------------------------- */
#define GPIO_BASE       0x90000000U
#define TIMER_BASE      0x90000100U
#define UART_BASE       0x90000200U

/* -------------------------------------------------------------------------
   Register offsets within each peripheral
------------------------------------------------------------------------- */
/* GPIO */
#define GPIO_DATA_REG   (GPIO_BASE  + 0x00U)

/* Timer */
#define TIMER_COUNT     (TIMER_BASE + 0x00U)    /* read-only counter */
#define TIMER_COMPARE   (TIMER_BASE + 0x04U)    /* compare register  */
#define TIMER_CONTROL   (TIMER_BASE + 0x08U)    /* control register  */
#define TIMER_STATUS    (TIMER_BASE + 0x0CU)    /* status  register  */

/* UART (mapped through APB bridge) */
#define UART_RBR        (UART_BASE  + 0x00U)    /* receive  buffer   */
#define UART_LSR        (UART_BASE  + 0x04U)    /* line status       */
#define UART_THR        (UART_BASE  + 0x08U)    /* transmit holding  */

/* -------------------------------------------------------------------------
   Memory-mapped I/O helper macros
------------------------------------------------------------------------- */
#define WRITE_REG(addr, val) \
    (*((volatile unsigned int *)(addr)) = (unsigned int)(val))

#define READ_REG(addr) \
    (*((volatile unsigned int *)(addr)))

#endif /* _DEFINES_H */

