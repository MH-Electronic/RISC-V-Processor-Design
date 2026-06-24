module reg_if_id (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         stall, 
    input  wire         flush, 
    input  wire [31:0]  if_pc,
    input  wire [31:0]  if_instr,
    output reg  [31:0]  id_pc,
    output reg  [31:0]  id_instr
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc    <= 32'h0;
            id_instr <= 32'h00000013; // Default to NOP 
        end else if (flush) begin
            id_pc    <= 32'h0;
            id_instr <= 32'h00000013; // Insert NOP on Flush
        end else if (!stall) begin
            // DIRECT PASS-THROUGH: Keeps PC and Instruction perfectly synced
            id_pc    <= if_pc;        
            
            if (^if_instr === 1'bx) begin
                id_instr <= 32'h00000013; // Treat X as NOP
            end else begin
                id_instr <= if_instr;
            end
        end
    end

endmodule