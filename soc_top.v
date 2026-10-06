`timescale 1ns/1ps
module soc_top (
    input  wire        clk,
    input  wire        rst,
    //指令SRAM
    output wire        inst_sram_en,
    output wire        inst_sram_wen,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    output wire [3:0]  inst_sram_wstrb,
    input  wire [31:0] inst_sram_rdata,
    //数据SRAM
    output wire        data_sram_en,
    output wire        data_sram_wen,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    output wire [3:0]  data_sram_wstrb,
    input  wire [31:0] data_sram_rdata,
    //UART
    output wire        uart_tx,
    input  wire        uart_rx,
    //调试
    output wire [4:0]  dbg_wb_rd,
    output wire [31:0] dbg_wb_data,
    output wire        dbg_wb_en
);

    //CPU到总线
    wire [31:0] imem_addr;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [31:0] dmem_rdata;
    wire [31:0] imem_data;
    wire        imem_en;
    wire        dmem_en;
    wire        dmem_we;
    wire [3:0]  dmem_wstrb;

    cpu_top u_cpu (
        .clk(clk), 
        .rst(rst),
        .imem_addr(imem_addr), 
        .imem_en(imem_en), 
        .imem_data(imem_data),
        .dmem_addr(dmem_addr), 
        .dmem_wdata(dmem_wdata),
        .dmem_en(dmem_en), 
        .dmem_we(dmem_we), 
        .dmem_wstrb(dmem_wstrb),
        .dmem_rdata(dmem_rdata),
        .dbg_wb_rd(dbg_wb_rd), 
        .dbg_wb_data(dbg_wb_data), 
        .dbg_wb_en(dbg_wb_en)
    );

    //指令 SRAM：BaseRAM，只读、常使能
    assign inst_sram_en    = imem_en;
    assign inst_sram_wen   = 1'b0;
    assign inst_sram_addr  = imem_addr;
    assign inst_sram_wdata = 32'h0;
    assign inst_sram_wstrb = 4'b0;
    assign imem_data       = inst_sram_rdata;

    // ---------- 数据地址解码 ----------
    // UART 窗口：0x1f000000 - 0x1f0fffff（[31:20]==0x1f0）
    wire uart_sel = (dmem_addr[31:20] == 12'h1f0);
    // 主存：BaseRAM(0x1c000000-0x1c3fffff) + ExtRAM(0x1c400000-0x1c7fffff)
    wire ram_sel  = (dmem_addr[31:24] == 8'h1c) && (dmem_addr[23] == 1'b0);



    wire [31:0] uart_rdata;
    wire [31:0] uart_wdata;
    wire        uart_cs;
    wire        uart_we;
    wire [2:0]  uart_addr;

    assign data_sram_en    = ram_sel & dmem_en;
    assign data_sram_wen   = ram_sel & dmem_en & dmem_we;
    assign data_sram_addr  = dmem_addr;
    assign data_sram_wdata = dmem_wdata;
    assign data_sram_wstrb = dmem_wstrb;

    assign dmem_rdata = uart_sel ? uart_rdata : (ram_sel ? data_sram_rdata : 32'h0);

    // ---------- UART ----------
    assign uart_cs    = uart_sel & dmem_en;
    assign uart_we    = uart_sel & dmem_en & dmem_we;
    assign uart_addr  = dmem_addr[2:0];
    assign uart_wdata = dmem_wdata;

    uart #(.CLK_FREQ(50000000), .BAUD(115200)) u_uart (
        .clk(clk), 
        .rst(rst),
        .cs(uart_cs), 
        .we(uart_we), 
        .addr(uart_addr),
        .wdata(uart_wdata), 
        .rdata(uart_rdata),
        .uart_tx(uart_tx), 
        .uart_rx(uart_rx)
    );

endmodule
