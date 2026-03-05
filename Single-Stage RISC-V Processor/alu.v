// In a single-cycle design, it is entirely combinational (no clocks)
module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  alu_control,
    output reg  [31:0] alu_result,
    output wire        zero
);
    // Zero flag for branch instructions
    assign zero = (alu_result == 32'b0);

    // Precompute results for addition and subtraction to simplify the case statement
    wire [31:0] sum = a + b;
    wire [31:0] diff = a - b;

    always @(*) begin
        case (alu_control)
            4'b0000: alu_result = a & b;        // AND
            4'b0001: alu_result = a | b;        // OR
            4'b0010: alu_result = sum;          // ADD
            4'b0110: alu_result = diff;         // SUB
            4'b0111: alu_result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0; // SLT
            default: alu_result = 32'b0;
        endcase
    end

endmodule