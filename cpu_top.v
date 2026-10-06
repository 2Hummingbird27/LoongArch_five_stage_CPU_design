`timescale 1ns/1ps
module cpu_top (
    input  wire        clk,
    input  wire        rst,

    output wire [31:0] imem_addr,
    output wire        imem_en,
    input  wire [31:0] imem_data,
 
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire        dmem_en,
    output wire        dmem_we,
    output wire [3:0]  dmem_wstrb,
    input  wire [31:0] dmem_rdata,
    //调试信号
    output wire [4:0]  dbg_wb_rd,
    output wire [31:0] dbg_wb_data,
    output wire        dbg_wb_en
);

    wire [31:0] pc_out;
    wire [31:0] inst_out;
    wire        stall_all;
    wire        branch_taken;
    wire [31:0] branch_target;

    //IF/ID流水寄存器
    reg  [31:0] pc_id;
    reg  [31:0] inst_id;

    //ID级输出
    wire [31:0] alu_src1;
    wire [31:0] alu_src2;
    wire [31:0] st_wdata;
    wire [4:0]  src1_regnum;
    wire [4:0]  src2_regnum;
    wire [4:0]  st_src_regnum;
    wire [4:0]  rd_id;
    wire [19:0] imm20;
    wire [15:0] offs16;
    wire [25:0] offs26;
    wire [3:0]  alu_op;
    wire        b;
    wire        bl;
    wire        beq;
    wire        bne;
    wire        jirl;
    wire        ld_b;
    wire        st_b;
    wire        write_en;
    wire        mem_read;
    wire        mem_write;
    wire        wb_is_byte;
    wire [1:0]  wb_sel;

    //ID/EX流水寄存器
    reg  [31:0] de_alu_src1, de_alu_src2, de_st_wdata, de_pc;
    reg  [4:0]  de_src1_regnum, de_src2_regnum, de_st_src_regnum, de_rd;
    reg  [19:0] de_imm20;
    reg  [15:0] de_offs16;
    reg  [25:0] de_offs26;
    reg  [3:0]  de_alu_op;
    reg         de_b, de_bl, de_beq, de_bne, de_jirl, de_st_b;
    reg         de_mem_read, de_mem_write, de_write_en, de_wb_is_byte;
    reg  [1:0]  de_wb_sel;

    //EXE级输出
    wire [31:0] alu_result, st_data_out, link_out;
    wire        exe_mem_read, exe_mem_write, exe_write_en, exe_wb_is_byte;
    wire [1:0]  exe_wb_sel;

    //EX/MEM流水寄存器
    reg  [31:0] em_alu_result, em_st_wdata, em_link;
    reg  [4:0]  em_rd;
    reg         em_mem_read, em_mem_write, em_write_en, em_wb_is_byte, em_st_b;
    reg  [1:0]  em_wb_sel;

    //MEM级输出
    wire [31:0] mem_rdata;

    //MEM/WB流水寄存器
    reg  [31:0] mw_alu_result;
    reg  [31:0] mw_mem_rdata;
    reg  [31:0] mw_link;
    reg  [4:0]  mw_rd;
    reg         mw_write_en;
    reg  [1:0]  mw_wb_sel;

    //WB
    wire [31:0] rd_data_wb;
    wire        write_wb_en;
    wire [4:0]  rd_addr_wb;

    // ============ 阶段例化 ============
    if_stage u_if (
        .clk(clk), 
        .rst(rst), 
        .stall(stall_all),
        .branch_taken(branch_taken), 
        .branch_target(branch_target),
        .pc_out(pc_out), 
        .imem_addr(imem_addr), 
        .imem_en(imem_en),
        .imem_data(imem_data), 
        .inst_out(inst_out)
    );

    id_stage u_id (
        .clk(clk), 
        .rst(rst), 
        .inst_id(inst_id), 
        .pc_id(pc_id),
        .write_wb_en(write_wb_en), 
        .rd_addr_wb(rd_addr_wb), 
        .rd_data_wb(rd_data_wb),
        .alu_src1(alu_src1), 
        .src1_regnum(src1_regnum),
        .alu_src2(alu_src2), 
        .src2_regnum(src2_regnum),
        .st_wdata(st_wdata), 
        .st_src_regnum(st_src_regnum),
        .rd_id(rd_id), 
        .imm20(imm20), 
        .offs16(offs16), 
        .offs26(offs26),
        .alu_op(alu_op), 
        .ld_b(ld_b), 
        .st_b(st_b),
        .b(b), 
        .bl(bl), 
        .beq(beq), 
        .bne(bne), 
        .jirl(jirl),
        .write_en(write_en), 
        .mem_read(mem_read), 
        .mem_write(mem_write),
        .wb_sel(wb_sel), 
        .wb_is_byte(wb_is_byte)
    );

    exe_stage u_exe (
        .alu_src1(de_alu_src1), 
        .src1_regnum(de_src1_regnum),
        .alu_src2(de_alu_src2), 
        .src2_regnum(de_src2_regnum),
        .st_wdata(de_st_wdata), 
        .st_src_regnum(de_st_src_regnum),
        .rd_exe(de_rd), 
        .imm20(de_imm20),
        .alu_op(de_alu_op),
        .b(de_b), 
        .bl(de_bl), 
        .beq(de_beq), 
        .bne(de_bne), 
        .jirl(de_jirl),
        .mem_read(de_mem_read),
        .mem_write(de_mem_write),
        .write_en(de_write_en), 
        .wb_sel(de_wb_sel), 
        .wb_is_byte(de_wb_is_byte),
        .offs16(de_offs16), 
        .offs26(de_offs26), 
        .pc_exe(de_pc),
        // 转发源：EX/MEM
        .exmem_result(em_alu_result), 
        .rd_mem(em_rd),
        .write_en_mem(em_write_en), 
        .mem_read_mem(em_mem_read),
        // 转发源：MEM/WB
        .memwb_data(rd_data_wb), 
        .rd_wb(rd_addr_wb), 
        .write_en_wb(write_wb_en),
        .alu_result(alu_result), 
        .st_data_out(st_data_out), 
        .link_out(link_out),
        .branch_taken(branch_taken), 
        .branch_target(branch_target),
        .mem_read_out(exe_mem_read), 
        .mem_write_out(exe_mem_write),
        .write_en_out(exe_write_en), 
        .wb_sel_out(exe_wb_sel), 
        .wb_is_byte_out(exe_wb_is_byte)
    );

    mem_stage u_mem (
        .alu_result_mem(em_alu_result), 
        .st_wdata_mem(em_st_wdata),
        .mem_read_r(em_mem_read), 
        .mem_write_r(em_mem_write),
        .st_b_mem(em_st_b), 
        .wb_is_byte_mem(em_wb_is_byte),
        .dmem_rdata(dmem_rdata),
        .dmem_addr(dmem_addr), 
        .dmem_wdata(dmem_wdata),
        .dmem_en(dmem_en), 
        .dmem_we(dmem_we), 
        .dmem_wstrb(dmem_wstrb),
        .mem_rdata_out(mem_rdata)
    );

    wb_stage u_wb (
        .alu_result_wb(mw_alu_result), 
        .mem_rdata_wb(mw_mem_rdata), 
        .link_wb(mw_link),
        .wb_sel_wb(mw_wb_sel), 
        .write_en_wb(mw_write_en), 
        .rd_wb(mw_rd),
        .rd_data_wb(rd_data_wb), 
        .write_wb_en(write_wb_en), 
        .rd_addr_wb(rd_addr_wb)
    );

    //load/use
    wire load_use =
        de_mem_read && (de_rd != 5'b0) &&
        ((de_rd == src1_regnum) || (de_rd == src2_regnum) || (de_rd == st_src_regnum));
    assign stall_all = load_use;

    //IF/ID
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc_id  <= 32'h0;
            inst_id<= 32'h0;
        end else if (branch_taken) begin
            pc_id  <= 32'h0;
            inst_id<= 32'h0;
        end else if (stall_all) begin
            pc_id  <= pc_id;
            inst_id<= inst_id;
        end else begin
            pc_id  <= pc_out;
            inst_id<= inst_out;
        end
    end

    //ID/EX
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            de_alu_src1 <= 32'h0; 
            de_alu_src2 <= 32'h0; 
            de_st_wdata <= 32'h0; 
            de_pc <= 32'h0;
            de_src1_regnum <= 5'b0; 
            de_src2_regnum <= 5'b0; 
            de_st_src_regnum <= 5'b0; 
            de_rd <= 5'b0;
            de_imm20 <= 20'h0; 
            de_offs16 <= 16'h0; 
            de_offs26 <= 26'h0;
            de_alu_op <= 4'b0;
            de_b<=0; 
            de_bl<=0; 
            de_beq<=0; 
            de_bne<=0; 
            de_jirl<=0; 
            de_st_b<=0;
            de_mem_read<=0; 
            de_mem_write<=0; 
            de_write_en<=0; 
            de_wb_is_byte<=0; 
            de_wb_sel<=2'b0;
        end else if (branch_taken || stall_all) begin
            de_alu_src1 <= 32'h0; 
            de_alu_src2 <= 32'h0; 
            de_st_wdata <= 32'h0;
            de_pc <= 32'h0;
            de_src1_regnum <= 5'b0; 
            de_src2_regnum <= 5'b0; 
            de_st_src_regnum <= 5'b0; 
            de_rd <= 5'b0;
            de_imm20 <= 20'h0; 
            de_offs16 <= 16'h0; 
            de_offs26 <= 26'h0;
            de_alu_op <= 4'b0;
            de_b<=0; 
            de_bl<=0; 
            de_beq<=0; 
            de_bne<=0; 
            de_jirl<=0; 
            de_st_b<=0;
            de_mem_read<=0; 
            de_mem_write<=0; 
            de_write_en<=0; 
            de_wb_is_byte<=0; 
            de_wb_sel<=2'b0;
        end else begin
            de_alu_src1 <= alu_src1; 
            de_alu_src2 <= alu_src2; 
            de_st_wdata <= st_wdata; 
            de_pc <= pc_id;
            de_src1_regnum <= src1_regnum; 
            de_src2_regnum <= src2_regnum;
            de_st_src_regnum <= st_src_regnum; 
            de_rd <= rd_id;
            de_imm20 <= imm20; 
            de_offs16 <= offs16; 
            de_offs26 <= offs26;
            de_alu_op <= alu_op;
            de_b<=b; 
            de_bl<=bl; 
            de_beq<=beq; 
            de_bne<=bne; 
            de_jirl<=jirl; 
            de_st_b<=st_b;
            de_mem_read<=mem_read; 
            de_mem_write<=mem_write; 
            de_write_en<=write_en;
            de_wb_is_byte<=wb_is_byte; 
            de_wb_sel<=wb_sel;
        end
    end

    //EX/MEM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            em_alu_result <= 32'h0; 
            em_st_wdata <= 32'h0; 
            em_link <= 32'h0; 
            em_rd <= 5'b0;
            em_mem_read<=0; 
            em_mem_write<=0; 
            em_write_en<=0; 
            em_wb_is_byte<=0; 
            em_st_b<=0; 
            em_wb_sel<=2'b0;
        end else begin
            em_alu_result <= alu_result; 
            em_st_wdata <= st_data_out; 
            em_link <= link_out; 
            em_rd <= de_rd;
            em_mem_read <= exe_mem_read; 
            em_mem_write <= exe_mem_write;
            em_write_en <= exe_write_en; 
            em_wb_is_byte <= exe_wb_is_byte;
            em_st_b <= de_st_b; 
            em_wb_sel <= exe_wb_sel;
        end
    end

    //MEM/WB
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mw_alu_result <= 32'h0; 
            mw_mem_rdata <= 32'h0; 
            mw_link <= 32'h0; 
            mw_rd <= 5'b0;
            mw_write_en<=0; 
            mw_wb_sel<=2'b0;
        end else begin
            mw_alu_result <= em_alu_result; 
            mw_mem_rdata <= mem_rdata;
            mw_link <= em_link;
            mw_rd <= em_rd; 
            mw_write_en <= em_write_en; 
            mw_wb_sel <= em_wb_sel;
        end
    end

    //调试端口
    assign dbg_wb_rd   = rd_addr_wb;
    assign dbg_wb_data = rd_data_wb;
    assign dbg_wb_en   = write_wb_en;

endmodule