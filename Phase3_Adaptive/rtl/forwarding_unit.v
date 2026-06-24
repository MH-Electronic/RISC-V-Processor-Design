module forwarding_unit (
    input  wire [4:0]  ex_rs1_addr,
    input  wire [4:0]  ex_rs2_addr,
    input  wire [4:0]  mem_rd_addr,
    input  wire [4:0]  wb_rd_addr,
    input  wire        mem_reg_write, // Must be HIGH to forward
    input  wire        wb_reg_write,  // Must be HIGH to forward
    input  wire        pipeline_mode,        

    output reg  [1:0]  forward_a,
    output reg  [1:0]  forward_b
);

    always @(*) begin
        // Forwarding for RS1
        if (mem_reg_write && (mem_rd_addr != 5'b0) && (mem_rd_addr == ex_rs1_addr))
            forward_a = 2'b10;
        else if (wb_reg_write && (wb_rd_addr != 5'b0) && (wb_rd_addr == ex_rs1_addr))
            forward_a = 2'b01;
        else
            forward_a = 2'b00;

        // Forwarding for RS2
        if (mem_reg_write && (mem_rd_addr != 5'b0) && (mem_rd_addr == ex_rs2_addr))
            forward_b = 2'b10;
        else if (wb_reg_write && (wb_rd_addr != 5'b0) && (wb_rd_addr == ex_rs2_addr))
            forward_b = 2'b01;
        else 
            forward_b = 2'b00;
    end
endmodule