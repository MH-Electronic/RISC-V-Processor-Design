// =============================================================================
// instr_rom_dual_port.v  --  Dual-port instruction ROM for bare-metal RISC-V
//
// Changes vs previous version:
//   1. $readmemh path changed from a hardcoded absolute Windows path to a
//      relative path "instr.mem".  The simulator must be launched from the
//      project root directory (where `make` writes instr.mem).
//      If your simulator requires an absolute path, set the MEM_PATH parameter
//      at instantiation:
//        instr_rom_dual_port #(.MEM_PATH("/home/user/fyp/instr.mem")) u_rom(...);
//   2. Parameter added so the path can be overridden at elaboration without
//      editing this file.
// =============================================================================

module instr_rom_dual_port #(
    parameter MEM_PATH = "C:/Users/User/Desktop/FYP/A_FYP/Bilibili_Ref/Single_Cycle/Codes/Phase5/instr.mem"
)(
    input  wire         clk_n,
    input  wire         rst_n,

    // Port A: instruction fetch 
    input  wire [14:0]  addr_a_i,
    output wire [31:0]  rd_data_a_o,

    // Port B: data constant read (synchronous read)
    input  wire [14:0]  addr_b_i,
    output reg  [31:0]  rd_data_b_o
);

    // 32 K words = 128 KB address space
    reg [31:0] array [0:32767];

    initial begin
        $readmemh(MEM_PATH, array);
    end

    reg [31:0] rd_data_a_reg;
    assign rd_data_a_o = rd_data_a_reg;

    always @(negedge clk_n) begin
        rd_data_a_reg <= array[addr_a_i];
    end

    // Port B: synchronous
    always @(posedge clk_n) begin
        rd_data_b_o <= array[addr_b_i];
    end

endmodule