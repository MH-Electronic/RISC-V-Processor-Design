module data_ram (
    input  wire [14:0] addr_i,
    input  wire [3:0]  ben_i,
    input  wire        clk_en_i,
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire [31:0] wr_data_i,
    input  wire        wr_en_i,
    output wire [31:0] rd_data_o 
);
    reg [31:0] mem [0:32767];

    reg [31:0] rd_data_reg;
    assign rd_data_o = rd_data_reg;

    always @(negedge clk_i) begin
        rd_data_reg <= mem[addr_i];
    end

    // Hide the loop from the Synthesizer, keep it for Simulator
    // synthesis translate_off
    integer j;
    initial begin
        for (j = 0; j < 32768; j = j + 1) mem[j] = 32'b0;
    end
    // synthesis translate_on

    // Synchronous write
    always @(posedge clk_i) begin
        if (wr_en_i) begin
            if (ben_i[0]) mem[addr_i][ 7: 0] <= wr_data_i[ 7: 0];
            if (ben_i[1]) mem[addr_i][15: 8] <= wr_data_i[15: 8];
            if (ben_i[2]) mem[addr_i][23:16] <= wr_data_i[23:16];
            if (ben_i[3]) mem[addr_i][31:24] <= wr_data_i[31:24];
        end
    end
endmodule