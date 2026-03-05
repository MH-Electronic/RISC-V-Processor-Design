module control_unit (
    input  wire [6:0] opcode,
    output reg        reg_write,    // Write to register file
    output reg        alu_src,      // ALU source (0: register, 1: immediate)
    output reg        mem_to_reg,   // Write to register from ALU result (0) or memory (1)
    output reg        mem_write,    // Write to memory
    output reg        branch,       // Branch instruction
    output reg [1:0]  alu_op        // ALU operation code
);

    always @(*) begin
        // Default values to prevent latches
        reg_write   = 1'b0;
        alu_src     = 1'b0;
        mem_to_reg  = 1'b0;
        mem_write   = 1'b0;
        branch      = 1'b0;
        alu_op      = 2'b00;

        case (opcode)
            7'b0110011: begin    // R-type (ADD, SUB, AND, OR, SLT)
                reg_write   = 1'b1;
                alu_op      = 2'b10;
            end

            7'b0010011: begin  // I-type (ADDI)
                reg_write   = 1'b1;
                alu_src     = 1'b1;
                alu_op      = 2'b10;
            end

            7'b0000011: begin // Load (LW)
                reg_write   = 1'b1;
                alu_src     = 1'b1;
                mem_to_reg  = 1'b1;
                alu_op      = 2'b00;
            end

            7'b0100011: begin // Store (SW)
                mem_write   = 1'b1;
                alu_src     = 1'b1;
                alu_op      = 2'b00;
            end

            7'b1100011: begin // Branch (BEQ)
                branch      = 1'b1;
                alu_op      = 2'b01;
            end

            default: begin
                // Explicitly set everything to 0 to prevent logic depth growth
                reg_write  = 1'b0;
                alu_src    = 1'b0;
                mem_to_reg = 1'b0;
                mem_write  = 1'b0;
                branch     = 1'b0;
                alu_op     = 2'b00; // NOP or unsupported instruction
            end
        endcase
    end

endmodule