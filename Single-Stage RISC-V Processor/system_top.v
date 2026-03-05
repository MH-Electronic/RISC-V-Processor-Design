module system_top (
    input  wire       clk_in,
    input  wire       rst_n,
    output wire [7:0] leds
);

    // Internal Wires
    wire [31:0] instr;
    wire [31:0] pc;
    wire [31:0] mem_read_data;
    wire [31:0] mem_write_data;
    wire [31:0] alu_result;
    wire        mem_write_en;
    wire        cpu_clk;
    wire        pll_lock;
	
	pll_clock u_pll (
        .clki_i     (clk_in),
        .rstn_i     (rst_n),
        .clkop_o    (cpu_clk),
        .lock_o     (pll_lock)
    );

    // Instantiate RISC-V Core
    riscv_top u_core (
        .clk            (cpu_clk),
        .rst_n          (rst_n),
        .instr          (instr),
        .pc_out         (pc),
        .mem_read_data  (mem_read_data),
        .mem_write_data (mem_write_data),
        .alu_result_out (alu_result),
        .mem_write_en   (mem_write_en)
    );

    // Instantiate Instruction Memory (ROM)
    instr_rom u_rom (
        .addr_i      (pc[11:2]),
        .rd_data_o   (instr)
    );

    // Instantiate Data Memory (RAM)
    data_ram u_ram (
        .addr_i          (alu_result[11:2]),
        .clk_en_i        (1'b1),
        .clk_i           (~cpu_clk),
        .rst_i           (!rst_n),
        .wr_data_i       (mem_write_data),
        .wr_en_i         (mem_write_en),
        .rd_data_o       (mem_read_data)
    );

    // Output ALU result to LEDs for debugging
    reg [7:0] leds_reg;
    always @(posedge cpu_clk or negedge rst_n) begin
        if (!rst_n) leds_reg <= 8'b0;
        else        leds_reg <= alu_result[7:0];
    end
    assign leds = leds_reg;

endmodule