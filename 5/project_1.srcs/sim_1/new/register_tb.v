`timescale 1ns / 1ps

module tb_jicunqidui;

    // 1. 声明与模块端口对应的变量
    reg         clk;
    reg         we3;
    reg  [5:0]  a1, a2, a3;
    reg  [31:0] wd3;
    wire [31:0] rd1, rd2;

    // 2. 实例化你的寄存器堆模块
    regfile uut (
        .clk(clk),
        .we3(we3),
        .a1(a1), .a2(a2), .a3(a3),
        .wd3(wd3),
        .rd1(rd1), .rd2(rd2)
    );

    // 3. 生成时钟信号 (周期为 10ns，每 5ns 翻转一次)
    initial clk = 0;
    always #5 clk = ~clk;

    // 4. 按顺序给输入赋值，并打印输出
    initial begin
        // 初始化所有输入
        we3 = 0; a1 = 0; a2 = 0; a3 = 0; wd3 = 0;
        
        #10; // 等待第一个时钟周期，让电路稳定
        $display("====== 开始测试寄存器堆 ======");

        // --- 测试 1：向 X1 和 X2 写入数据 ---
        // 写 X1 = 100
        we3 = 1; a3 = 6'd1; wd3 = 32'd100; 
        @(posedge clk); // 等待时钟上升沿，触发写入
        #10;
        // 写 X2 = 200
        a3 = 6'd2; wd3 = 32'd200; 
        @(posedge clk); // 再次等待上升沿
        #10
        // --- 测试 2：读取 X1 和 X2 ---
        we3 = 0;       // 关闭写入
        a1 = 6'd1;     // 读端口1 指向 X1
        a2 = 6'd2;     // 读端口2 指向 X2
        #2;            // 组合逻辑需要极短时间稳定，稍微等一下
        $display("READ: rd1(X1) = %d, rd2(X2) = %d (期望: 100, 200)", rd1, rd2);

        // --- 测试 3：尝试向 X0 写入非零值 (破坏性测试) ---
        we3 = 1; a3 = 6'd0; wd3 = 32'd999; // 试图把 999 写进 X0
        @(posedge clk);

        // --- 测试 4：读取 X0，验证是否被保护 ---
        we3 = 0; a1 = 6'd0; a2 = 6'd0; // 两个读端口都指向 X0
        #2;
        $display("READ: rd1(X0) = %d, rd2(X0) = %d (期望: 必须都是 0)", rd1, rd2);

        $display("====== 测试结束 ======");
        $finish;
    end

endmodule