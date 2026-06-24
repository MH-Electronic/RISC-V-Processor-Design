module system_top (
    input  wire       clk_in,
    input  wire       rst_n,

    output wire [7:0] leds,
    output wire       test_finished
);

    // Internal Wires
    wire [31:0] instr;
    wire [31:0] pc;
    wire [31:0] mem_read_data_ram;
    wire [31:0] mem_read_data_rom;
    wire [31:0] final_read_data;
    wire [31:0] mem_write_data;
    wire [31:0] alu_result_out;
    wire [31:0] mem_write_data_aligned;
    wire        mem_write_en;
    wire        cpu_clk;
    wire        pll_lock;
    wire [2:0]  funct3_out;
    wire        core_finish;
    wire        is_tohost_write;

    // --- THE CRITICAL FIX: DRIVE THE OUTPUTS ---
    // Mapping the PC to the LEDs forces the synthesizer to keep the CPU intact
    assign leds = pc[9:2]; 
    
    // Pass the internal finish signal to the top-level output for the testbench
    assign test_finished = core_finish || is_tohost_write;

    // 1. Address Decoding for Memory-Mapped I/O
    wire is_ram_addr = (alu_result_out[31:22] == 10'b1000000000); // 0x40000000 - 0x7FFFFFFF for RAM
    wire is_rom_addr = (alu_result_out[31:22] == 10'b0000000000); // 0x00000000 - 0x3FFFFFFF for ROM

    // 2. Data Bus Multiplexing: Choose between ROM and RAM read data
    assign final_read_data = is_ram_addr ? mem_read_data_ram :
                             is_rom_addr ? mem_read_data_rom :
                             32'b0; // Default to zero for invalid addresses

    // 3. Testbench Finish Detection (for compliance testing)
    assign is_tohost_write = (alu_result_out == 32'h803FFF00) && mem_write_en && (mem_write_data != 32'b0);
    assign test_finished   = core_finish || is_tohost_write;

    // PLL for Clock Generation
	pll_clock u_pll (
        .clki_i     (clk_in),
        .rstn_i     (rst_n),
        .clkop_o    (cpu_clk),
        .lock_o     (pll_lock)
    );

    // Instantiate RISC-V Core
    riscv_top u_core (
        .clk            (cpu_clk),
        .rst_n          (rst_n && pll_lock),
        .instr          (instr),
        .pc_out         (pc),
        .mem_read_data  (final_read_data),
        .mem_write_data (mem_write_data),
        .alu_result_out (alu_result_out),
        .mem_write_en   (mem_write_en),
        .funct3_out     (funct3_out),
        .test_finished  (core_finish)
    );

    // Instantiate Instruction Memory (ROM)
    instr_rom u_rom (
        .addr_a_i      (pc[16:2]),              // Port A: Instruction Fetch (word-aligned)
        .rd_data_a_o   (instr),
        .addr_b_i      (alu_result_out[16:2]),  // Port B: Data Read (for constants, word-aligned)
        .rd_data_b_o   (mem_read_data_rom)
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
        .clk_i           (~cpu_clk),
        .rst_i           (!rst_n),
        .wr_data_i       (mem_write_data_aligned),
        .wr_en_i         (mem_write_en && is_ram_addr),
        .rd_data_o       (mem_read_data_ram)
    );

endmodule