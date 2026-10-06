`timescale 1ns/1ps
module id_stage (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] inst_id,      
    input  wire [31:0] pc_id,        
    //WB
    input  wire         write_wb_en,
    input  wire [4:0]   rd_addr_wb,
    input  wire [31:0]  rd_data_wb,
    //ID/EX
    output wire [31:0] alu_src1,
    output wire [4:0]  src1_regnum,   
    output wire [31:0] alu_src2,
    output wire [4:0]  src2_regnum,   
    output wire [31:0] st_wdata,     
    output wire [4:0]  st_src_regnum, 
    output wire [4:0]  rd_id,        
    output wire [19:0] imm20,        
    output wire [15:0] offs16,      
    output wire [25:0] offs26,        
    //控制信号
    output wire [3:0]  alu_op,       
    output wire        ld_b, 
    output wire        st_b,    
    output wire        b, 
    output wire        bl, 
    output wire        beq, 
    output wire        bne, 
    output wire        jirl,
    output wire        write_en,      // 是否回写寄存器堆
    output wire        mem_read,      // 是否读内�?
    output wire        mem_write,     // 是否写内�?
    output wire [1:0]  wb_sel,        // 00=ALU 01=MEM 10=LINK
    output wire        wb_is_byte     // 写回 MEM 数据是否�?字节符号扩展（ld.b�?
);

    //ALU 运算�?
    localparam ALU_ADD = 0, ALU_SUB = 1, ALU_SLT = 2, ALU_AND = 3, ALU_OR = 4,
               ALU_XOR = 5, ALU_SLL = 6, ALU_SRL = 7, ALU_LU12I = 8,
               ALU_PCADDU12I = 9, ALU_MUL = 10, ALU_CPUCGF = 11;

    //字段切分
    wire [5:0]  opcode;
    wire [3:0]  opcode_expand;
    wire [6:0]  op2;                  // 2R 族与 2RI 移位族区分位 inst[21:15]
    wire [11:0] imm12;
    wire [4:0]  rd, rj, rk;
    wire        lu12i_w;
    wire        pcaddu12i;
    wire        cpucfg;
    wire        ld_w;
    wire        st_w;   // 直接 assign 的目标指令信�?

    assign opcode        = inst_id[31:26];
    assign opcode_expand = inst_id[25:22];
    assign op2           = inst_id[21:15];
    assign imm20         = inst_id[24:5];
    assign imm12         = inst_id[21:10];
    assign rd            = inst_id[4:0];
    assign rj            = inst_id[9:5];
    assign rk            = inst_id[14:10];
    assign offs16        = inst_id[25:10];
    assign offs26        = inst_id[25:0];

    //指令识别
    // 2R 族：opcode=000000, expand=0000, �? op2 区分
    wire r2 = (opcode == 6'b000000) && (opcode_expand == 4'b0000);

    wire add_w  = r2 && (op2 == 7'b0100000);
    wire sub_w  = r2 && (op2 == 7'b0100010);
    wire slt    = r2 && (op2 == 7'b0100100);
    wire and_   = r2 && (op2 == 7'b0101001);
    wire or_    = r2 && (op2 == 7'b0101010);
    wire xor_   = r2 && (op2 == 7'b0101011);
    wire sll_w  = r2 && (op2 == 7'b0101110);
    wire mul_w  = r2 && (op2 == 7'b0111000);

    // 立即数族：opcode=000000，用 expand/op2 区分
    wire addi_w = (opcode == 6'b000000) && (opcode_expand == 4'b1010);
    wire andi   = (opcode == 6'b000000) && (opcode_expand == 4'b1101);
    wire ori    = (opcode == 6'b000000) && (opcode_expand == 4'b1110);
    wire slli_w = (opcode == 6'b000000) && (opcode_expand == 4'b0001) && (op2 == 7'b0000011);
    wire srli_w = (opcode == 6'b000000) && (opcode_expand == 4'b0001) && (op2 == 7'b0001001);

    // opcode 直接识别的指�?
    assign lu12i_w   = (opcode == 6'b000101);
    assign pcaddu12i = (opcode == 6'b000111) && (inst_id[25:24] == 2'b00);
    assign cpucfg    = (opcode == 6'b000111) && (inst_id[25:24] == 2'b10) &&
                       (inst_id[23:15] == 9'b0);
    assign ld_w      = (opcode == 6'b001010) && (opcode_expand == 4'b0010);
    assign ld_b      = (opcode == 6'b001010) && (opcode_expand == 4'b0000);
    assign st_w      = (opcode == 6'b001010) && (opcode_expand == 4'b0110);
    assign st_b      = (opcode == 6'b001010) && (opcode_expand == 4'b0100);
    assign b         = (opcode == 6'b010100);
    assign bl        = (opcode == 6'b010101);
    assign beq       = (opcode == 6'b010110);
    assign bne       = (opcode == 6'b010111);
    assign jirl      = (opcode == 6'b010011);

    //控制�?
    // ALU 运算�?
    assign alu_op = sub_w || bne || beq    ? ALU_SUB
                  : slt                    ? ALU_SLT
                  : (and_ || andi)         ? ALU_AND
                  : (or_  || ori)          ? ALU_OR
                  : xor_                   ? ALU_XOR
                  : (sll_w || slli_w)      ? ALU_SLL
                  : srli_w                 ? ALU_SRL
                  : lu12i_w                ? ALU_LU12I
                  : pcaddu12i              ? ALU_PCADDU12I
                  : mul_w                  ? ALU_MUL
                  : cpucfg                 ? ALU_CPUCGF
                  :                          ALU_ADD;

    // 写回三�?�一�?00=ALU 01=MEM 10=LINK
    assign wb_sel     = (ld_w || ld_b) ? 2'b01 : (bl || jirl) ? 2'b10 : 2'b00;
    assign wb_is_byte = ld_b;

    assign mem_read  = ld_w | ld_b;
    assign mem_write = st_w | st_b;

    assign write_en  = add_w | sub_w | slt | and_ | or_ | xor_ | sll_w | mul_w |
                       addi_w | andi | ori | slli_w | srli_w | lu12i_w | pcaddu12i |
                       cpucfg | ld_w | ld_b | bl | jirl;

    //寄存器堆
    reg [31:0] regfile [0:31];
    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regfile[i] <= 32'h0;
        end else if (write_wb_en && rd_addr_wb != 5'b0) begin
            regfile[rd_addr_wb] <= rd_data_wb;
        end
    end

    //写优�?
    wire [31:0] rj_data = (write_wb_en && rd_addr_wb == rj && rd_addr_wb != 5'b0)
                           ? rd_data_wb : regfile[rj];
    wire [31:0] rk_data = (write_wb_en && rd_addr_wb == rk && rd_addr_wb != 5'b0)
                           ? rd_data_wb : regfile[rk];
    wire [31:0] rd_data = (write_wb_en && rd_addr_wb == rd && rd_addr_wb != 5'b0)
                           ? rd_data_wb : regfile[rd];

    //立即数扩�?
    wire [31:0] se12 = {{20{inst_id[21]}}, inst_id[21:10]};  
    wire [31:0] ze12 = {20'b0, inst_id[21:10]};               
    wire [31:0] ui5  = {27'b0, rk};                          

    //打包源操作数
    assign alu_src1    = (lu12i_w || pcaddu12i) ? 32'b0 : rj_data;
    assign src1_regnum = (lu12i_w || pcaddu12i) ? 5'b0  : rj;

    assign alu_src2    = add_w || sub_w || slt || and_ || or_ || xor_ ||
                         sll_w || mul_w ? rk_data
                       : slli_w || srli_w ? ui5
                       : (beq || bne) ? rd_data
                       : (andi || ori) ? ze12
                       : (lu12i_w || pcaddu12i || cpucfg) ? 32'b0
                       : se12;   

    assign src2_regnum = add_w || sub_w || slt || and_ || or_ || xor_ ||
                         sll_w || mul_w ? rk
                       : (beq || bne) ? rd
                       : 5'b0;

    // st 存数来自 rd（st.w / st.b�?
    assign st_wdata      = rd_data;
    assign st_src_regnum = (st_w || st_b) ? rd : 5'b0;

    // 目的寄存�?
    assign rd_id = bl ? 5'd1 : rd;

endmodule