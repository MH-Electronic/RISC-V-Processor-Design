module riscv_top (
    input  wire        clk,
    input  wire        rst_n,

    // External Memory Interfaces
    input  wire [31:0] instr,           // Instruction from instruction memory  
    input  wire [31:0] mem_read_data,   // Data from data memory
    output wire [31:0] pc_out,          // Current PC to instruction memory
    output wire [31:0] mem_write_data,  // Data to write to data memory
    output wire [31:0] alu_result_out,  // ALU result to data memory
    output wire        mem_write_en     // Memory write enable
);

    // Internal Wires
    wire [31:0] pc_next, pc_plus4, branch_target;
    wire [31:0] rs1_data, rs2_data, write_data, imm_out, alu_b, alu_res;
    wire [3:0]  alu_ctrl;
    wire [1:0]  alu_op_write;
    wire        reg_write, alu_src, mem_to_reg, branch, zero;

    // 1. Instruction Fetch (IF) Stage
    wire  beq_taken = (branch && (rs1_data == rs2_data)); 
    assign pc_plus4 = pc_out + 4;
    assign pc_next  = beq_taken ? branch_target : pc_plus4;

    pc unit_pc (
        .clk      (clk),
        .rst_n    (rst_n),
        .pc_next  (pc_next),
        .pc_out   (pc_out)
    );

    // 2. Instruction Decode (ID) Stage
    control_unit unit_control (
        .opcode      (instr[6:0]),
        .reg_write   (reg_write),
        .alu_src     (alu_src),
        .mem_to_reg  (mem_to_reg),
        .mem_write   (mem_write_en),
        .branch      (branch),
        .alu_op      (alu_op_write)
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

    // 3. Execute (EX) Stage
    alu_control unit_alucontrol (
        .alu_op      (alu_op_write),
        .funct3      (instr[14:12]),
        .funct7_bit  (instr[30]),
        .alu_control (alu_ctrl)
    );

    assign alu_b = (alu_src) ? imm_out : rs2_data; // Select between immediate and register

    alu unit_alu (
        .a           (rs1_data),
        .b           (alu_b),
        .alu_control (alu_ctrl),
        .alu_result  (alu_res),
        .zero        (zero)
    );

    assign branch_target = pc_out + imm_out; // Branch target calculation

    // 4. Memory Access (MEM) Stage
    assign write_data = (mem_to_reg) ? mem_read_data : alu_res; // Select data to write back

    // Outputs to Data Memory
    assign alu_result_out = alu_res;
    assign mem_write_data = rs2_data;

endmodule