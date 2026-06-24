module reg_mem_wb (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             pipeline_mode, // 0: 5-Stage, 1: 3-Stage

    // Control Signals from MEM stage
    input  wire             mem_reg_write,
    input  wire             mem_mem_to_reg,
    input  wire             mem_csr_we,
    input  wire             mem_jal_sel,
    input  wire             mem_jalr_sel,

    // Data from MEM stage
    input  wire [31:0]      mem_read_data,
    input  wire [31:0]      mem_alu_result,
    input  wire [31:0]      mem_csr_rdata,
    input  wire [31:0]      mem_pc_plus4,
    input  wire [4:0]       mem_rd_addr,


    // Outputs to WB stage
    output reg  [31:0]      wb_read_data,
    output reg  [31:0]      wb_alu_result,
    output reg  [31:0]      wb_csr_rdata,
    output reg  [31:0]      wb_pc_plus4,
    output reg  [4:0]       wb_rd_addr,
    output reg              wb_reg_write,
    output reg              wb_mem_to_reg,
    output reg              wb_csr_we,
    output reg              wb_jal_sel,
    output reg              wb_jalr_sel
);

    always@(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_read_data    <= 32'b0;
            wb_alu_result   <= 32'b0;
            wb_csr_rdata    <= 32'b0;
            wb_pc_plus4     <= 32'b0;
            wb_rd_addr      <= 5'b0;
            wb_reg_write    <= 1'b0;
            wb_mem_to_reg   <= 1'b0;
            wb_csr_we       <= 1'b0;
            wb_jal_sel      <= 1'b0;
            wb_jalr_sel     <= 1'b0;
        end else begin
            wb_reg_write    <= mem_reg_write;
            wb_mem_to_reg   <= mem_mem_to_reg;
            wb_csr_we       <= mem_csr_we;
            wb_read_data    <= mem_read_data;
            wb_alu_result   <= mem_alu_result;
            wb_csr_rdata    <= mem_csr_rdata;
            wb_rd_addr      <= mem_rd_addr;
            wb_pc_plus4     <= mem_pc_plus4;
            wb_jal_sel      <= mem_jal_sel;
            wb_jalr_sel     <= mem_jalr_sel;
        end
    end

endmodule