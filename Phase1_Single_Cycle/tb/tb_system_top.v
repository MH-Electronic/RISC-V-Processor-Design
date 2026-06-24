`timescale 1ns/1ps

module tb_system_top;

    reg  clk_in, rst_n;
    wire test_finished;
    wire [7:0] leds;

    // Lattice Primitives
    GSR GSR_INST ( .GSR_N(rst_n), .CLK(clk_in) ); 
    PUR PUR_INST ( .PUR(rst_n) ); 

    system_top u_system (
        .clk_in         (clk_in),
        .rst_n          (rst_n),
        .leds           (leds),
        .test_finished  (test_finished)
    );

    // Clock Generation (125 MHz)
    initial begin
        clk_in = 0;
        forever #4 clk_in = ~clk_in; 
    end

    // Internal Signal Probes (Hierarchy Paths)
    wire [31:0] x1      = u_system.u_core.unit_regfile.registers[1];
    wire [31:0] x3      = u_system.u_core.unit_regfile.registers[3];
    wire [31:0] pc      = u_system.u_core.pc_out;
    wire [31:0] wb_data = u_system.u_core.write_data;
    wire        reg_we  = u_system.u_core.reg_write;
    wire [4:0]  rd_addr = u_system.u_core.instr[11:7];

    // Performance Counters (from CSR)
    wire [31:0] cyc_count = u_system.u_core.unit_csr.mcycle_64[31:0];
    wire [31:0] ins_count = u_system.u_core.unit_csr.minstret_64[31:0];

    // 1. Instruction Tracer
    always @(posedge clk_in) begin
        if (rst_n && reg_we && rd_addr != 0) begin
            $display("[Trace] Time:%t | PC: %h | x%0d <= %h", $time, pc, rd_addr, wb_data);
        end
    end

    // 2. Main Test Controller
    initial begin
        $display("-----------------------------------------------------");
        $display("   STARTING RV32I ARCHITECTURAL COMPLIANCE TEST      ");
        $display("-----------------------------------------------------");
        
        rst_n = 0;
        #100 rst_n = 1;

        // Wait for the "End of Program" Signal
        // In the Assembly test, we will write to a specific address (0x0FFC) to finish
        wait(u_system.mem_write_en && u_system.alu_result_out == 32'h00000FFC);

        #20;
        
        $display("\n-----------------------------------------------------");
        $display("      SIMULATION FINISHED - CHECKING SIGNATURES      ");
        $display("-----------------------------------------------------");

        // --- 3. CPI & Efficiency Metrics ---
        if (ins_count > 0) begin
            $display("Total Cycles       : %d", cyc_count);
            $display("Total Instructions : %d", ins_count);
            $display("Calculated CPI     : %0.2f", $itor(cyc_count)/$itor(ins_count));
        end

        // --- 4. Final Signature Validation ---
        // Example: Check if x1 holds the correct result of our math test
        if (x1 === 32'h12345000) 
            $display("[PASS] LUI: x1 correctly loaded with 0x12345000");
        else 
            $display("[FAIL] LUI: x1 = %h (Expected 12345000)", x1);

        if (x3 === 32'd30)
            $display("[PASS] ADD: x3 correctly calculated 10 + 20 = 30");
        else
            $display("[FAIL] ADD: x3 = %h (Expected 30)", x3);

        $display("=====================================================\n");
        $stop;
    end

    // --- Timeout Watchdog ---
    initial begin
        #50000; // 50us safety timeout
        $display("[ERROR] Simulation Timeout! Program might be in an infinite loop.");
        $finish;
    end

    // Signature Dump Logic (RISCOF Compliance)
    // always @(posedge clk) begin
    //     if (test_finished) begin
    //         $display("Compliance Test Finished. Dumping Signature: %s", signature_file);
            
    //         f = $fopen(signature_file, "w");
    //         if (f == 0) begin
    //             $display("ERROR: Could not open signature file!");
    //             $finish;
    //         end

    //         // We iterate from sig_start to sig_end. 
    //         // IMPORTANT: sig_start and sig_end come from the RISCOF Makefile.
    //         for (i = sig_start; i < sig_end; i = i + 4) begin
    //             // Access memory by Word Address. 
    //             // Since your RAM is [11:2], i[11:2] correctly converts byte address to word index.
    //             $fwrite(f, "%h\n", dut.u_ram.mem[i[11:2]]);
    //         end

    //         $fclose(f);
    //         $display("Signature Dump Complete. Ending Simulation.");
    //         $finish;
    //     end
    // end

endmodule