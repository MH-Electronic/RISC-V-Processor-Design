module instr_rom (
    input  wire [9:0]  addr_i, // pc[11:2]
    output wire [31:0] rd_data_o
);

    reg [31:0] mem [0:1023];

    initial begin
        $readmemh("C:/Users/User/Desktop/FYP/A_FYP/Bilibili_Ref/Single_Cycle/Codes/Memory_Initialization/instr.mem", mem);
    end

    assign rd_data_o = mem[addr_i];

endmodule