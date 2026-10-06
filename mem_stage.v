`timescale 1ns/1ps
module mem_stage (
    input  wire [31:0] alu_result_mem,   // 计算出的地址（EX/MEM）
    input  wire [31:0] st_wdata_mem,     // st 要存的数据（已转发）
    input  wire        mem_read_r,       // 是否读
    input  wire        mem_write_r,      // 是否写
    input  wire        st_b_mem,         // 是否字节写（ST.B）
    input  wire        wb_is_byte_mem,   // 是否字节读（LD.B，需符号扩展）
    input  wire [31:0] dmem_rdata,       // 外部读回的数据

    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire        dmem_en,
    output wire        dmem_we,
    output wire [3:0]  dmem_wstrb,       // 字节写使能

    output wire [31:0] mem_rdata_out     // = dmem_rdata（LD.B 则已符号扩展）
);

    wire [3:0] stb_strb  = 4'b0001 << alu_result_mem[1:0];
    assign dmem_wstrb = mem_write_r ? (st_b_mem ? stb_strb : 4'b1111) : 4'b0000;

    // ST.B 把字节复制到所有通道，配合 wstrb 写入目标字节；ST.W 直接写整字。
    assign dmem_wdata = (mem_write_r && st_b_mem) ? {4{st_wdata_mem[7:0]}} : st_wdata_mem;

    assign dmem_addr = alu_result_mem;
    assign dmem_en   = mem_read_r | mem_write_r;
    assign dmem_we   = mem_write_r;

    wire [7:0] sel_byte = dmem_rdata[8*alu_result_mem[1:0] +: 8];
    assign mem_rdata_out = wb_is_byte_mem ? {{24{sel_byte[7]}}, sel_byte} : dmem_rdata;

endmodule