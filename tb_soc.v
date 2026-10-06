// tb_soc.v —— 第三阶段功能测试台（自包含验证，不依赖 kernel.bin）
// 三个场景：
//   1) bootstrap(0x1c000000) → 斐波那契用户程序(0x1c100000) → 校验 ExtRAM 结果内存与 R4/R5/R12/R13/R14
//   2) bootstrap → cpucfg 探测程序(0x1c300000) → 校验 CPUCFG 全 0（无 Cache，supervisor 可跳过 Cache/DMW 初始化）
//   3) bootstrap → UART 自测程序(0x1c200000)：16550 初始化写兼容、DLAB 跟踪、TX 轮询发送 'A'/'B'、
//      RX 轮询接收 tb 注入帧 → 校验 TX 帧数（边沿范围）与接收字节
`timescale 1ns/1ps
module tb_soc;

    reg clk, rst;
    // SRAM 接口
    wire inst_sram_en, inst_sram_wen, data_sram_en, data_sram_wen;
    wire [31:0] inst_sram_addr, inst_sram_wdata, data_sram_addr, data_sram_wdata;
    wire [3:0]  inst_sram_wstrb, data_sram_wstrb;
    reg  [31:0] inst_sram_rdata, data_sram_rdata;
    wire uart_tx;
    reg  uart_rx;
    wire [4:0]  dbg_wb_rd;
    wire [31:0] dbg_wb_data;
    wire        dbg_wb_en;

    soc_top u_soc (
        .clk(clk), .rst(rst),
        .inst_sram_en(inst_sram_en), .inst_sram_wen(inst_sram_wen),
        .inst_sram_addr(inst_sram_addr), .inst_sram_wdata(inst_sram_wdata),
        .inst_sram_wstrb(inst_sram_wstrb), .inst_sram_rdata(inst_sram_rdata),
        .data_sram_en(data_sram_en), .data_sram_wen(data_sram_wen),
        .data_sram_addr(data_sram_addr), .data_sram_wdata(data_sram_wdata),
        .data_sram_wstrb(data_sram_wstrb), .data_sram_rdata(data_sram_rdata),
        .uart_tx(uart_tx), .uart_rx(uart_rx),
        .dbg_wb_rd(dbg_wb_rd), .dbg_wb_data(dbg_wb_data), .dbg_wb_en(dbg_wb_en)
    );

    // ================= 时钟 =================
    initial clk = 1'b0;
    always #10 clk = ~clk;   // 50MHz

    // ================= 共享 8MiB 主存（BaseRAM+ExtRAM 连续，小端字节数组） =================
    reg [7:0] ram [0:8388607];
    // 指令口组合读（BaseRAM 区）
    always @(*) begin
        inst_sram_rdata = {ram[inst_sram_addr[22:0]+3], ram[inst_sram_addr[22:0]+2],
                           ram[inst_sram_addr[22:0]+1], ram[inst_sram_addr[22:0]+0]};
    end
    // 数据口组合读
    always @(*) begin
        data_sram_rdata = {ram[data_sram_addr[22:0]+3], ram[data_sram_addr[22:0]+2],
                           ram[data_sram_addr[22:0]+1], ram[data_sram_addr[22:0]+0]};
    end
    // 数据口时序写（两段捕获：先寄存写请求，下一拍落盘）
    reg ds_en_r, ds_we_r;
    reg [31:0] ds_addr_r, ds_wdata_r;
    reg [3:0]  ds_wstrb_r;
    always @(posedge clk) begin
        ds_en_r   <= data_sram_en;
        ds_we_r   <= data_sram_wen;
        ds_addr_r <= data_sram_addr;
        ds_wdata_r<= data_sram_wdata;
        ds_wstrb_r<= data_sram_wstrb;
    end
    always @(posedge clk) begin
        if (ds_en_r && ds_we_r) begin
            if (ds_wstrb_r[0]) ram[ds_addr_r[22:0]]   <= ds_wdata_r[7:0];
            if (ds_wstrb_r[1]) ram[ds_addr_r[22:0]+1] <= ds_wdata_r[15:8];
            if (ds_wstrb_r[2]) ram[ds_addr_r[22:0]+2] <= ds_wdata_r[23:16];
            if (ds_wstrb_r[3]) ram[ds_addr_r[22:0]+3] <= ds_wdata_r[31:24];
        end
    end

    // ================= 载入/读取辅助 =================
    task load_word;
        input [31:0] a;
        input [31:0] w;
        begin
            ram[a[22:0]]     = w[7:0];
            ram[a[22:0]+1]   = w[15:8];
            ram[a[22:0]+2]   = w[23:16];
            ram[a[22:0]+3]   = w[31:24];
        end
    endtask

    function [31:0] rdword;
        input [31:0] a;
        begin
            rdword = {ram[a[22:0]+3], ram[a[22:0]+2], ram[a[22:0]+1], ram[a[22:0]+0]};
        end
    endfunction

    // ================= UART TX 边沿计数 =================
    integer uart_edges;
    reg uart_tx_prev;
    always @(posedge clk) begin
        if (rst) begin uart_edges <= 0; uart_tx_prev <= 1'b1; end
        else begin
            if (uart_tx !== uart_tx_prev) uart_edges <= uart_edges + 1;
            uart_tx_prev <= uart_tx;
        end
    end

    // ================= 周期计数（调试用） =================
    integer cyc;
    always @(posedge clk) begin
        if (rst) cyc <= 0;
        else     cyc <= cyc + 1;
    end

    // ================= DBG：PC/取指跟踪（每个复位后的前 100 周期） =================
    always @(posedge clk) begin
        if (~rst && cyc < 100)
            $display("DBG[PC] cyc=%0d pc=%h inst=%h stall=%b br_taken=%b br_tgt=%h",
                     cyc, u_soc.u_cpu.u_if.pc, u_soc.u_cpu.u_if.inst_out,
                     u_soc.u_cpu.stall_all, u_soc.u_cpu.branch_taken,
                     u_soc.u_cpu.branch_target);
    end

    // ================= DBG：UART 读写跟踪 =================
    integer uartdbg_cnt;
    always @(posedge clk) begin
        if (rst) uartdbg_cnt <= 0;
        else if (uartdbg_cnt < 40 && u_soc.uart_cs) begin
            $display("DBG[UART] cyc=%0d %s addr=%h wdata=%h dlab=%b tx_active=%b rx_valid=%b",
                     cyc, u_soc.uart_we ? "WR" : "RD", u_soc.uart_addr, u_soc.uart_wdata,
                     u_soc.u_uart.dlab, u_soc.u_uart.tx_active, u_soc.u_uart.rx_valid);
            uartdbg_cnt <= uartdbg_cnt + 1;
        end
    end

    // ================= 阶段 3 RX 帧注入（'A'=0x41，115200 baud） =================
    reg phase3_run;
    reg [31:0] p3_cyc;
    always @(posedge clk) begin
        if (rst) p3_cyc <= 0;
        else if (phase3_run) p3_cyc <= p3_cyc + 1;
    end
    reg [9:0]  rx_sreg;
    reg [15:0] rx_cnt;
    reg [3:0]  rx_bitcnt;
    reg        rx_st;
    always @(posedge clk) begin
        if (rst) begin rx_st <= 1'b0; uart_rx <= 1'b1; rx_cnt <= 16'b0; rx_bitcnt <= 4'b0; end
        else if (phase3_run && ~rx_st && (p3_cyc == 32'd15000)) begin
            rx_st <= 1'b1; rx_cnt <= 16'b0; rx_bitcnt <= 4'b0;
            rx_sreg <= 10'b1010000010;   // 0x41 帧：{stop, D7..D0(LSB 先), start}
        end else if (rx_st) begin
            uart_rx <= rx_sreg[0];
            if (rx_cnt == 16'd433) begin
                rx_cnt <= 16'b0;
                if (rx_bitcnt == 4'd9) begin
                    rx_st <= 1'b0; uart_rx <= 1'b1;
                end else begin
                    rx_sreg <= {1'b1, rx_sreg[9:1]};
                    rx_bitcnt <= rx_bitcnt + 1'b1;
                end
            end else rx_cnt <= rx_cnt + 1'b1;
        end
    end

    // ================= 主流程：三阶段 =================
    integer err, k;
    reg [31:0] fib [0:7];
    initial begin
        err = 0;
        phase3_run = 1'b0;
        fib[0]=32'd2; fib[1]=32'd3; fib[2]=32'd5; fib[3]=32'd8;
        fib[4]=32'd13; fib[5]=32'd21; fib[6]=32'd34; fib[7]=32'd55;

        // ================= 阶段 1：斐波那契 =================
        load_word(32'h1c000000, 32'h5003FFFF);         // b 0x1c100000
        load_word(32'h1c100000, 32'h14388004);         // lu12i.w r4,0x1c400
        load_word(32'h1c100004, 32'h02808085);         // addi.w  r5,r4,0x20
        load_word(32'h1c100008, 32'h0280080C);         // addi.w  r12,r0,2
        load_word(32'h1c10000C, 32'h02800C0D);         // addi.w  r13,r0,3
        load_word(32'h1c100010, 32'h50000003);         // b  LOOP2
        load_word(32'h1c100014, 32'h0010358C);         // LOOP1 add.w r12,r12,r13
        load_word(32'h1c100018, 32'h0010358D);         // add.w r13,r12,r13
        load_word(32'h1c10001C, 32'h001001AE);         // add.w r14,r13,r0
        load_word(32'h1c100020, 32'h2980008C);         // LOOP2 st.w r12,r4,0
        load_word(32'h1c100024, 32'h2980108D);         // st.w r13,r4,4
        load_word(32'h1c100028, 32'h02802084);         // addi.w r4,r4,8
        load_word(32'h1c10002C, 32'h5FFFE485);         // bne  r4,r5,LOOP1

        rst = 1'b1; #40; rst = 1'b0;
        #500000;   // 25000 周期
        for (k=0; k<8; k=k+1) begin
            if (rdword(32'h1c400000 + k*4) !== fib[k]) begin
                $display("FAIL[P1] mem[0x%08X]=%0d 期望 %0d", 32'h1c400000+k*4, rdword(32'h1c400000+k*4), fib[k]);
                err = err + 1;
            end
        end
        if (u_soc.u_cpu.u_id.regfile[4]  !== 32'h1c400020) begin
            $display("FAIL[P1] R4=%h 期望 1c400020", u_soc.u_cpu.u_id.regfile[4]); err = err + 1; end
        if (u_soc.u_cpu.u_id.regfile[5]  !== 32'h1c400020) begin
            $display("FAIL[P1] R5=%h 期望 1c400020", u_soc.u_cpu.u_id.regfile[5]); err = err + 1; end
        if (u_soc.u_cpu.u_id.regfile[12] !== 32'h00000022) begin
            $display("FAIL[P1] R12=%h 期望 00000022", u_soc.u_cpu.u_id.regfile[12]); err = err + 1; end
        if (u_soc.u_cpu.u_id.regfile[13] !== 32'h00000037) begin
            $display("FAIL[P1] R13=%h 期望 00000037", u_soc.u_cpu.u_id.regfile[13]); err = err + 1; end
        if (u_soc.u_cpu.u_id.regfile[14] !== 32'h00000037) begin
            $display("FAIL[P1] R14=%h 期望 00000037", u_soc.u_cpu.u_id.regfile[14]); err = err + 1; end
        if (err == 0) $display("PASS[阶段1] 斐波那契：内存与 R4/R5/R12/R13/R14 全部正确");
        $display("===== 阶段 1（斐波那契）完成 =====");

        // ================= 阶段 2：cpucfg =================
        load_word(32'h1c000000, 32'h500BFFFF);          // b 0x1c300000
        load_word(32'h1c300000, 32'h1438A004);          // lu12i.w r4,0x1c500
        load_word(32'h1c300004, 32'h02804006);          // addi.w  r6,r0,0x10
        load_word(32'h1c300008, 32'h1E0000C7);          // cpucfg  r7,r6 (CPUCFG[16])
        load_word(32'h1c30000C, 32'h1E000008);          // cpucfg  r8,r0 (CPUCFG[0])
        load_word(32'h1c300010, 32'h29800087);          // st.w    r7,r4,0
        load_word(32'h1c300014, 32'h29801088);          // st.w    r8,r4,4
        load_word(32'h1c300018, 32'h53FFFFFF);          // b -1

        rst = 1'b1; #40; rst = 1'b0;
        #100000;   // 5000 周期
        if (rdword(32'h1c500000) !== 32'h0) begin
            $display("FAIL[P2] CPUCFG[16]=%h 期望 0（无 Cache）", rdword(32'h1c500000)); err = err + 1; end
        if (rdword(32'h1c500004) !== 32'h0) begin
            $display("FAIL[P2] CPUCFG[0]=%h 期望 0", rdword(32'h1c500004)); err = err + 1; end
        if (u_soc.u_cpu.u_id.regfile[7] !== 32'h0) begin
            $display("FAIL[P2] R7=%h 期望 0", u_soc.u_cpu.u_id.regfile[7]); err = err + 1; end
        if (u_soc.u_cpu.u_id.regfile[8] !== 32'h0) begin
            $display("FAIL[P2] R8=%h 期望 0", u_soc.u_cpu.u_id.regfile[8]); err = err + 1; end
        if (err == 0) $display("PASS[阶段2] cpucfg：CPUCFG 全 0（I/D-cache 不存在）");
        $display("===== 阶段 2（cpucfg）完成 =====");

        // ================= 阶段 3：UART =================
        load_word(32'h1c000000, 32'h5007FFFF);          // b 0x1c200000
        load_word(32'h1c200000, 32'h143E0004);          // lu12i.w r4,0x1f000
        load_word(32'h1c200004, 32'h02820006);          // addi.w  r6,r0,0x80
        load_word(32'h1c200008, 32'h29000C86);          // st.b r6,r4,3  (LCR=0x80 DLAB=1)
        load_word(32'h1c20000C, 32'h29000480);          // st.b r0,r4,1  (DLH)
        load_word(32'h1c200010, 32'h02803806);          // addi.w r6,r0,0x0e
        load_word(32'h1c200014, 32'h29000086);          // st.b r6,r4,0  (DLL, DLAB=1 不发送)
        load_word(32'h1c200018, 32'h02800C06);          // addi.w r6,r0,0x03
        load_word(32'h1c20001C, 32'h29000C86);          // st.b r6,r4,3  (LCR=0x03 8N1 DLAB=0)
        load_word(32'h1c200020, 32'h29001080);          // st.b r0,r4,4  (MCR)
        load_word(32'h1c200024, 32'h02801484);          // addi.w r4,r4,5 -> LSR
        load_word(32'h1c200028, 32'h28000085);          // TXLOOP ld.b r5,r4,0
        load_word(32'h1c20002C, 32'h034080A6);          // andi r6,r5,0x20
        load_word(32'h1c200030, 32'h5BFFF4C0);          // beq  r6,r0,TXLOOP
        load_word(32'h1c200034, 32'h02BFEC84);          // addi.w r4,r4,-5 -> DATA
        load_word(32'h1c200038, 32'h02810405);          // addi.w r5,r0,0x41 'A'
        load_word(32'h1c20003C, 32'h29000085);          // st.b r5,r4,0 (发送 A)
        load_word(32'h1c200040, 32'h02801484);          // addi.w r4,r4,5 -> LSR
        load_word(32'h1c200044, 32'h28000086);          // TXWAIT ld.b r6,r4,0
        load_word(32'h1c200048, 32'h034080C7);          // andi r7,r6,0x20
        load_word(32'h1c20004C, 32'h5BFFF4E0);          // beq  r7,r0,TXWAIT
        load_word(32'h1c200050, 32'h02BFEC84);          // addi.w r4,r4,-5
        load_word(32'h1c200054, 32'h02810805);          // addi.w r5,r0,0x42 'B'
        load_word(32'h1c200058, 32'h29000085);          // st.b r5,r4,0 (发送 B)
        load_word(32'h1c20005C, 32'h02801484);          // addi.w r4,r4,5 -> LSR
        load_word(32'h1c200060, 32'h28000086);          // RXLOOP ld.b r6,r4,0
        load_word(32'h1c200064, 32'h034004C7);          // andi r7,r6,0x01
        load_word(32'h1c200068, 32'h5BFFF4E0);          // beq  r7,r0,RXLOOP
        load_word(32'h1c20006C, 32'h02BFEC84);          // addi.w r4,r4,-5
        load_word(32'h1c200070, 32'h28000085);          // ld.b r5,r4,0 (读 RX 字节)
        load_word(32'h1c200074, 32'h1438A008);          // lu12i.w r8,0x1c500
        load_word(32'h1c200078, 32'h29000105);          // st.b r5,r8,0
        load_word(32'h1c20007C, 32'h53FFFFFF);          // b -1 (HALT)

        rst = 1'b1; #40; rst = 1'b0;
        phase3_run = 1'b1;
        #2000000;   // 100000 周期
        phase3_run = 1'b0;
        if (rdword(32'h1c500000) !== 32'h41) begin
            $display("FAIL[P3] RX 接收字节 mem[0x1c500000]=%h 期望 0x41", rdword(32'h1c500000)); err = err + 1; end
        if (uart_edges < 10 || uart_edges > 16) begin
            $display("FAIL[P3] uart_tx 边沿=%0d 期望约 12（恰好 2 帧：'A' 与 'B'）", uart_edges); err = err + 1; end
        if (err == 0) $display("PASS[阶段3] UART：16550 写兼容/DLAB 跟踪/TX 轮询发送 2 帧/RX 轮询接收 0x41");
        $display("===== 阶段 3（UART）完成，uart_edges=%0d =====", uart_edges);

        if (err == 0)
            $display("===== 全部 3 阶段 PASS（第三阶段功能测试达标） =====");
        else
            $display("===== 存在 %0d 项错误 =====", err);
        $finish;
    end

endmodule
