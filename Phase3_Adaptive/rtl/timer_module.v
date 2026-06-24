module timer_module (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        timer_we,
    input  wire [31:0] addr,
    input  wire [31:0] timer_write_data,
    output reg  [31:0] timer_read_data,
    output wire        timer_interrupt
);

    reg [31:0] timer_count;
    reg [31:0] timer_compare;
    reg [31:0] timer_control;

    // 1. Timer Counter Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_count <= 32'b0;
        end else if (timer_control[0]) begin
            if (timer_count >= timer_compare) timer_count <= 32'b0;
            else                              timer_count <= timer_count + 1;
        end
    end

    // 2. Timer Register Access Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_compare  <= 32'b0;
            timer_control  <= 32'b0;
        end else if (timer_we) begin
            case (addr[3:2])
                2'b01: timer_compare <= timer_write_data; // Compare Register at 0x04
                2'b10: timer_control <= timer_write_data; // Control Register at 0x08
                default: ;
            endcase
        end
    end

    // 3. Timer Read Logic
    always @(*) begin
        case (addr[3:2])
            2'b00:   timer_read_data = timer_count;   // Counter Register at 0x00
            2'b01:   timer_read_data = timer_compare; // Compare Register at 0x04
            2'b10:   timer_read_data = timer_control; // Control Register at 0x08
            default: timer_read_data = 32'b0;
        endcase
    end

    // 4. Timer Interrupt Logic
    assign timer_interrupt = (timer_control[0] && (timer_count == timer_compare));

endmodule