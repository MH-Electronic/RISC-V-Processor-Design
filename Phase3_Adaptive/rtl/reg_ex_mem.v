module reg_ex_mem (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             pipeline_mode, // 0: 5-Stage, 1: 3-Stage

    // Control Signals from EX stage
    input  wire             ex_reg_write,
    input  wire             ex_mem_to_reg,
    input  wire             ex_mem_write,
    input  wire             ex_csr_we,
    input  wire [2:0]       ex_funct3,
    input  wire             ex_jal_sel,
    input  wire             ex_jalr_sel,

    // Data from EX stage
    input  wire [31:0]      ex_alu_result,
    input  wire [31:0]      ex_rs2_data,
    input  wire [31:0]      ex_csr_rdata,
    input  wire [31:0]      ex_pc_plus4,
    input  wire [4:0]       ex_rd_addr,


    // Outputs to MEM stage
    output reg  [31:0]      mem_alu_result,
    output reg  [31:0]      mem_rs2_data,
    output reg  [31:0]      mem_csr_rdata,
    output reg  [31:0]      mem_pc_plus4,
    output reg  [4:0]       mem_rd_addr,
    output reg  [2:0]       mem_funct3,
    output reg              mem_reg_write,
    output reg              mem_mem_to_reg,
    output reg              mem_mem_write,
    output reg              mem_csr_we,
    output reg              mem_jal_sel,
    output reg              mem_jalr_sel
);

    always@(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_alu_result  <= 32'b0;
            mem_rs2_data    <= 32'b0;
            mem_csr_rdata   <= 32'b0;
            mem_pc_plus4    <= 32'b0;
            mem_rd_addr     <= 5'b0;
            mem_funct3      <= 3'b0;
            mem_reg_write   <= 1'b0;
            mem_mem_to_reg  <= 1'b0;
            mem_mem_write   <= 1'b0;
            mem_csr_we      <= 1'b0;
            mem_jal_sel     <= 1'b0;
            mem_jalr_sel    <= 1'b0;
        end else begin
            mem_reg_write   <= ex_reg_write;
            mem_mem_to_reg  <= ex_mem_to_reg;
            mem_mem_write   <= ex_mem_write;
            mem_csr_we      <= ex_csr_we;
            mem_funct3      <= ex_funct3;
            mem_alu_result  <= ex_alu_result;
            mem_rs2_data    <= ex_rs2_data;
            mem_csr_rdata   <= ex_csr_rdata;
            mem_rd_addr     <= ex_rd_addr;
            mem_pc_plus4    <= ex_pc_plus4;
            mem_jal_sel     <= ex_jal_sel;
            mem_jalr_sel    <= ex_jalr_sel;
        end
    end
    
endmodule