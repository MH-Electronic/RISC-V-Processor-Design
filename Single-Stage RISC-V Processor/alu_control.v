module alu_control (
    input  wire [1:0] alu_op,       // From control unit
    input  wire [2:0] funct3,       // From instruction [14:12]
    input  wire       funct7_bit,   // Bit 30 of funct7
    output reg  [3:0] alu_control   // To ALU
);

    always @(*) begin
        case (alu_op)
            // Case 00: Load/Store/ADDI -> Force ADD
            2'b00: begin
                alu_control = 4'b0010; // ADD
            end

            // Case 01: Branch (BEQ) -> Force SUB
            2'b01: begin
                alu_control = 4'b0110; // SUB
            end

            // Case 10: R-type or I-type -> Decode based on funct3 and funct7
            2'b10: begin
                case (funct3)
                    3'b000: begin
                        if (funct7_bit == 1'b0) begin
                            alu_control = 4'b0010; // ADD
                        end else begin
                            alu_control = 4'b0110; // SUB
                        end
                    end

                    3'b111: begin
                        alu_control = 4'b0000; // AND
                    end

                    3'b110: begin
                        alu_control = 4'b0001; // OR
                    end

                    3'b010: begin
                        alu_control = 4'b0111; // SLT
                    end

                    default: begin
                        alu_control = 4'b0010; // Default to ADD
                    end
                endcase
            end

            default: begin
                alu_control = 4'b0010; // Default to ADD
            end
        endcase
    end

endmodule