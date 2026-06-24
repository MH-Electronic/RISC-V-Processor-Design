module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [4:0]  alu_control,
    output reg  [31:0] alu_result
);
    wire less_than;
    wire less_than_unsigned;

    // Internal wires for comparison used ONLY for SLT/SLTU instructions
    assign less_than           = ($signed(a) < $signed(b));
    assign less_than_unsigned  = (a < b);

    always @(*) begin
        case (alu_control)
            5'b00000: alu_result = a & b;                       // AND
            5'b00001: alu_result = a | b;                       // OR
            5'b00010: alu_result = a + b;                       // ADD
            5'b00110: alu_result = a - b;                       // SUB
            5'b00011: alu_result = a ^ b;                       // XOR
            5'b00100: alu_result = a << b[4:0];                 // SLL
            5'b00101: alu_result = a >> b[4:0];                 // SRL
            5'b01000: alu_result = ($signed(a) >>> b[4:0]);     // SRA
            5'b00111: alu_result = {31'b0, less_than};          // SLT (Set Less Than)
            5'b01001: alu_result = {31'b0, less_than_unsigned}; // SLTU
            5'b11111: alu_result = 32'b0;                       // NOP (or default)
            default: alu_result = 32'b0;
        endcase
    end
endmodule