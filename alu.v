`timescale 1ns/1ps
module alu (
    input  wire [31:0] src1,      
    input  wire [31:0] src2,        
    input  wire [19:0] imm20,       
    input  wire [31:0] pc,          
    input  wire [3:0]  op,          
    output reg  [31:0] alu_result,  
    output wire       zero         
);

    localparam ALU_ADD      = 4'd0;
    localparam ALU_SUB      = 4'd1;
    localparam ALU_SLT      = 4'd2;
    localparam ALU_AND      = 4'd3;
    localparam ALU_OR       = 4'd4;
    localparam ALU_XOR      = 4'd5;
    localparam ALU_SLL      = 4'd6;
    localparam ALU_SRL      = 4'd7;
    localparam ALU_LU12I    = 4'd8;
    localparam ALU_PCADDU12I= 4'd9;
    localparam ALU_MUL      = 4'd10;
    localparam ALU_CPUCGF   = 4'd11;


    function [31:0] cpucfg_val;
        input [4:0] idx;
        begin
            cpucfg_val = 32'h0;
        end
    endfunction

    reg [63:0] mul_tmp;
    always @(*) begin
        mul_tmp = $signed(src1) * $signed(src2);  
        case (op)
            ALU_ADD:       alu_result = src1 + src2;
            ALU_SUB:       alu_result = src1 - src2;
            ALU_SLT:       alu_result = ($signed(src1) < $signed(src2)) ? 32'h1 : 32'h0;
            ALU_AND:       alu_result = src1 & src2;
            ALU_OR:        alu_result = src1 | src2;
            ALU_XOR:       alu_result = src1 ^ src2;
            ALU_SLL:       alu_result = src1 << src2[4:0];
            ALU_SRL:       alu_result = src1 >> src2[4:0];
            ALU_LU12I:     alu_result = {imm20, 12'b0};
            ALU_PCADDU12I: alu_result = pc + {{4{imm20[19]}}, imm20, 12'b0};
            ALU_MUL:       alu_result = mul_tmp[31:0];
            ALU_CPUCGF:    alu_result = cpucfg_val(src1[4:0]);
            default:       alu_result = 32'h0;
        endcase
    end

    assign zero = (alu_result == 32'b0);

endmodule