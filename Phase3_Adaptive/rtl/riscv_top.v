// =============================================================================
// riscv_top.v  —  Adaptive 3/5-stage RISC-V pipeline core
// =============================================================================

module riscv_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] instr,
    input  wire [31:0] mem_read_data,
    output wire [31:0] pc_out,
    output wire [31:0] mem_write_data,
    output wire [31:0] alu_result_out,
    output wire        mem_write_en,
    output wire [2:0]  funct3_out,
    output wire        test_finished,
    output wire        clk_sel
);

    // =========================================================================
    // 0. INTERNAL DECLARATIONS (Strictly Declared Before Use)
    // =========================================================================
    
    // Global & Status Wires
    wire        stall;
    wire        master_stall;
    wire        flush;
    wire        pipeline_mode;
    wire        is_valid_instr;
    wire        instr_retired_final;

    // FSM Registers
    reg  [3:0]  switch_counter;
    reg         clk_sel_reg;
    reg         pipeline_mode_active;
    reg         fsm_stall;
    reg  [1:0]  switch_state;

    // IF Stage Wires
    wire [31:0] if_pc_plus4;
    wire [31:0] if_pc_next;

    // ID Stage Wires & Registers
    wire [31:0] id_pc;
    wire [31:0] id_instr;
    wire [31:0] id_rs1_data;
    wire [31:0] id_rs2_data;
    wire [31:0] id_imm;
    wire [1:0]  id_alu_op;
    wire        id_reg_write;
    wire        id_alu_src;
    wire        id_mem_to_reg;
    wire        id_mem_write;
    wire        id_branch;
    wire        id_jal_sel;
    wire        id_jalr_sel;
    wire        id_csr_we;
    wire        id_test_finished;

    // EX Stage Wires
    wire [31:0] ex_pc;
    wire [31:0] ex_instr;
    wire [31:0] ex_rs1_data;
    wire [31:0] ex_rs2_data;
    wire [31:0] ex_imm;
    wire [31:0] ex_alu_a;
    wire [31:0] ex_alu_b;
    wire [31:0] ex_alu_res;
    wire [31:0] ex_branch_target;
    wire [31:0] ex_jalr_target;
    wire [31:0] ex_csr_rdata;
    wire [31:0] ex_rs1_forwarded;
    wire [31:0] ex_rs2_forwarded;
    wire [31:0] iso_alu_a;
    wire [31:0] iso_alu_b;
    wire [31:0] ex_pc_plus4;
    wire [4:0]  ex_alu_ctrl;
    wire [4:0]  ex_rd_addr;
    wire [4:0]  ex_rs1_addr;
    wire [4:0]  ex_rs2_addr;
    wire [4:0]  iso_alu_ctrl;
    wire [1:0]  ex_alu_op;
    wire [1:0]  forward_a;
    wire [1:0]  forward_b;
    wire        ex_reg_write;
    wire        ex_alu_src;
    wire        ex_mem_to_reg;
    wire        ex_mem_write;
    wire        ex_csr_we;
    wire        ex_jal_sel;
    wire        ex_jalr_sel;
    wire        ex_branch_eq;
    wire        ex_branch_lt;
    wire        ex_branch;
    wire        ex_alu_active;
    reg         ex_take_branch;

    // Write-Buffer Barrier Registers (The _q Registers)
    reg  [31:0] ex_alu_res_q;
    reg  [4:0]  ex_rd_addr_q;
    reg         ex_reg_write_q;
    reg         ex_mem_to_reg_q;
    reg         ex_mem_write_q;
    reg         ex_csr_we_q;
    reg         ex_jal_sel_q;
    reg         ex_jalr_sel_q;
    reg  [31:0] ex_rs2_forwarded_q;
    reg  [2:0]  ex_funct3_q;
    reg  [31:0] ex_csr_rdata_q;
    reg  [31:0] ex_pc_plus4_q;

    // MEM Stage Wires
    wire [31:0] mem_alu_res;
    wire [31:0] mem_rs2_data;
    wire [31:0] mem_csr_rdata;
    wire [31:0] mem_pc_plus4;
    wire [15:0] mem_half_data;
    wire [7:0]  mem_byte_data;
    wire [4:0]  mem_rd_addr;
    wire [2:0]  mem_funct3;
    wire        mem_reg_write;
    wire        mem_mem_to_reg;
    wire        mem_mem_write;
    wire        mem_csr_we;
    wire        mem_jal_sel;
    wire        mem_jalr_sel;
    reg  [31:0] mem_to_reg_data;

    // WB Stage Wires
    wire [31:0] wb_read_data;
    wire [31:0] wb_alu_res;
    wire [31:0] wb_csr_rdata;
    wire [31:0] wb_pc_plus4;
    wire [31:0] wb_forward_data;
    wire [4:0]  wb_rd_addr;
    wire        wb_reg_write;
    wire        wb_mem_to_reg;
    wire        wb_csr_we;
    wire        wb_jal_sel;
    wire        wb_jalr_sel;

    // Adaptive Effective Routing Wires
    wire [31:0] eff_mem_alu_res;
    wire [31:0] eff_mem_rs2_data;
    wire [2:0]  eff_mem_funct3;
    wire [31:0] mem_forward_data;
    wire [31:0] eff_mem_forward_data;

    // Final WB Bus Wires & Regs
    reg  [31:0] final_reg_write_data;
    wire [4:0]  final_reg_write_addr;
    wire        final_reg_write_en;

    // Test Finished Propagation
    reg         ex_test_finished_id_reg;
    wire        ex_test_finished;
    reg         ex_test_finished_reg;
    wire        mem_test_finished;
    reg         wb_test_finished_reg;
    wire        wb_test_finished;


    // =========================================================================
    // 1. CLOCK-SWITCH FSM
    // =========================================================================
    localparam ST_RUNNING    = 2'b00;
    localparam ST_FLUSH_PIPE = 2'b01;
    localparam ST_SWITCH_CLK = 2'b10;
    localparam ST_SETTLE_DLY = 2'b11;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            switch_state         <= ST_RUNNING;
            clk_sel_reg          <= 1'b1;
            pipeline_mode_active <= 1'b1;
            switch_counter       <= 4'b0;
            fsm_stall            <= 1'b0;
        end else begin
            case (switch_state)
                ST_RUNNING: begin
                    fsm_stall <= 1'b0;
                    if (pipeline_mode != pipeline_mode_active) begin
                        switch_state <= ST_FLUSH_PIPE;
                        fsm_stall    <= 1'b1;
                    end
                end
                ST_FLUSH_PIPE: begin
                    fsm_stall    <= 1'b1;
                    switch_state <= ST_SWITCH_CLK;
                end
                ST_SWITCH_CLK: begin
                    fsm_stall            <= 1'b1;
                    clk_sel_reg          <= pipeline_mode;
                    pipeline_mode_active <= pipeline_mode;
                    switch_counter       <= 4'b0;
                    switch_state         <= ST_SETTLE_DLY;
                end
                ST_SETTLE_DLY: begin
                    fsm_stall <= 1'b1;
                    if (switch_counter == 4'd15) begin
                        switch_state <= ST_RUNNING;
                        fsm_stall    <= 1'b0;
                    end else begin
                        switch_counter <= switch_counter + 1'b1;
                    end
                end
                default: switch_state <= ST_RUNNING;
            endcase
        end
    end

    assign master_stall = stall || fsm_stall;


    // =========================================================================
    // 2. STAGE 1: INSTRUCTION FETCH (IF)
    // =========================================================================
    assign if_pc_plus4 = pc_out + 4;

    assign if_pc_next = (ex_jalr_sel === 1'b1)                                                      ? ex_jalr_target    :
                        (ex_jal_sel  === 1'b1 || (ex_branch === 1'b1 && ex_take_branch === 1'b1))   ? ex_branch_target  :
                         if_pc_plus4 ;

    assign flush = (ex_jal_sel === 1'b1 || ex_jalr_sel === 1'b1 || (ex_branch === 1'b1 && ex_take_branch === 1'b1));

    pc unit_pc (
        .clk     (clk),
        .rst_n   (rst_n),
        .stall   (master_stall),
        .pc_next (if_pc_next),
        .pc_out  (pc_out)
    );


    // =========================================================================
    // 3. PIPELINE REGISTER: IF / ID
    // =========================================================================
    reg_if_id unit_if_id (
        .clk      (clk),
        .rst_n    (rst_n),
        .stall    (master_stall),
        .flush    (flush),
        .if_pc    (pc_out),
        .if_instr (instr),
        .id_pc    (id_pc),
        .id_instr (id_instr)
    );


    // =========================================================================
    // 4. STAGE 2: INSTRUCTION DECODE (ID)
    // =========================================================================
    hazard_detection_unit unit_hazard (
        .id_rs1_addr  (id_instr[19:15]),
        .id_rs2_addr  (id_instr[24:20]),
        .ex_rd_addr   (ex_rd_addr),
        .ex_mem_read  (ex_mem_to_reg),
        .stall        (stall)
    );

    control_unit unit_control (
        .instr          (id_instr),
        .opcode         (id_instr[6:0]),
        .pipeline_mode  (pipeline_mode),
        .reg_write      (id_reg_write),
        .alu_src        (id_alu_src),
        .mem_to_reg     (id_mem_to_reg),
        .mem_write      (id_mem_write),
        .branch         (id_branch),
        .jal_sel        (id_jal_sel),
        .jalr_sel       (id_jalr_sel),
        .csr_we         (id_csr_we),
        .alu_op         (id_alu_op),
        .test_finished  (id_test_finished)
    );

    imm_gen unit_immgen (
        .instr   (id_instr),
        .imm_out (id_imm)
    );

    
    register_file unit_regfile (
        .clk          (clk),
        .reg_write_en (final_reg_write_en),
        .rs1_addr     (id_instr[19:15]),
        .rs2_addr     (id_instr[24:20]),
        .rd_addr      (final_reg_write_addr),
        .write_data   (final_reg_write_data),
        .rs1_data     (id_rs1_data),
        .rs2_data     (id_rs2_data)
    );


    // =========================================================================
    // 5. PIPELINE REGISTER: ID / EX
    // =========================================================================
    reg_id_ex unit_id_ex (
        .clk           (clk),
        .rst_n         (rst_n),
        .flush         (flush),
        .id_pc         (id_pc),
        .id_instr      (id_instr),
        .id_reg_write  (id_reg_write),
        .id_alu_src    (id_alu_src),
        .id_mem_to_reg (id_mem_to_reg),
        .id_mem_write  (id_mem_write),
        .id_alu_op     (id_alu_op),
        .id_csr_we     (id_csr_we),
        .id_rs1_data   (id_rs1_data),
        .id_rs2_data   (id_rs2_data),
        .id_imm        (id_imm),
        .id_rd_addr    (id_instr[11:7]),
        .id_rs1_addr   (id_instr[19:15]),
        .id_rs2_addr   (id_instr[24:20]),
        .id_branch     (id_branch),
        .id_jal_sel    (id_jal_sel),
        .id_jalr_sel   (id_jalr_sel),
        
        .ex_pc         (ex_pc),
        .ex_instr      (ex_instr),
        .ex_reg_write  (ex_reg_write),
        .ex_alu_src    (ex_alu_src),
        .ex_mem_to_reg (ex_mem_to_reg),
        .ex_mem_write  (ex_mem_write),
        .ex_alu_op     (ex_alu_op),
        .ex_csr_we     (ex_csr_we),
        .ex_rs1_data   (ex_rs1_data),
        .ex_rs2_data   (ex_rs2_data),
        .ex_imm        (ex_imm),
        .ex_rd_addr    (ex_rd_addr),
        .ex_rs1_addr   (ex_rs1_addr),
        .ex_rs2_addr   (ex_rs2_addr),
        .ex_branch     (ex_branch),
        .ex_jal_sel    (ex_jal_sel),
        .ex_jalr_sel   (ex_jalr_sel)
    );


    // =========================================================================
    // 6. STAGE 3: EXECUTE (EX)
    // =========================================================================

    forwarding_unit unit_forwarding (
        .ex_rs1_addr   (ex_rs1_addr),
        .ex_rs2_addr   (ex_rs2_addr),
        .mem_rd_addr   (mem_rd_addr),
        .mem_reg_write (mem_reg_write),
        .wb_rd_addr    (wb_rd_addr),
        .wb_reg_write  (wb_reg_write),
        .pipeline_mode (pipeline_mode),
        .forward_a     (forward_a),
        .forward_b     (forward_b)
    );

    assign ex_rs1_forwarded =
        (forward_a == 2'b10) ? eff_mem_forward_data :
        (forward_a == 2'b01) ? wb_forward_data       :
                               ex_rs1_data;

    assign ex_rs2_forwarded =
        (forward_b == 2'b10) ? eff_mem_forward_data :
        (forward_b == 2'b01) ? wb_forward_data       :
                               ex_rs2_data;

    // --- ALU & Logic ---
    assign ex_pc_plus4 = ex_pc + 4;
    assign ex_branch_target = ex_pc + ex_imm;
    assign ex_jalr_target   = ex_alu_res & ~32'b1;

    alu_control unit_alucontrol (
        .alu_op      (ex_alu_op),
        .funct3      (ex_instr[14:12]),
        .funct7_bit  (ex_instr[30]),
        .opcode_6_4  (ex_instr[6:4]),
        .alu_control (ex_alu_ctrl)
    );
 
    assign ex_alu_a = (ex_instr[6:0] == 7'b0010111 || ex_instr[6:0] == 7'b1101111)   ? ex_pc          :
                       (ex_instr[6:0] == 7'b0110111)                                 ? 32'b0          :
                                                                                       ex_rs1_forwarded;

    assign ex_alu_b = ex_alu_src ? ex_imm : ex_rs2_forwarded;

    assign ex_alu_active = ((ex_instr[6:0] == 7'b0110011) ||
                            (ex_instr[6:0] == 7'b0010011) ||
                            (ex_instr[6:0] == 7'b0110111) ||
                            (ex_instr[6:0] == 7'b0010111) ||
                            (ex_instr[6:0] == 7'b0000011) ||
                            (ex_instr[6:0] == 7'b0100011) ||
                            (ex_instr[6:0] == 7'b1100011) ||
                            (ex_instr[6:0] == 7'b1100111) ||
                            (ex_instr[6:0] == 7'b1101111) ||
                            (ex_instr[6:0] == 7'b1110011)) && (ex_instr != 32'h0000_0013);

    assign iso_alu_a    = ex_alu_active ? ex_alu_a    : 32'b0;
    assign iso_alu_b    = ex_alu_active ? ex_alu_b    : 32'b0;
    assign iso_alu_ctrl = ex_alu_active ? ex_alu_ctrl : 5'b11111;

    alu unit_alu (
        .a           (iso_alu_a),
        .b           (iso_alu_b),
        .alu_control (iso_alu_ctrl),
        .alu_result  (ex_alu_res)
    );

    branch_comp unit_branch_comp (
        .data_a      (ex_rs1_forwarded),
        .data_b      (ex_rs2_forwarded),
        .br_unsigned (ex_instr[13]),
        .branch_eq   (ex_branch_eq),
        .branch_lt   (ex_branch_lt)
    );

    always @(*) begin
        case (ex_instr[14:12])
            3'b000: ex_take_branch =  ex_branch_eq;
            3'b001: ex_take_branch = !ex_branch_eq;
            3'b100: ex_take_branch =  ex_branch_lt;
            3'b101: ex_take_branch = !ex_branch_lt;
            3'b110: ex_take_branch =  ex_branch_lt;
            3'b111: ex_take_branch = !ex_branch_lt;
            default: ex_take_branch = 1'b0;
        endcase
    end

    csr_unit unit_csr (
        .clk           (clk),
        .rst_n         (rst_n),
        .csr_addr      (ex_instr[31:20]),
        .csr_wdata     (ex_rs1_forwarded),
        .csr_we        (ex_csr_we),
        .csr_op        (ex_instr[14:12]),
        .instr_retired (instr_retired_final),
        .pipeline_mode (pipeline_mode),
        .csr_rdata     (ex_csr_rdata)
    );


    // =========================================================================
    // 7. THE 3-STAGE WRITE-BUFFER BARRIER (Pseudo-4th-Stage _q Registers)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_alu_res_q       <= 32'b0;
            ex_csr_rdata_q     <= 32'b0;
            ex_rs2_forwarded_q <= 32'b0;
            ex_pc_plus4_q      <= 32'b0;
            ex_rd_addr_q       <= 5'b0;
            ex_funct3_q        <= 3'b0;
            ex_reg_write_q     <= 1'b0;
            ex_mem_to_reg_q    <= 1'b0;
            ex_mem_write_q     <= 1'b0;
            ex_csr_we_q        <= 1'b0;
            ex_jal_sel_q       <= 1'b0;
            ex_jalr_sel_q      <= 1'b0;
        end else begin
            ex_alu_res_q       <= ex_alu_res;
            ex_rd_addr_q       <= ex_rd_addr;
            ex_reg_write_q     <= ex_reg_write;
            ex_mem_to_reg_q    <= ex_mem_to_reg;
            ex_mem_write_q     <= ex_mem_write;
            ex_csr_we_q        <= ex_csr_we;
            ex_jal_sel_q       <= ex_jal_sel;
            ex_jalr_sel_q      <= ex_jalr_sel;
            ex_rs2_forwarded_q <= ex_rs2_forwarded;
            ex_funct3_q        <= ex_instr[14:12];
            ex_csr_rdata_q     <= ex_csr_rdata;
            ex_pc_plus4_q      <= ex_pc_plus4;
        end
    end


    // =========================================================================
    // 8. PIPELINE REGISTER: EX / MEM (Active only in 5-Stage Mode)
    // =========================================================================
    reg_ex_mem unit_ex_mem (
        .clk            (clk),
        .rst_n          (rst_n),
        .pipeline_mode  (pipeline_mode),
        .ex_reg_write   (ex_reg_write),
        .ex_mem_to_reg  (ex_mem_to_reg),
        .ex_mem_write   (ex_mem_write),
        .ex_csr_we      (ex_csr_we),
        .ex_funct3      (ex_instr[14:12]),
        .ex_alu_result  (ex_alu_res),
        .ex_rs2_data    (ex_rs2_forwarded),
        .ex_csr_rdata   (ex_csr_rdata),
        .ex_pc_plus4    (ex_pc_plus4),
        .ex_jal_sel     (ex_jal_sel),
        .ex_jalr_sel    (ex_jalr_sel),
        .ex_rd_addr     (ex_rd_addr),
        
        .mem_reg_write  (mem_reg_write),
        .mem_mem_to_reg (mem_mem_to_reg),
        .mem_mem_write  (mem_mem_write),
        .mem_csr_we     (mem_csr_we),
        .mem_funct3     (mem_funct3),
        .mem_alu_result (mem_alu_res),
        .mem_rs2_data   (mem_rs2_data),
        .mem_csr_rdata  (mem_csr_rdata),
        .mem_rd_addr    (mem_rd_addr),
        .mem_pc_plus4   (mem_pc_plus4),
        .mem_jal_sel    (mem_jal_sel),
        .mem_jalr_sel   (mem_jalr_sel)
    );


    // =========================================================================
    // 9. STAGE 4: MEMORY (MEM) & ADAPTIVE ROUTING
    // =========================================================================

    assign mem_forward_data = mem_csr_we                      ? mem_csr_rdata   :
                              mem_mem_to_reg                  ? mem_to_reg_data :
                              (mem_jal_sel || mem_jalr_sel)   ? mem_pc_plus4    :
                                                                mem_alu_res     ;

    assign eff_mem_forward_data = pipeline_mode                     ? mem_forward_data  : (
                                  ex_csr_we_q                       ? ex_csr_rdata_q    :
                                  ex_mem_to_reg_q                   ? mem_to_reg_data   :
                                  (ex_jal_sel_q || ex_jalr_sel_q)   ? ex_pc_plus4_q     :
                                                                      ex_alu_res_q   );
    
    // Adaptive effective assignments
    assign eff_mem_alu_res    = pipeline_mode ? mem_alu_res      : ex_alu_res_q;
    assign eff_mem_rs2_data   = pipeline_mode ? mem_rs2_data     : ex_rs2_forwarded_q;
    assign eff_mem_funct3     = pipeline_mode ? mem_funct3       : ex_funct3_q;

    // Output assignments
    assign mem_write_en   = pipeline_mode ? mem_mem_write  : ex_mem_write_q;
    assign alu_result_out = eff_mem_alu_res;
    assign mem_write_data = eff_mem_rs2_data;
    assign funct3_out     = eff_mem_funct3;

    // Memory Alignment Logic
    assign mem_byte_data =
        (eff_mem_alu_res[1:0] == 2'b00) ? mem_read_data[7:0]   :
        (eff_mem_alu_res[1:0] == 2'b01) ? mem_read_data[15:8]  :
        (eff_mem_alu_res[1:0] == 2'b10) ? mem_read_data[23:16] :
                                           mem_read_data[31:24];

    assign mem_half_data =
        eff_mem_alu_res[1] ? mem_read_data[31:16] : mem_read_data[15:0];

    always @(*) begin
        case (eff_mem_funct3)
            3'b000 : mem_to_reg_data = {{24{mem_byte_data[7]}}, mem_byte_data};
            3'b001 : mem_to_reg_data = {{16{mem_half_data[15]}}, mem_half_data};
            3'b010 : mem_to_reg_data = mem_read_data;
            default: mem_to_reg_data = mem_read_data;
        endcase
    end


    // =========================================================================
    // 10. PIPELINE REGISTER: MEM / WB (Active only in 5-Stage Mode)
    // =========================================================================
    reg_mem_wb unit_mem_wb (
        .clk            (clk),
        .rst_n          (rst_n),
        .pipeline_mode  (pipeline_mode),
        .mem_reg_write  (mem_reg_write),
        .mem_mem_to_reg (mem_mem_to_reg),
        .mem_csr_we     (mem_csr_we),
        .mem_read_data  (mem_to_reg_data),
        .mem_alu_result (mem_alu_res),
        .mem_csr_rdata  (mem_csr_rdata),
        .mem_rd_addr    (mem_rd_addr),
        .mem_pc_plus4   (mem_pc_plus4),
        .mem_jal_sel    (mem_jal_sel),
        .mem_jalr_sel   (mem_jalr_sel),
        
        .wb_reg_write   (wb_reg_write),
        .wb_mem_to_reg  (wb_mem_to_reg),
        .wb_csr_we      (wb_csr_we),
        .wb_read_data   (wb_read_data),
        .wb_alu_result  (wb_alu_res),
        .wb_csr_rdata   (wb_csr_rdata),
        .wb_rd_addr     (wb_rd_addr),
        .wb_pc_plus4    (wb_pc_plus4),
        .wb_jal_sel     (wb_jal_sel),
        .wb_jalr_sel    (wb_jalr_sel)
    );


    // =========================================================================
    // 11. STAGE 5: WRITE-BACK (WB)
    // =========================================================================
    always @(*) begin
        if (pipeline_mode) begin
            // 5-Stage Path (From WB Register)
            final_reg_write_data = wb_forward_data;
        end else begin
            // 3-Stage Path (From _q Register Barrier)
            if      (ex_csr_we_q)                      final_reg_write_data = ex_csr_rdata_q;
            else if (ex_mem_to_reg_q)                  final_reg_write_data = mem_to_reg_data;
            else if (ex_jal_sel_q || ex_jalr_sel_q)    final_reg_write_data = ex_pc_plus4_q;
            else                                       final_reg_write_data = ex_alu_res_q;
        end
    end

    // --- Forwarding Network & Assignments ---
    assign wb_forward_data = wb_csr_we                   ? wb_csr_rdata :
                             wb_mem_to_reg               ? wb_read_data :
                             (wb_jal_sel || wb_jalr_sel) ? wb_pc_plus4  :
                                                           wb_alu_res   ;

    assign final_reg_write_en   = pipeline_mode ? wb_reg_write  : ex_reg_write_q;
    assign final_reg_write_addr = pipeline_mode ? wb_rd_addr    : ex_rd_addr_q;

    // =========================================================================
    // 12. STATUS FLAGS & TEST FINISHED PROPAGATION
    // =========================================================================
    
    // EX to MEM propagation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ex_test_finished_id_reg <= 1'b0;
        else        ex_test_finished_id_reg <= id_test_finished;
    end
    assign ex_test_finished = pipeline_mode ? ex_test_finished_id_reg : id_test_finished;

    // MEM to WB propagation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ex_test_finished_reg <= 1'b0;
        else        ex_test_finished_reg <= ex_test_finished;
    end
    assign mem_test_finished = pipeline_mode ? ex_test_finished_reg : ex_test_finished;

    // Final WB propagation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wb_test_finished_reg <= 1'b0;
        else        wb_test_finished_reg <= mem_test_finished;
    end
    assign wb_test_finished = pipeline_mode ? wb_test_finished_reg : mem_test_finished;

    // Final Top-Level Assignments
    assign is_valid_instr      = (ex_instr != 32'h0000_0013) && (!flush) && (!stall);
    assign instr_retired_final = final_reg_write_en;
    assign test_finished       = wb_test_finished;
    assign clk_sel             = clk_sel_reg;

endmodule