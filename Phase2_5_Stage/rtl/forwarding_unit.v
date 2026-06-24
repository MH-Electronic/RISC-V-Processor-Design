module forwarding_unit (
    input  wire [4:0]   ex_rs1_addr,
    input  wire [4:0]   ex_rs2_addr,
    input  wire [4:0]   mem_rd_addr,
    input  wire [4:0]   wb_rd_addr,
    input  wire         mem_reg_write,
    input  wire         wb_reg_write,

    // Selection Signals for ALU Muxes
    // 00: Use Original Register Data (ID/EX Register)
    // 01: Forward from WB  Stage
    // 10: Forward from MEM Stage
    output reg  [1:0]   forward_a,
    output reg  [1:0]   forward_b
);

    always @(*) begin
        // Forwarding for RS1 (Operand A)
        if (mem_reg_write && (mem_rd_addr != 5'b0) && (mem_rd_addr == ex_rs1_addr))
            forward_a = 2'b10;  // Forward from MEM stage
        else if (wb_reg_write && (wb_rd_addr != 5'b0) && (wb_rd_addr == ex_rs1_addr))
            forward_a = 2'b01;  // Forward from WB stage
        else
            forward_a = 2'b00;  // No Forwarding

        // Forwarding for RS2 (Operand B)
        if (mem_reg_write && (mem_rd_addr != 5'b0) && (mem_rd_addr == ex_rs2_addr))
            forward_b = 2'b10;  // Forward from MEM stage
        else if (wb_reg_write && (wb_rd_addr != 5'b0) && (wb_rd_addr == ex_rs2_addr))
            forward_b = 2'b01;  // Forward from WB stage
        else 
            forward_b = 2'b00;  // No forwarding
    end
endmodule
