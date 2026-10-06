`timescale 1ns/1ps
module exe_stage (
    //ID/EX
    input  wire [31:0] alu_src1, 
    input  wire [4 :0] src1_regnum,
    input  wire [31:0] alu_src2, 
    input  wire [4 :0] src2_regnum,
    input  wire [31:0] st_wdata, 
    input  wire [4 :0] st_src_regnum,
    input  wire [4 :0] rd_exe,
    input  wire [19:0] imm20,
    input  wire [3 :0] alu_op,
    input  wire        b, 
    input  wire        bl,
    input  wire        beq, 
    input  wire        bne, 
    input  wire        jirl,
    input  wire        mem_read, 
    input  wire        mem_write, 
    input  wire        write_en,   
    input  wire [1:0]  wb_sel,
    input  wire        wb_is_byte,
    input  wire [15:0] offs16,
    input  wire [25:0] offs26,
    input  wire [31:0] pc_exe,
    //EX/MEM
    input  wire [31:0] exmem_result,
    input  wire [4:0]  rd_mem,
    input  wire        write_en_mem,
    input  wire        mem_read_mem,       // 若是 load，其 exmem_result 只是地址，不能转发
    //MEM/WB
    input  wire [31:0] memwb_data,
    input  wire [4:0]  rd_wb,
    input  wire        write_en_wb,
  
    output wire [31:0] alu_result,
    output wire [31:0] st_data_out,        // 转发后的 st 存数
    output wire [31:0] link_out,           // pc+4（bl/jirl 写回）
    output wire        branch_taken,
    output wire [31:0] branch_target,
    output wire        mem_read_out, 
    output wire        mem_write_out, 
    output wire        write_en_out,
    output wire [1:0]  wb_sel_out,
    output wire        wb_is_byte_out
);

    //数据转发
    wire src1_fm = write_en_mem && (rd_mem != 5'b0) && (~mem_read_mem) && (rd_mem == src1_regnum);
    wire src1_fw = write_en_wb  && (rd_wb  != 5'b0) && (rd_wb  == src1_regnum);
    wire src2_fm = write_en_mem && (rd_mem != 5'b0) && (~mem_read_mem) && (rd_mem == src2_regnum);
    wire src2_fw = write_en_wb  && (rd_wb  != 5'b0) && (rd_wb  == src2_regnum);
    wire stt_fm  = write_en_mem && (rd_mem != 5'b0) && (~mem_read_mem) && (rd_mem == st_src_regnum);
    wire stt_fw  = write_en_wb  && (rd_wb  != 5'b0) && (rd_wb  == st_src_regnum);
    //就近
    wire [31:0] alu_in1     = src1_fm ? exmem_result : (src1_fw ? memwb_data : alu_src1);
    wire [31:0] alu_in2     = src2_fm ? exmem_result : (src2_fw ? memwb_data : alu_src2);
    assign      st_data_out = stt_fm  ? exmem_result : (stt_fw  ? memwb_data : st_wdata);

    //ALU例化
    wire zero;
    alu u_alu (
        .src1      (alu_in1),
        .src2      (alu_in2),
        .imm20     (imm20),
        .pc        (pc_exe),
        .op        (alu_op),
        .alu_result(alu_result),
        .zero      (zero)
    );

    //分支判定与目标
    assign branch_taken = (b | bl | jirl) | (beq & zero) | (bne & ~zero);

    //各类型目标立即数
    wire [31:0] sext_offs16 = {{14{offs16[15]}}, offs16, 2'b0};
    wire [31:0] sext_offs26 = {{4{offs26[25]}}, offs26, 2'b0};

    // jirl 目标 = 转发后的 rj + offs16*4（无 +4）；
    assign branch_target =    jirl     ? (alu_in1 + sext_offs16)
                            : (b | bl) ? (pc_exe + 32'h4 + sext_offs26)
                            :            (pc_exe + 32'h4 + sext_offs16); // beq/bne

    // bl/jirl 链接值 = pc+4
    assign link_out = pc_exe + 32'h4;

    assign mem_read_out   = mem_read;
    assign mem_write_out  = mem_write;
    assign write_en_out   = write_en;
    assign wb_sel_out     = wb_sel;
    assign wb_is_byte_out = wb_is_byte;

endmodule