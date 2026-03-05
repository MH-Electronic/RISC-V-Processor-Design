module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm_out
);

    always @(*) begin
        case (instr[6:0])
            // I-Type (ADDI, LW)
            7'b0010011, 7'b0000011: begin
                imm_out = {{20{instr[31]}}, instr[31:20]};
            end

            // S-Type (SW)
            7'b0100011: begin
                imm_out = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end

            // B-Type (BEQ)
            7'b1100011: begin
                imm_out = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            end

            default: begin
                imm_out = 32'b0; // Default case
            end
        endcase
    end

endmodule
