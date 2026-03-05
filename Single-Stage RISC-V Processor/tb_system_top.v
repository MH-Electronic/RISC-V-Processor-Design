`timescale 1ns/1ps

module tb_system_top;

    // Clock and Reset
    reg         clk_in, rst_n;
    wire [7:0]  leds;

    // Add these Lattice Primitives to fix the 'GSR_INST' errors
    GSR GSR_INST ( .GSR_N(rst_n), .CLK(clk_in) ); // Global Set Reset (Active Low)
    PUR PUR_INST ( .PUR(rst_n) ); // Power Up Reset (Active Low)

    // Instantiate the System Top Module
    system_top u_system (
        .clk_in (clk_in),
        .rst_n  (rst_n),
        .leds   (leds)
    );

    // Clock Generation 
    initial begin
        clk_in = 0;
        forever #4 clk_in = ~clk_in; // 125 MHz clock
    end

    // Reset Generation
    initial begin
        rst_n = 0;
        #40 rst_n = 1;
    end

    wire [31:0] x3 = u_system.u_core.unit_regfile.registers[3];
    wire [31:0] x4 = u_system.u_core.unit_regfile.registers[4];
    wire [31:0] current_pc = u_system.u_core.unit_pc.pc_out;

    // Validation Sequence
    initial begin
        // Wait for some time to let the system execute
        wait(rst_n == 1);
        #500; 

        if (x3 === 32'd30 && x4 === 32'd30) begin
            $display("Test Passed: x3 = %d, x4 = %d", x3, x4);
        end else begin
            $display("Test Failed: x3 = %d, x4 = %d", x3, x4);
        end

        $display("Final PC: %d", current_pc);
        $stop;
    end
endmodule