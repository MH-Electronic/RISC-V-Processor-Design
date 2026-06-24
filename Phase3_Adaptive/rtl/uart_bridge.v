module uart_bridge (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_en,
    input  wire        uart_we,
    input  wire [31:0] addr,
    input  wire [31:0] uart_write_data,

    // Connections to Lattice UART IP
    input  wire        apb_pready,
    output reg  [31:0] apb_pwdata,
    output reg  [5:0]  apb_paddr,
    output reg         apb_psel,
    output reg         apb_penable,
    output reg         apb_pwrite
);

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= 2'b00;
            apb_psel    <= 1'b0;
            apb_penable <= 1'b0;
            apb_pwrite  <= 1'b0;
        end else begin
            case (state)
                // IDLE -> SETUP
                2'b00: begin
                    if (uart_en) begin
                        state       <= 2'b01;
                        apb_psel    <= 1'b1;
                        apb_pwrite  <= uart_we;
                        apb_pwdata  <= uart_write_data;
                        apb_paddr   <= addr[5:0]; // Assuming 64-byte address
                    end
                end

                // SETUP -> ACCESS
                2'b01: begin
                    state       <= 2'b10;
                    apb_penable <= 1'b1;
                end

                // WAIT FOR READY
                2'b10: begin
                    if (apb_pready) begin
                        state       <= 2'b00;
                        apb_psel    <= 1'b0;
                        apb_penable <= 1'b0;
                        apb_pwrite  <= 1'b0;
                    end
                end

                default: state <= 2'b00;
            endcase
        end
    end

endmodule