module alu_control (
    input  wire [1:0] alu_op,       // From control unit
    input  wire [2:0] funct3,       // From instruction [14:12]
    input  wire       funct7_bit,   // From instruction [30] for R-type instructions
    input  wire [2:0] opcode_6_4,   // From instruction [6:4] for upper immediate instructions
    output reg  [4:0] alu_control   // To ALU
);

    always @(*) begin
        case (alu_op)
            // Case 00: Load/Store/AUIPC/JALR
            2'b00: begin
                alu_control = 5'b00010; // ADD
            end

            // Case 01: Branch
            2'b01: begin
                alu_control = 5'b00110; // SUB
            end

            // Case 10: R-type or I-type -> Decode based on funct3 and funct7 (or opcode for upper immediate)
            2'b10: begin
                case (funct3)
                    3'b000: begin
                        if (funct7_bit && opcode_6_4 == 3'b011) 
                            alu_control = 5'b00110;  // SUB (for R-type)
                        else 
                            alu_control = 5'b00010;  // ADD (for I-type and R-type)
                    end
                    3'b001: alu_control = 5'b00100;                         // SLL
                    3'b010: alu_control = 5'b00111;                         // SLT
                    3'b011: alu_control = 5'b01001;                         // SLTU
                    3'b100: alu_control = 5'b00011;                         // XOR
                    3'b101: begin
                        alu_control = (funct7_bit) ? 5'b01000 : 5'b00101;   // SRA / SRL
                    end
                    3'b110: alu_control = 5'b00001;                          // OR
                    3'b111: alu_control = 5'b00000;                          // AND
                    default: alu_control = 5'b00010;                         // Default to ADD
                endcase
            end

            default: begin
                alu_control = 5'b00010; // Default to ADD
            end
        endcase
    end

endmodule