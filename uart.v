// uart.v —— 异步 UART 收发（内存映射 IO），16550 兼容
// 寄存器（字节偏移 addr[2:0]，窗口基址 0x1f000000，见 soc_top 解码）：
//   0x0 DATA : DLAB=0 时写触发发送；读返回接收字节并清除 RX_READY
//   0x1 DLH  : DLAB=1 时写分频高 8 位（接受并忽略，简化实现）
//   0x2 FCR  : FIFO 控制（接受并忽略）
//   0x3 LCR  : 线路控制，bit7=DLAB（决定 +0/+1 是数据还是分频）
//   0x4 MCR  : Modem 控制（接受并忽略）
//   0x5 LSR  : bit0=RX_READY, bit5=TX_READY
// Supervisor 轮询语义：
//   while ((STATUS&0x20)==0){}; DATA=ch;          // 发送
//   while ((STATUS&0x01)==0){}; ch = DATA;        // 接收
// 16550 初始化序列 +2=0x07 +3=0x80 +1=0x00 +0=0x0e +3=0x03 +4=0x00 均允许写入不报错。
`timescale 1ns/1ps
module uart #(
    parameter CLK_FREQ = 50000000,
    parameter BAUD     = 115200
)(
    input  wire        clk,
    input  wire        rst,
    // --- 寄存器读写接口（来自 soc 地址解码） ---
    input  wire        cs,
    input  wire        we,
    input  wire [2:0]  addr,       // 字节偏移
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    // --- 外部串口引脚 ---
    output reg         uart_tx,
    input  wire        uart_rx
);

    localparam DIV = CLK_FREQ / BAUD;      // 每波特对应的时钟周期

    // ================= LCR / DLAB =================
    reg [7:0] lcr;
    wire dlab = lcr[7];
    always @(posedge clk or posedge rst) begin
        if (rst) lcr <= 8'h00;
        else if (cs && we && (addr == 3'd3)) lcr <= wdata[7:0];
    end

    // ================= TX =================
    reg        tx_active;
    reg [3:0]  tx_idx;      // 0=start, 1..8=data, 9=stop
    reg [7:0]  tx_dat;
    reg [15:0] tx_div;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            uart_tx   <= 1'b1;
            tx_active <= 1'b0;
            tx_idx    <= 4'b0;
            tx_dat    <= 8'b0;
            tx_div    <= 16'b0;
        end else if (~tx_active && cs && we && (addr == 3'd0) && ~dlab) begin
            tx_dat    <= wdata[7:0];
            tx_idx    <= 4'b0;
            tx_div    <= 16'b0;
            uart_tx   <= 1'b0;   // start bit
            tx_active <= 1'b1;
        end else if (tx_active) begin
            if (tx_div == DIV[15:0]-1) begin
                tx_div <= 16'b0;
                if (tx_idx == 4'd9) begin          // stop bit 完成
                    tx_active <= 1'b0;
                    uart_tx   <= 1'b1;
                end else begin
                    tx_idx <= tx_idx + 1'b1;
                    // 进入下一 bit：start 之后依次发 8 个数据位，最后 stop
                    case (tx_idx)
                        4'd0: uart_tx <= tx_dat[0];
                        4'd1: uart_tx <= tx_dat[1];
                        4'd2: uart_tx <= tx_dat[2];
                        4'd3: uart_tx <= tx_dat[3];
                        4'd4: uart_tx <= tx_dat[4];
                        4'd5: uart_tx <= tx_dat[5];
                        4'd6: uart_tx <= tx_dat[6];
                        4'd7: uart_tx <= tx_dat[7];
                        4'd8: uart_tx <= 1'b1;     // stop bit
                        default: uart_tx <= 1'b1;
                    endcase
                end
            end else begin
                tx_div <= tx_div + 1'b1;
            end
        end
    end

    // ================= RX（FSM 只推进状态机，不置 READY） =================
    localparam RXIDLE=0, RXSTART=1, RXDATA=2, RXSTOP=3;
    reg [1:0]  rx_bs;
    reg [7:0]  rx_shift;
    reg [3:0]  rx_biti;
    reg [15:0] rx_div;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_bs     <= RXIDLE;
            rx_shift  <= 8'b0;
            rx_biti   <= 4'b0;
            rx_div    <= 16'b0;
        end else begin
            case (rx_bs)
                RXIDLE: begin
                    if (uart_rx == 1'b0) begin           // 检测到下降沿
                        rx_bs   <= RXSTART;
                        rx_div  <= DIV[15:0] >> 1;       // 等半位
                    end
                end
                RXSTART: begin
                    if (rx_div == 16'b0) begin
                        if (uart_rx == 1'b0) begin       // 确认是有效起始位
                            rx_bs  <= RXDATA;
                            rx_div <= DIV[15:0]-1;
                            rx_biti<= 4'b0;
                        end else
                            rx_bs  <= RXIDLE;            // 毛刺，放弃
                    end else
                        rx_div <= rx_div - 1'b1;
                end
                RXDATA: begin
                    if (rx_div == 16'b0) begin
                        rx_shift[rx_biti] <= uart_rx;    // 在数据位中点采样
                        rx_div <= DIV[15:0]-1;
                        if (rx_biti == 4'd7) begin
                            rx_bs <= RXSTOP;
                        end else
                            rx_biti <= rx_biti + 1'b1;
                    end else
                        rx_div <= rx_div - 1'b1;
                end
                RXSTOP: begin
                    if (rx_div == 16'b0) begin
                        rx_bs <= RXIDLE;
                    end else
                        rx_div <= rx_div - 1'b1;
                end
            endcase
        end
    end

    // RX_READY 置位（帧完成）与读清（读 DATA）
    reg        rx_valid;
    reg [7:0]  rx_data;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_valid <= 1'b0;
        end else if (rx_bs == RXSTOP && rx_div == 16'b0) begin
            rx_valid <= 1'b1;       // 一帧接收完成
            rx_data  <= rx_shift;
        end else if (cs && ~we && (addr == 3'd0)) begin
            rx_valid <= 1'b0;       // 读 DATA 清除 RX_READY
        end
    end

    // ================= 读数据（按地址字节通道移位） =================
    // CPU 的 LD.B 会按地址低 2 位（addr[1:0]）选择 32 位读数据中的字节通道，
    // 因此 8 位外设必须把寄存器值放到 addr[1:0] 对应的通道上，否则 LD.B 读错通道。
    // 例如 LSR 地址 0x1f000005 的 addr[1:0]=01，值要放在 bits[15:8]。
    always @(*) begin
        rdata = 32'h0;
        if (cs && ~we) begin
            case (addr)
                3'd0: rdata = {24'b0, rx_data} << (8 * addr[1:0]);   // DATA：最近接收字节
                3'd5: rdata = {26'b0, ~tx_active, 4'b0, rx_valid} << (8 * addr[1:0]); // LSR
                default: rdata = 32'h0;
            endcase
        end
    end

endmodule
