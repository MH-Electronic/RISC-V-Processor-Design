module reg_if_id (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         stall, // For Hazard Detection  
    input  wire         flush, // For Branch Misprediction
    input  wire [31:0]  if_pc,
    input  wire [31:0]  if_instr,
    output reg  [31:0]  id_pc,
    output reg  [31:0]  id_instr
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            id_pc    <= 32'h0;
            id_instr <= 32'h00000013; // Default to NOP 
        end else if (!stall) begin
            id_pc    <= if_pc;
            id_instr <= if_instr;
        end
    end

endmodule