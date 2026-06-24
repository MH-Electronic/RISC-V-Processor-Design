module branch_comp (
    input  wire [31:0] data_a,
    input  wire [31:0] data_b,
    input  wire        br_unsigned,
    output wire        branch_eq,
    output wire        branch_lt
);

    // Equality Check
    assign branch_eq = (data_a == data_b);

    // Less-Than Check
    assign branch_lt = br_unsigned ? (data_a < data_b) : 
                                     ($signed(data_a) < $signed(data_b));

endmodule