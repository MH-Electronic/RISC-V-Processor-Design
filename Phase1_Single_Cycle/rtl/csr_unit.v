module csr_unit (
    input  wire         clk,
    input  wire         rst_n,

    // Interface from Decode/Execute Stage
    input  wire [11:0]  csr_addr,       // 12-bit CSR address from instruction [31:20]
    input  wire [31:0]  csr_wdata,      // Data to write (from rs1 or zero-extended immediate)
    input  wire         csr_we,         // CSR write enable signal
    input  wire [2:0]   csr_op,         // CSR operation type (funct3: RW=001, RS=010, RC=011)

    // Performance Monitor Signals
    input  wire         instr_retired,  // HIGH if instruction is valid & retired

    // Output to Write-Back Mux
    output reg  [31:0]  csr_rdata       // Data read from CSR to be written back to RegFile
);

    // Internal 64-bit counters
    reg [63:0]  mcycle_64;
    reg [63:0]  minstret_64;

    // Intermediate Logic for Atomic Operations
    reg [31:0]  next_csr_val;

    always @(*) begin
        case (csr_op[1:0])
            2'b01   : next_csr_val = csr_wdata;                 // CSRRW: Write rs1 to CSR
            2'b10   : next_csr_val = csr_rdata | csr_wdata;     // CSRRS: Bitwise OR (Set bits)
            2'b11   : next_csr_val = csr_rdata & ~csr_wdata;    // CSRRC: Bitwise AND NOT (Clear bits)
            default : next_csr_val = csr_rdata; 
        endcase
    end

    // Performance Counter & Write Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mcycle_64   <= 64'b0;
            minstret_64 <= 64'b0;
        end else begin
            // mcycle increments every cycle; minstret increments only on retired instructions
            mcycle_64   <= mcycle_64 + 1'b1;
            if (instr_retired) begin
                minstret_64 <= minstret_64 + 1'b1;
            end

            // Synchronous Write Logic using the calculated next_csr_val
            if (csr_we) begin
                case (csr_addr)
                    12'hB00: mcycle_64[31:0]    <= next_csr_val; // mcycle (lower) 
                    12'hB80: mcycle_64[63:32]   <= next_csr_val; // mcycleh (upper) 
                    12'hB02: minstret_64[31:0]  <= next_csr_val; // minstret (lower) 
                    12'hB82: minstret_64[63:32] <= next_csr_val; // minstreth (upper) 
                    default: ;
                endcase
            end
        end 
    end

    // Synchronous Read Logic
    always @(*) begin
        case (csr_addr)
            12'hB00: csr_rdata = mcycle_64[31:0];       
            12'hB80: csr_rdata = mcycle_64[63:32];      
            12'hB02: csr_rdata = minstret_64[31:0];     
            12'hB82: csr_rdata = minstret_64[63:32];    
            default: csr_rdata = 32'b0; 
        endcase                
    end
    
endmodule
