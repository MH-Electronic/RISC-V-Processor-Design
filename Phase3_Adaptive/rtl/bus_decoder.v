module bus_decoder (
    input wire [31:0] addr,
    input wire        master_write_en,

    output reg        ram_en,
    output reg        ram_we,
    output reg        gpio_en,
    output reg        gpio_we,
    output reg        timer_en,
    output reg        timer_we,
    output reg        uart_en,
    output reg        uart_we
);

    always @(*) begin
        ram_en      = 0;
        ram_we      = 0;
        gpio_en     = 0;
        gpio_we     = 0;
        timer_en    = 0;
        timer_we    = 0;
        uart_en     = 0;
        uart_we     = 0;

        case (addr[31:16])
            16'h8001: begin // RAM space: 0x80010000
                ram_en = 1'b1;
                ram_we = master_write_en;
            end
            16'h9000: begin // Peripherals: 0x90000000
                case (addr[15:8])
                    8'h00: begin gpio_en = 1'b1;  gpio_we = master_write_en; end
                    8'h01: begin timer_en = 1'b1; timer_we = master_write_en; end
                    8'h02: begin uart_en = 1'b1;  uart_we = master_write_en; end
                    default: ;
                endcase
            end
            default: ;
        endcase
    end

endmodule