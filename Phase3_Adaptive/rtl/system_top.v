module system_top (
    input  wire       clk_in,
    input  wire       rst_n,
    
    // LED Outputs
    output wire [7:0] leds,

    // UART Physical Pins
    input  wire       uart_rx,
    output wire       uart_tx
);

    // Internal Wires
    wire [31:0] instr;
    wire [31:0] pc;
    wire [31:0] mem_read_data_ram;
    wire [31:0] mem_read_data_rom;
    reg  [31:0] final_read_data;
    wire [31:0] mem_write_data;
    wire [31:0] alu_result_out;
    wire [31:0] mem_write_data_aligned;
    wire        mem_write_en;
    wire        pll_lock;
    wire [2:0]  funct3_out;
    wire        core_finish;
	wire        test_finished;
    wire        is_tohost_write;

    // Peripheral Enable Signals
    wire        ram_we;
    wire        ram_en;
    wire        gpio_we;
    wire        gpio_en;
    wire        timer_we;
    wire        timer_en;
    wire        uart_we;
    wire        uart_en;

    // Peripheral Internal Wires
    wire [31:0] gpio_read_data;
    wire [31:0] uart_read_data;
    wire [31:0] timer_read_data;
    
    // APB Bus Signals for UART
    wire [31:0] apb_pwdata;
    wire [31:0] apb_prdata;
    wire [5:0]  apb_paddr;
    wire        apb_psel;
    wire        apb_penable;
    wire        apb_pwrite;
    wire        apb_pready;

    // Lattice Certus-NX Dyanmic Clock Select (DCS) for Adaptive Pipeline Mode Selection
    wire cpu_clk_glitchless;
    wire clk_slow; // 43.125 MHz for 3-stage mode
    wire clk_fast; // 68     MHz for 5-stage mode
    wire clk_sel;  // Clock select signal from CPU to control DCS mux

    // PLL for Clock Generation
	pll_clock u_pll (
        .clki_i         (clk_in),
        .rstn_i         (rst_n),
        .clkop_o        (clk_slow),
        .clkos_o        (clk_fast),
        .lock_o         (pll_lock)
    );

    // ---------------------------------------------------------
    // Professional Glitch-Free Clock Mux (No Primitives Needed)
    // ---------------------------------------------------------
    reg slow_q1, slow_q2;
    reg fast_q1, fast_q2;
    reg gated_slow_r, gated_fast_r;

    // --- Slow domain synchroniser (all FFs on negedge clk_slow) ---
    always @(negedge clk_slow or negedge rst_n) begin
        if (!rst_n) begin
            slow_q1      <= 1'b1;   // default: slow clock selected at reset
            slow_q2      <= 1'b1;
            gated_slow_r <= 1'b1;  // gate pre-opened
        end else begin
            slow_q1      <= (!clk_sel) & (!fast_q2); // request slow AND fast has deasserted
            slow_q2      <= slow_q1;
            gated_slow_r <= slow_q2;
        end
    end

    // --- Fast domain synchroniser (all FFs on negedge clk_fast) ---
    always @(negedge clk_fast or negedge rst_n) begin
        if (!rst_n) begin
            fast_q1     <= 1'b0;
            fast_q2     <= 1'b0;
            gated_fast_r <= 1'b0;
        end else begin
            fast_q1     <= clk_sel & (!slow_q2);  // request fast AND slow has deasserted
            fast_q2     <= fast_q1;
            gated_fast_r <= fast_q2;
        end
    end

    // --- Gate and combine ---
    wire gated_slow = clk_slow & gated_slow_r;
    wire gated_fast = clk_fast & gated_fast_r;
    assign cpu_clk_glitchless = gated_slow | gated_fast;

    // Instantiate RISC-V Core
    riscv_top u_core (
        .clk            (cpu_clk_glitchless),
        .rst_n          (rst_n && pll_lock),
        .instr          (instr),
        .pc_out         (pc),
        .mem_read_data  (final_read_data),
        .mem_write_data (mem_write_data),
        .alu_result_out (alu_result_out),
        .mem_write_en   (mem_write_en),
        .funct3_out     (funct3_out),
        .test_finished  (core_finish),
        .clk_sel        (clk_sel) // Output from core to control clock selection for adaptive pipeline mode
    );

    // Instantiate Instruction Memory (ROM)
    instr_rom_dual_port u_rom (
        .clk_n         (cpu_clk_glitchless),               // Drive with active PLL system clock tree
        .rst_n         (rst_n),                // Invert active-low reset to feed active-high IP reset port
        .addr_a_i      (pc[16:2]),              // Port A: Instruction Fetch address pointer
        .rd_data_a_o   (instr),                 // Raw instruction pattern fed to CPU pipeline
        .addr_b_i      (alu_result_out[16:2]),  // Port B: Data constant look-up pointer
        .rd_data_b_o   (mem_read_data_rom)      // Constant data routed to read-data multiplexer matrix
    );

    // Store Masking Logic for RAM (for SB, SH, SW)
    // Generate byte enable signals for RAM based on instruction type
    reg [3:0] ram_byte_we;

    always @(*) begin
        if (mem_write_en) begin
            case (funct3_out) // funct 3
                3'b000: begin // SB (Store Byte)
                    case (alu_result_out[1:0])
                        2'b00: ram_byte_we = 4'b0001; // Write to byte 0
                        2'b01: ram_byte_we = 4'b0010; // Write to byte 1
                        2'b10: ram_byte_we = 4'b0100; // Write to byte 2
                        2'b11: ram_byte_we = 4'b1000; // Write to byte 3
                        default: ram_byte_we = 4'b0000;
                    endcase
                end
                3'b001: begin // SH (Store Half-word)
                    // 2'b00 for lower half, 2'b10 for upper half
                    ram_byte_we = (alu_result_out[1]) ? 4'b1100 : 4'b0011;
                end
                3'b010: begin // SW (Store Word)
                    ram_byte_we = 4'b1111; // Write to all bytes
                end
                default: ram_byte_we = 4'b0000; // No write
            endcase
        end else begin
            ram_byte_we = 4'b0000; // No write
        end
    end

    assign mem_write_data_aligned = (funct3_out == 3'b000) ? {4{mem_write_data[7:0]}} :     // SB
                                    (funct3_out == 3'b001) ? {2{mem_write_data[15:0]}} :    // SH
                                     mem_write_data;                                        // SW

    // Instantiate Data Memory (RAM)
    data_ram u_ram (
        .addr_i          (alu_result_out[16:2]),
        .ben_i           (ram_byte_we),
        .clk_en_i        (1'b1),
        .clk_i           (cpu_clk_glitchless),
        .rst_i           (!rst_n),
        .wr_data_i       (mem_write_data_aligned),
        .wr_en_i         (ram_we),
        .rd_data_o       (mem_read_data_ram)
    );

    // ===================================================
    // Peripheral Modules (GPIO, Timer, UART)
    // ===================================================
    // 1. Centralized Address Decoder
    bus_decoder u_decoder (
        .addr               (alu_result_out),
        .master_write_en    (mem_write_en),
        .ram_en             (ram_en),
        .ram_we             (ram_we),
        .gpio_en            (gpio_en),
        .gpio_we            (gpio_we),
        .timer_en           (timer_en),
        .timer_we           (timer_we),
        .uart_en            (uart_en),
        .uart_we            (uart_we)
    );

    // 2. Instantiate GPIO Module
    gpio_module u_gpio (
        .clk                (cpu_clk_glitchless),
        .rst_n              (rst_n && pll_lock),
        .gpio_we            (gpio_we),
        .gpio_write_data    (mem_write_data),
        .gpio_read_data     (gpio_read_data),
        .leds               (leds)
    );

    // 3. Instantiate UART Bridge
    uart_bridge u_uart_bridge (
        .clk                (cpu_clk_glitchless),
        .rst_n              (rst_n && pll_lock),
        .uart_en            (uart_en),
        .uart_we            (uart_we),
        .addr               (alu_result_out),
        .uart_write_data    (mem_write_data),
        .apb_psel           (apb_psel),
        .apb_penable        (apb_penable),
        .apb_pwrite         (apb_pwrite),
        .apb_pwdata         (apb_pwdata),
        .apb_paddr          (apb_paddr),
        .apb_pready         (apb_pready)
    );

    // 4. Instantiate Lattice UART IP Core
    uart_module u_uart_ip (
        .clk_i              (cpu_clk_glitchless),
        .rst_n_i            (rst_n && pll_lock),
        .apb_psel_i         (apb_psel),
        .apb_penable_i      (apb_penable),
        .apb_pwrite_i       (apb_pwrite),
        .apb_paddr_i        (apb_paddr),
        .apb_pwdata_i       (apb_pwdata),
        .apb_pready_o       (apb_pready),
        .apb_prdata_o       (apb_prdata),
        .apb_pslverr_o      (), // Not used in this design
        .txd_o              (uart_tx),
        .rxd_i              (uart_rx),
        .int_o              () // Interrupt output can be connected to CPU if needed
    );

    assign uart_read_data = apb_prdata; // Route APB read data from UART to the data bus multiplexer

    // 5. Instantiate Timer Module
    timer_module u_timer (
        .clk                (cpu_clk_glitchless),
        .rst_n              (rst_n && pll_lock),
        .timer_we           (timer_we),
        .addr               (alu_result_out),
        .timer_write_data   (mem_write_data),
        .timer_read_data    (timer_read_data),
        .timer_interrupt    ()
    );

    // 6. Data Bus Multiplexing
    always @(*) begin
        case (1'b1) // Use priority encoding
            (alu_result_out[31:16] == 16'h8000) : final_read_data = mem_read_data_rom; // ROM
            (ram_en)                            : final_read_data = mem_read_data_ram; // RAM
            (gpio_en)                           : final_read_data = gpio_read_data;    // GPIO
            (timer_en)                          : final_read_data = timer_read_data;   // Timer
            (uart_en)                           : final_read_data = uart_read_data;    // UART
            default                             : final_read_data = 32'b0;
        endcase
    end

    // ===================================================
    // Testbench Finish Detection (for compliance testing)
    // ===================================================
    assign is_tohost_write = (alu_result_out == 32'h803FFF00) && mem_write_en;
    assign test_finished   = core_finish || is_tohost_write;

endmodule