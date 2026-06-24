// In a single-cycle design, it is entirely combinational (no clocks)
module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [4:0]  alu_control,
    output reg  [31:0] alu_result,
    output wire        zero,
    output wire        less_than
);
    // Zero flag for branch instructions
    assign zero = (alu_result == 32'b0);

    // Precompute common operations
    wire [31:0] sum  = a + b;
    wire [31:0] diff = a - b;

    assign less_than = (alu_control == 5'b00111) ? ($signed(a) < $signed(b))    : 
                       (alu_control == 5'b01001) ? (a < b)                      : 
                                                   1'b0                         ;

    always @(*) begin
        case (alu_control)
            5'b00000: alu_result = a & b;                    // AND
            5'b00001: alu_result = a | b;                    // OR
            5'b00010: alu_result = sum;                      // ADD
            5'b00110: alu_result = diff;                     // SUB
            5'b00011: alu_result = a ^ b;                    // XOR
            5'b00100: alu_result = a << b[4:0];              // SLL
            5'b00101: alu_result = a >> b[4:0];              // SRL
            5'b01000: alu_result = ($signed(a) >>> b[4:0]);  // SRA
            5'b01001: alu_result = {31'b0, less_than};       // SLTU
            5'b00111: alu_result = {31'b0, less_than};       // SLT
            
            default: alu_result = 32'b0;
        endcase
    end

endmodule

