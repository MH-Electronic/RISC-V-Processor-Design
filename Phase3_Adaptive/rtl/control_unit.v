module control_unit (
    input  wire [31:0] instr,
    input  wire [6:0]  opcode,
    input  wire        pipeline_mode,
    output reg         reg_write,     // Write to register file
    output reg         alu_src,       // ALU source (0: register, 1: immediate)
    output reg         mem_to_reg,    // Write to register from ALU result (0) or memory (1)
    output reg         mem_write,     // Write to memory
    output reg         branch,        // Branch instruction
    output reg         jal_sel,       // JAL instruction
    output reg         jalr_sel,      // JALR instruction
    output reg         csr_we,        // CSR write enable
    output reg [1:0]   alu_op,        // ALU operation code
    output reg         test_finished
);

    always @(*) begin
        // Default values to prevent latches
        reg_write       = 1'b0;
        alu_src         = 1'b0;
        mem_to_reg      = 1'b0;
        mem_write       = 1'b0;
        branch          = 1'b0;
        jal_sel         = 1'b0;
        jalr_sel        = 1'b0;
        csr_we          = 1'b0;
        alu_op          = 2'b00;
        test_finished   = 1'b0;

        case (opcode)
            7'b0110011: begin    // R-type (ADD, SUB, AND, OR, SLT)
                reg_write   = 1'b1;
                alu_op      = 2'b10;

            end

            7'b0010011: begin  // I-type (ADDI)
                reg_write     = 1'b1;
                alu_src       = 1'b1;
                alu_op        = 2'b10;
            end

            7'b0000011: begin // Load (LW)
                reg_write     = 1'b1;
                alu_src       = 1'b1;
                mem_to_reg    = 1'b1;
                alu_op        = 2'b00;
            end

            7'b0100011: begin // Store (SW)
                mem_write     = 1'b1;
                alu_src       = 1'b1;
                alu_op        = 2'b00;
            end

            7'b1100011: begin // Branch (BEQ)
                branch        = 1'b1;
                reg_write     = 1'b0;
                alu_op        = 2'b01;
            end

            7'b1101111: begin // JAL
                reg_write     = 1'b1;
                jal_sel       = 1'b1;
            end

            7'b1100111: begin // JALR
                reg_write     = 1'b1;
                alu_src       = 1'b1;
                jalr_sel      = 1'b1;
            end

            7'b0110111: begin // LUI
                reg_write       = 1'b1;
                alu_src         = 1'b1; // Use immediate for upper immediate
            end

            7'b0010111: begin // AUIPC
                reg_write       = 1'b1;
                alu_src         = 1'b1; // Use immediate for PC-relative calculation
            end

            7'b0001111: begin // FENCE (not implemented, treated as NOP)
                // No control signals needed
                reg_write  = 1'b0;
                mem_write  = 1'b0;
            end

            7'b1110011: begin   // SYSTEM (ECALL, EBREAK, CSR instructions)
                if (instr == 32'h00000073) begin // ECALL
                    test_finished = 1'b1; // Signal test completion
                    reg_write     = 1'b0;
                    csr_we        = 1'b0;
                end else begin
                    // Assume it's a CSR instruction for simplicity
                    reg_write     = (instr[11:7] != 5'b0) ? 1'b1 : 1'b0; // Only write if rd is not x0
                    csr_we        = 1'b1;
                    test_finished = 1'b0;
                end
            end

            default: begin
                // Explicitly set everything to 0 to prevent logic depth growth
                reg_write       = 1'b0;
                alu_src         = 1'b0;
                mem_to_reg      = 1'b0;
                mem_write       = 1'b0;
                branch          = 1'b0;
                jal_sel         = 1'b0;
                jalr_sel        = 1'b0;
                csr_we          = 1'b0;
                alu_op          = 2'b00; // NOP or unsupported instruction
            end
        endcase
    end

endmodule