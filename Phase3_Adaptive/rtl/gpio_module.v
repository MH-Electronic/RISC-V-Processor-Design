module gpio_module (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        gpio_we,
    input  wire [31:0] gpio_write_data,
    output reg  [31:0] gpio_read_data,
    output reg  [7:0]  leds
);

    // Write Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            leds <= 8'b0;
        end else if (gpio_we) begin
            // Only lower 8 bits (0x00 to 0xFF) control the LEDs
            leds <= gpio_write_data[7:0]; 
        end
    end

    // Read Logic
    always @(*) begin
        gpio_read_data = {24'b0, leds};
    end

endmodule