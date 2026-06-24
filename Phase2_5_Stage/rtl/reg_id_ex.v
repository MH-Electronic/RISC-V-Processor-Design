module reg_id_ex (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         flush,

    // Stage Tracking
    input  wire [31:0]  id_pc,
    input  wire [31:0]  id_instr,

    // Control Signals
    input  wire         id_reg_write,
    input  wire         id_alu_src,
    input  wire         id_mem_to_reg,
    input  wire         id_mem_write,
    input  wire [1:0]   id_alu_op,
    input  wire         id_csr_we,
    input  wire         id_branch,
    input  wire         id_jal_sel,
    input  wire         id_jalr_sel,

    // Data
    input  wire [31:0]  id_rs1_data,
    input  wire [31:0]  id_rs2_data,
    input  wire [31:0]  id_imm,
    input  wire [4:0]   id_rd_addr,
    input  wire [4:0]   id_rs1_addr,
    input  wire [4:0]   id_rs2_addr,

    // Outputs to EX stage
    output reg  [31:0]  ex_pc,
    output reg  [31:0]  ex_instr,
    output reg          ex_reg_write,
    output reg          ex_alu_src,
    output reg          ex_mem_to_reg,
    output reg          ex_mem_write,
    output reg  [1:0]   ex_alu_op,
    output reg          ex_csr_we,
    output reg          ex_branch,
    output reg          ex_jal_sel,
    output reg          ex_jalr_sel,
    output reg  [31:0]  ex_rs1_data,
    output reg  [31:0]  ex_rs2_data,
    output reg  [31:0]  ex_imm,
    output reg  [4:0]   ex_rd_addr,
    output reg  [4:0]   ex_rs1_addr,
    output reg  [4:0]   ex_rs2_addr
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            ex_pc           <= 32'b0;
            ex_instr        <= 32'h00000013;
            ex_reg_write    <= 1'b0;
            ex_alu_src      <= 1'b0;
            ex_mem_to_reg   <= 1'b0;
            ex_mem_write    <= 1'b0;
            ex_alu_op       <= 2'b00;
            ex_csr_we       <= 1'b0;
            ex_branch       <= 1'b0;
            ex_jal_sel      <= 1'b0;
            ex_jalr_sel     <= 1'b0;
            ex_rs1_data     <= 32'b0;
            ex_rs2_data     <= 32'b0;
            ex_imm          <= 32'b0;
            ex_rd_addr      <= 5'b0;
            ex_rs1_addr     <= 5'b0;
            ex_rs2_addr     <= 5'b0;
        end else begin
            ex_pc           <= id_pc;
            ex_instr        <= id_instr;
            ex_reg_write    <= id_reg_write;
            ex_alu_src      <= id_alu_src;
            ex_mem_to_reg   <= id_mem_to_reg;
            ex_mem_write    <= id_mem_write;
            ex_alu_op       <= id_alu_op;
            ex_csr_we       <= id_csr_we;
            ex_branch       <= id_branch;
            ex_jal_sel      <= id_jal_sel;
            ex_jalr_sel     <= id_jalr_sel;
            ex_rs1_data     <= id_rs1_data;
            ex_rs2_data     <= id_rs2_data;
            ex_imm          <= id_imm;
            ex_rd_addr      <= id_rd_addr;
            ex_rs1_addr     <= id_rs1_addr;
            ex_rs2_addr     <= id_rs2_addr;
        end
    end

endmodule