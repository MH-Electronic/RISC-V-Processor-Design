module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm_out
);

    always @(*) begin
        case (instr[6:0])
            // I-Type (ADDI, LW, JALR)
            7'b0010011, 7'b0000011, 7'b1100111: begin
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

            // U-Type (LUI, AUIPC)
            7'b0110111, 7'b0010111: begin
                imm_out = {instr[31:12], 12'b0};
            end

            // J-Type (JAL)
            7'b1101111: begin
                imm_out = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
            end


            default: begin
                imm_out = 32'b0; // Default case
            end
        endcase
    end

endmodule