`timescale 1ns/1ps
module wb_stage (
    input  wire [31:0] alu_result_wb,    // ALU 结果（来自 MEM/WB）
    input  wire [31:0] mem_rdata_wb,     // 内存读回值（LD.B 已符号扩展）
    input  wire [31:0] link_wb,          // 链接值 pc+4（来自 MEM/WB）
    input  wire [1:0]  wb_sel_wb,        // 00=ALU 01=MEM 10=LINK
    input  wire        write_en_wb,
    input  wire [4:0]  rd_wb,
    output wire [31:0] rd_data_wb,
    output wire        write_wb_en,
    output wire [4:0]  rd_addr_wb
);

    assign rd_data_wb  = (wb_sel_wb == 2'b10) ? link_wb
                       : (wb_sel_wb == 2'b01) ? mem_rdata_wb
                       :                        alu_result_wb;
    assign write_wb_en = write_en_wb;
    assign rd_addr_wb  = rd_wb;

endmodule