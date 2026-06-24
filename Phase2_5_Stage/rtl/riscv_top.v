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

    // ===================================
    // 1. Internal Wires & Stage Signals
    // ===================================

    // Hazard & Control Wires
    wire stall;
    wire flush;

    // IF Stage
    wire [31:0] if_pc_plus4, if_pc_next;

    // ID Stage
    wire [31:0] id_pc, id_instr, id_rs1_data, id_rs2_data, id_imm;
    wire [1:0]  id_alu_op;
    wire        id_reg_write, id_alu_src, id_mem_to_reg, id_mem_write;
    wire        id_branch, id_jal_sel, id_jalr_sel, id_csr_we;

    // EX Stage
    wire [31:0] ex_pc, ex_instr, ex_rs1_data, ex_rs2_data, ex_imm;
    wire [31:0] ex_alu_a, ex_alu_b, ex_alu_res;
    wire [31:0] ex_branch_target, ex_jalr_target;
    wire [31:0] ex_csr_rdata;
    wire [4:0]  ex_alu_ctrl;
    wire [4:0]  ex_rd_addr, ex_rs1_addr, ex_rs2_addr;
    wire [1:0]  ex_alu_op;
    wire        ex_reg_write, ex_alu_src, ex_mem_to_reg, ex_mem_write, ex_csr_we;
    wire        ex_zero, ex_less_than, ex_jal_sel, ex_jalr_sel, ex_branch;
    reg         ex_take_branch;
    wire [1:0]  forward_a, forward_b;
    wire [31:0] ex_rs1_forwarded, ex_rs2_forwarded;

    // MEM Stage
    wire [31:0] mem_alu_res, mem_rs2_data, mem_csr_rdata;
    wire [4:0]  mem_rd_addr;
    wire [2:0]  mem_funct3;
    wire        mem_reg_write, mem_mem_to_reg, mem_mem_write, mem_csr_we;
    reg  [31:0] mem_to_reg_data;
    wire [7:0]  mem_byte_data;
    wire [15:0] mem_half_data;

    // WB Stage
    wire [31:0] wb_read_data, wb_alu_res, wb_csr_rdata, wb_write_data;
    wire [4:0]  wb_rd_addr;
    wire        wb_reg_write, wb_mem_to_reg, wb_csr_we;

    // ===================================
    // 2. INSTRUCTION FETCH (IF) 
    // ===================================
    assign if_pc_plus4      = pc_out + 4;
   
    
    // PC Next Logic (Calculated in EX, acted on in IF)
    assign flush      = (ex_jal_sel || ex_jalr_sel || (ex_branch && ex_take_branch));
    assign if_pc_next = (ex_jalr_sel)                                   ? ex_jalr_target :
                        (ex_jal_sel || (ex_branch && ex_take_branch))   ? ex_branch_target :
                         if_pc_plus4;

    pc unit_pc (
        .clk      (clk),
        .rst_n    (rst_n),
        .stall    (stall),
        .pc_next  (if_pc_next),
        .pc_out   (pc_out)
    );

    reg_if_id unit_if_id (
        .clk      (clk),
        .rst_n    (rst_n),
        .stall    (stall),
        .flush    (flush),
        .if_pc    (pc_out),
        .if_instr (instr),
        .id_pc    (id_pc),
        .id_instr (id_instr)
    );

    // ==================================
    // 3. Instruction Decode (ID) Stage
    // ==================================
    hazard_detection_unit unit_hazard (
        .id_rs1_addr    (id_instr[19:15]),
        .id_rs2_addr    (id_instr[24:20]),
        .ex_rd_addr     (ex_rd_addr),
        .ex_mem_read    (ex_mem_to_reg),
        .stall          (stall)
    );

    control_unit unit_control (
        .instr          (id_instr),
        .opcode         (id_instr[6:0]),
        .reg_write      (id_reg_write),
        .alu_src        (id_alu_src),
        .mem_to_reg     (id_mem_to_reg),
        .mem_write      (id_mem_write),
        .branch         (id_branch),
        .jal_sel        (id_jal_sel),
        .jalr_sel       (id_jalr_sel),
        .csr_we         (id_csr_we),
        .alu_op         (id_alu_op),
        .test_finished  (test_finished)
    );

    register_file unit_regfile (
        .clk         (clk),
        .reg_write_en(wb_reg_write),
        .rs1_addr    (id_instr[19:15]),
        .rs2_addr    (id_instr[24:20]),
        .rd_addr     (wb_rd_addr),
        .write_data  (wb_write_data),
        .rs1_data    (id_rs1_data),
        .rs2_data    (id_rs2_data)
    );

    imm_gen unit_immgen (
        .instr       (id_instr),
        .imm_out     (id_imm)
    );

    reg_id_ex unit_id_ex (
        .clk            (clk),
        .rst_n          (rst_n),
        .flush          (stall || flush),
        .id_pc          (id_pc),
        .id_instr       (id_instr),
        .id_reg_write   (id_reg_write),
        .id_alu_src     (id_alu_src),
        .id_mem_to_reg  (id_mem_to_reg),
        .id_mem_write   (id_mem_write),
        .id_alu_op      (id_alu_op),
        .id_csr_we      (id_csr_we),
        .id_rs1_data    (id_rs1_data),
        .id_rs2_data    (id_rs2_data),
        .id_imm         (id_imm),
        .id_rd_addr     (id_instr[11:7]),
        .id_rs1_addr    (id_instr[19:15]),
        .id_rs2_addr    (id_instr[24:20]),
        .id_branch      (id_branch),
        .id_jal_sel     (id_jal_sel),
        .id_jalr_sel    (id_jalr_sel),
        .ex_pc          (ex_pc),
        .ex_instr       (ex_instr),
        .ex_reg_write   (ex_reg_write),
        .ex_alu_src     (ex_alu_src),
        .ex_mem_to_reg  (ex_mem_to_reg),
        .ex_mem_write   (ex_mem_write),
        .ex_alu_op      (ex_alu_op),
        .ex_csr_we      (ex_csr_we),
        .ex_rs1_data    (ex_rs1_data),
        .ex_rs2_data    (ex_rs2_data),
        .ex_imm         (ex_imm),
        .ex_rd_addr     (ex_rd_addr),
        .ex_rs1_addr    (ex_rs1_addr),
        .ex_rs2_addr    (ex_rs2_addr),
        .ex_branch      (ex_branch),
        .ex_jal_sel     (ex_jal_sel),
        .ex_jalr_sel    (ex_jalr_sel)
    );

    // ==================================
    // 4. Execute (EX) Stage
    // ==================================
    forwarding_unit unit_forwarding (
        .ex_rs1_addr    (ex_rs1_addr),
        .ex_rs2_addr    (ex_rs2_addr),
        .mem_rd_addr    (mem_rd_addr),
        .wb_rd_addr     (wb_rd_addr),
        .mem_reg_write  (mem_reg_write),
        .wb_reg_write   (wb_reg_write),
        .forward_a      (forward_a),
        .forward_b      (forward_b)
    );

    // Selection Muxes for Forwarding
    assign ex_rs1_forwarded = (forward_a == 2'b10) ? mem_alu_res    :
                              (forward_a == 2'b01) ? wb_write_data  :
                               ex_rs1_data;

    assign ex_rs2_forwarded = (forward_b == 2'b10) ? mem_alu_res    :
                              (forward_b == 2'b01) ? wb_write_data  :
                               ex_rs2_data;

    alu_control unit_alucontrol (
        .alu_op      (ex_alu_op),
        .funct3      (ex_instr[14:12]),
        .funct7_bit  (ex_instr[30]),
        .opcode_6_4  (ex_instr[6:4]),
        .alu_control (ex_alu_ctrl)
    );

    assign ex_alu_a = (ex_instr[6:0] == 7'b0010111) ? ex_pc : 
                      (ex_instr[6:0] == 7'b0110111) ? 32'b0 : 
                                                      ex_rs1_forwarded;
    assign ex_alu_b = (ex_alu_src) ? ex_imm : 
                                     ex_rs2_forwarded; // Select between immediate and register

    alu unit_alu (
        .a           (ex_alu_a),
        .b           (ex_alu_b),
        .alu_control (ex_alu_ctrl),
        .alu_result  (ex_alu_res),
        .zero        (ex_zero),
        .less_than   (ex_less_than)
    );

    
    csr_unit unit_csr (
        .clk            (clk),
        .rst_n          (rst_n),
        .csr_addr       (ex_instr[31:20]),
        .csr_wdata      (ex_rs1_forwarded),             
        .csr_we         (ex_csr_we),
        .csr_op         (ex_instr[14:12]),        
        .instr_retired  (wb_reg_write),    // Only retired when written back
        .csr_rdata      (ex_csr_rdata)
    );

    assign ex_branch_target = ex_pc + ex_imm;
    assign ex_jalr_target   = ex_alu_res & ~32'b1; // Clear LSB for JALR target

    always @(*) begin
        case (ex_instr[14:12]) // funct3
            3'b000: ex_take_branch =  ex_zero;         // BEQ
            3'b001: ex_take_branch = !ex_zero;         // BNE
            3'b100: ex_take_branch =  ex_less_than;    // BLT
            3'b101: ex_take_branch = !ex_less_than;    // BGE
            3'b110: ex_take_branch =  ex_less_than;    // BLTU
            3'b111: ex_take_branch = !ex_less_than;    // BGEU
            default: ex_take_branch = 1'b0;
        endcase
    end

    reg_ex_mem unit_ex_mem (
        .clk            (clk),
        .rst_n          (rst_n),
        .ex_reg_write   (ex_reg_write),
        .ex_mem_to_reg  (ex_mem_to_reg),
        .ex_mem_write   (ex_mem_write),
        .ex_csr_we      (ex_csr_we),
        .ex_funct3      (ex_instr[14:12]),
        .ex_alu_result  ((ex_jal_sel || ex_jalr_sel) ? (ex_pc + 32'd4) : ex_alu_res),
        .ex_rs2_data    (ex_rs2_forwarded),
        .ex_csr_rdata   (ex_csr_rdata),
        .ex_rd_addr     (ex_rd_addr),
        .mem_reg_write  (mem_reg_write),
        .mem_mem_to_reg (mem_mem_to_reg),
        .mem_mem_write  (mem_mem_write),
        .mem_csr_we     (mem_csr_we),
        .mem_funct3     (mem_funct3),
        .mem_alu_result (mem_alu_res),
        .mem_rs2_data   (mem_rs2_data),
        .mem_csr_rdata  (mem_csr_rdata),
        .mem_rd_addr    (mem_rd_addr)
    );

    // ==================================
    // 5. Memory Access (MEM) Stage
    // ==================================
    assign mem_write_en     = mem_mem_write;
    assign alu_result_out   = mem_alu_res;
    assign mem_write_data   = mem_rs2_data;
    assign funct3_out       = mem_funct3;

    assign mem_byte_data = (mem_alu_res[1:0] == 2'b00) ? mem_read_data[7:0]     :
                           (mem_alu_res[1:0] == 2'b01) ? mem_read_data[15:8]    :
                           (mem_alu_res[1:0] == 2'b10) ? mem_read_data[23:16]   :
                            mem_read_data[31:24]; 

    assign mem_half_data = (mem_alu_res[1]) ? mem_read_data[31:16] : mem_read_data[15:0];

    always@(*) begin
        case (mem_funct3)
            3'b000 : mem_to_reg_data = {{24{mem_byte_data[7]}}, mem_byte_data};
            3'b001 : mem_to_reg_data = {{16{mem_half_data[15]}}, mem_half_data};
            3'b010 : mem_to_reg_data = mem_read_data;
            default: mem_to_reg_data = mem_read_data;
        endcase
    end 

    reg_mem_wb unit_mem_wb (
        .clk            (clk),
        .rst_n          (rst_n),
        .mem_reg_write  (mem_reg_write),
        .mem_mem_to_reg (mem_mem_to_reg),
        .mem_csr_we     (mem_csr_we),
        .mem_read_data  (mem_to_reg_data),
        .mem_alu_result (mem_alu_res),
        .mem_csr_rdata  (mem_csr_rdata),
        .mem_rd_addr    (mem_rd_addr),
        .wb_reg_write   (wb_reg_write),
        .wb_mem_to_reg  (wb_mem_to_reg),
        .wb_csr_we      (wb_csr_we),
        .wb_read_data   (wb_read_data),
        .wb_alu_result  (wb_alu_res),
        .wb_csr_rdata   (wb_csr_rdata),
        .wb_rd_addr     (wb_rd_addr)
    );

    // ==================================
    // 6. WRITE BACK (WB) Stage
    // ==================================
    assign wb_write_data = (wb_csr_we)      ? wb_csr_rdata  :
                           (wb_mem_to_reg)  ? wb_read_data  :
                            wb_alu_res      ;

endmodule 
