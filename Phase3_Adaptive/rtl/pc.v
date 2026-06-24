module pc (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         stall,
    input  wire [31:0]  pc_next,
    output reg  [31:0]  pc_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out <= 32'h8000_0000;
        end else if (!stall) begin
            pc_out <= (^pc_next === 1'bx) ? pc_out : pc_next; // hold on X, don't silently corrupt
        end
    end

endmodule