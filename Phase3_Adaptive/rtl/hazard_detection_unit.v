module hazard_detection_unit (
    input  wire [4:0]  id_rs1_addr,
    input  wire [4:0]  id_rs2_addr,
    input  wire [4:0]  ex_rd_addr,
    input  wire        ex_mem_read,
    output reg         stall
);

    always @(*) begin
        // 1. Existing Load-Use Hazard
        if (ex_mem_read && (ex_rd_addr != 5'b0) && ((ex_rd_addr == id_rs1_addr) || (ex_rd_addr == id_rs2_addr))) begin
            stall = 1'b1;
        end else begin
            stall = 1'b0;
        end
    end
endmodule