`timescale 1ns/1ps
module if_stage (
    input  wire       clk,
    input  wire       rst,
    input  wire       stall,            // load-use 停顿时冻结 PC
    input  wire       branch_taken,     // 分支是否跳转（来自 EXE）
    input  wire [31:0] branch_target,   // 分支目标地址（来自 EXE）
    output wire [31:0] pc_out,          // 当前 PC

    output wire [31:0] imem_addr,
    output wire       imem_en,
    input  wire [31:0] imem_data,
    output wire [31:0] inst_out
);

    reg [31:0] pc;
    wire [31:0] pc_plus4;
    wire [31:0] pc_next;

    assign pc_plus4 = pc + 32'd4;

    assign pc_next  = branch_taken ? branch_target : pc_plus4;

    always @(posedge clk or posedge rst) begin
        if (rst)        pc <= 32'h1c000000;   
        else if (stall) pc <= pc;              
        else            pc <= pc_next;
    end

    assign pc_out    = pc;
    assign imem_addr = pc;
    assign imem_en   = 1'b1;           
    assign inst_out  = imem_data;

endmodule