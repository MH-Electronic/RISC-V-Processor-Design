module reg_mem_wb (
    input  wire             clk,
    input  wire             rst_n,

    // Control Signals from MEM stage
    input  wire             mem_reg_write,
    input  wire             mem_mem_to_reg,
    input  wire             mem_csr_we,

    // Data from MEM stage
    input  wire [31:0]      mem_read_data,
    input  wire [31:0]      mem_alu_result,
    input  wire [31:0]      mem_csr_rdata,
    input  wire [4:0]       mem_rd_addr,

    // Outputs to WB stage
    output reg              wb_reg_write,
    output reg              wb_mem_to_reg,
    output reg              wb_csr_we,
    output reg  [31:0]      wb_read_data,
    output reg  [31:0]      wb_alu_result,
    output reg  [31:0]      wb_csr_rdata,
    output reg  [4:0]       wb_rd_addr
);

    always@(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_reg_write    <= 1'b0;
            wb_mem_to_reg   <= 1'b0;
            wb_csr_we       <= 1'b0;
            wb_read_data    <= 32'b0;
            wb_alu_result   <= 32'b0;
            wb_csr_rdata    <= 32'b0;
            wb_rd_addr      <= 5'b0;
        end else begin
            wb_reg_write    <= mem_reg_write;
            wb_mem_to_reg   <= mem_mem_to_reg;
            wb_csr_we       <= mem_csr_we;
            wb_read_data    <= mem_read_data;
            wb_alu_result   <= mem_alu_result;
            wb_csr_rdata    <= mem_csr_rdata;
            wb_rd_addr      <= mem_rd_addr;
        end
    end

endmodule
