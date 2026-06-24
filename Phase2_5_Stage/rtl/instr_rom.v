// Dual-Port Instruction ROM (Read-Only Memory) for 32-bit RISC-V Single-Cycle CPU
module instr_rom (
    input  wire [14:0]  addr_a_i, // 4MB address space, word-aligned (20 bits for 1M words)
    output wire [31:0]  rd_data_a_o,

    input  wire [14:0]  addr_b_i,
    output wire [31:0]  rd_data_b_o
);

    // 1,048,576 words * 32-bits = 4,194,304 bytes (4MB)
    reg [31:0] mem [0:32767];

    initial begin
        $readmemh("C:/Users/User/Desktop/FYP/A_FYP/Bilibili_Ref/Single_Cycle/Codes/Phase3/instr.mem", mem);
    end

    // Port A: Instruction Fetch (Read-Only)
    assign rd_data_a_o = mem[addr_a_i];

    // Port B: Data Read (Constants, Read-Only Data)
    assign rd_data_b_o = mem[addr_b_i];

endmodule