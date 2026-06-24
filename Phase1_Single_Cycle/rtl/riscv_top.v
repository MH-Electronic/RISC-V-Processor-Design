module riscv_top (
    input  wire        clk,
    input  wire        rst_n,

    // External Memory Interfaces
    input  wire [31:0] instr,           // Instruction from instruction memory  
    input  wire [31:0] mem_read_data,   // Data from data memory
    output wire [31:0] pc_out,          // Current PC to instruction memory
    output wire [31:0] mem_write_data,  // Data to write to data memory
    output wire [31:0] alu_result_out,  // ALU result to data memory
    output wire        mem_write_en,    // Memory write enable
    output wire [2:0]  funct3_out,      // funct3 field for memory operations (for byte/half-word selection)
    output wire        test_finished    // Signal to indicate test completion (for compliance testing)
);

    // Internal Wires
    wire [31:0] pc_next, pc_plus4, branch_target, jalr_target;
    wire [31:0] rs1_data, rs2_data, write_data, imm_out, alu_a, alu_b, alu_res;
    wire [31:0] csr_rdata;
    wire [4:0]  alu_ctrl;
    wire [1:0]  alu_op_write;
    wire        reg_write, alu_src, mem_to_reg, branch, zero, less_than;
    wire        jal_sel, jalr_sel, upper_imm_sel;
    wire        csr_we;
    reg         take_branch;

    // 1. Instruction Fetch (IF) Stage
    assign pc_plus4         = pc_out + 4;
    assign branch_target    = pc_out + imm_out; // Branch target calculation
    assign jalr_target      = alu_res & ~32'b1; // JALR target calculation and alignment (clear LSB)
    
    // PC Next Logic (Priority: JALR > JAL/Branch > PC+4)
    assign pc_next = (jalr_sel)                             ? jalr_target :
                     (jal_sel || (branch && take_branch))   ? branch_target :
                      pc_plus4;

    assign funct3_out = instr[14:12]; // Pass funct3 to data memory for load/store byte/half-word selection

    pc unit_pc (
        .clk      (clk),
        .rst_n    (rst_n),
        .pc_next  (pc_next),
        .pc_out   (pc_out)
    );

    // 2. Instruction Decode (ID) Stage
    control_unit unit_control (
        .instr          (instr),
        .opcode         (instr[6:0]),
        .reg_write      (reg_write),
        .alu_src        (alu_src),
        .mem_to_reg     (mem_to_reg),
        .mem_write      (mem_write_en),
        .branch         (branch),
        .jal_sel        (jal_sel),
        .jalr_sel       (jalr_sel),
        .upper_imm_sel  (upper_imm_sel),
        .csr_we         (csr_we),
        .alu_op         (alu_op_write),
        .test_finished  (test_finished)
    );

    register_file unit_regfile (
        .clk         (clk),
        .reg_write_en(reg_write),
        .rs1_addr    (instr[19:15]),
        .rs2_addr    (instr[24:20]),
        .rd_addr     (instr[11:7]),
        .write_data  (write_data),
        .rs1_data    (rs1_data),
        .rs2_data    (rs2_data)
    );

    imm_gen unit_immgen (
        .instr       (instr),
        .imm_out     (imm_out)
    );

    csr_unit unit_csr (
        .clk            (clk),
        .rst_n          (rst_n),
        .csr_addr       (instr[31:20]),
        .csr_wdata      (rs1_data),             
        .csr_we         (csr_we),
        .csr_op         (instr[14:12]),        
        .instr_retired  (1'b1),             // Assume every instruction is retired for performance counters in single-cycle design
        .csr_rdata      (csr_rdata)
    );

    // 3. Execute (EX) Stage
    alu_control unit_alucontrol (
        .alu_op      (alu_op_write),
        .funct3      (instr[14:12]),
        .funct7_bit  (instr[30]),
        .opcode_6_4  (instr[6:4]),
        .alu_control (alu_ctrl)
    );

    // AUIPC and LUI handling: If upper_imm_sel is set, use imm_out as ALU A; otherwise use rs1_data
    assign alu_a = (instr[6:0] == 7'b0010111) ? pc_out : rs1_data;
    assign alu_b = (alu_src) ? imm_out : rs2_data; // Select between immediate and register

    alu unit_alu (
        .a           (alu_a),
        .b           (alu_b),
        .alu_control (alu_ctrl),
        .alu_result  (alu_res),
        .zero        (zero),
        .less_than   (less_than)
    );

    always @(*) begin
        case (instr[14:12]) // funct3
            3'b000: take_branch =  zero;         // BEQ
            3'b001: take_branch = !zero;         // BNE
            3'b100: take_branch =  less_than;    // BLT
            3'b101: take_branch = !less_than;    // BGE
            3'b110: take_branch =  less_than;    // BLTU
            3'b111: take_branch = !less_than;    // BGEU
            default: take_branch = 1'b0;
        endcase
    end

    // 4. Memory Access (MEM) Stage
    reg  [31:0] mem_to_reg_data;
    wire [7:0]  byte_data;
    wire [15:0] half_data;

    // Byte selection based on ALU result for LB and LBU
    assign byte_data = (alu_res[1:0] == 2'b00) ? mem_read_data[7:0] :
                       (alu_res[1:0] == 2'b01) ? mem_read_data[15:8] :
                       (alu_res[1:0] == 2'b10) ? mem_read_data[23:16] :
                                                 mem_read_data[31:24];

    // Half-word selection based on ALU result for LH and LHU
    assign half_data = (alu_res[1]) ? mem_read_data [31:16] : mem_read_data[15:0];

    always @(*) begin
        case (instr[14:12])
            3'b000: mem_to_reg_data = {{24{byte_data[7]}}, byte_data}; // LB
            3'b001: mem_to_reg_data = {{16{half_data[15]}}, half_data};// LH
            3'b010: mem_to_reg_data = mem_read_data;                   // LW
            3'b100: mem_to_reg_data = {24'b0, byte_data};              // LBU
            3'b101: mem_to_reg_data = {16'b0, half_data};              // LHU
            default: mem_to_reg_data = mem_read_data;                  // Default to LW
        endcase
    end

    // Outputs to data memory
    assign mem_write_data = rs2_data;

    assign alu_result_out = alu_res;

    // 5. Write Back (WB) Stage
    assign write_data = (instr[6:0] == 7'b0110111)  ? imm_out         :       // only for LUI
                        (jal_sel || jalr_sel)       ? pc_plus4        :       // Jumps
                        (mem_to_reg)                ? mem_to_reg_data :       // Loads
                        (csr_we)                    ? csr_rdata       :       // CSR Writeback
                                                      alu_res;                // ALU result for R-type and I-type 

endmodule


