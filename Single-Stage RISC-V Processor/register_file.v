module register_file(
    input  wire        clk,
    input  wire        reg_write_en,        // Control signal from Control Unit
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] write_data,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data
);

    reg [31:0] registers [0:31];

    // Asynchronous read
    assign rs1_data = (rs1_addr == 5'b0) ? 32'b0 : registers[rs1_addr];
    assign rs2_data = (rs2_addr == 5'b0) ? 32'b0 : registers[rs2_addr];

    // Synchronous write
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