module register_file(
    input  wire        clk,
    input  wire        reg_write_en,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] write_data,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data
);
    reg [31:0] registers [0:31];

    // INTERNAL FORWARDING (Write-First, Read-Second)
    // This fixes the bug your script found! If the WB stage writes to a register
    // on the exact same cycle the ID stage reads it, grab the new data immediately.
    assign rs1_data = (rs1_addr == 5'b0) ? 32'b0 :
                      (reg_write_en && (rs1_addr == rd_addr)) ? write_data :
                      registers[rs1_addr];

    assign rs2_data = (rs2_addr == 5'b0) ? 32'b0 :
                      (reg_write_en && (rs2_addr == rd_addr)) ? write_data :
                      registers[rs2_addr];

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1) registers[i] = 32'b0;
    end

    always @(posedge clk) begin
        if (reg_write_en && (rd_addr != 5'b0)) begin
            registers[rd_addr] <= write_data;
        end
    end
endmodule