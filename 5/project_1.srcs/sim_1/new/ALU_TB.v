`timescale 1ns / 1ps

module tb_ALU_simple;

    // 1. 声明与模块端口对应的变量
    reg  [2:0]  ALUControl;
    reg  [31:0] SrcA, SrcB;
    wire [31:0] ALUResult;

    // 2. 实例化你的ALU模块
    ALU uut (
        .ALUControl(ALUControl),
        .SrcA(SrcA),
        .SrcB(SrcB),
        .ALUResult(ALUResult)
    );

    // 3. 按顺序给输入赋值，并打印输出
    initial begin
        // 初始化所有输入为0，防止出现不定态X
        ALUControl = 3'b000;
        SrcA = 0; 
        SrcB = 0;
        
        #10; // 等待10个时间单位让电路稳定
        
        $display("====== 开始测试 ======");

        // --- 测试加法 (000) ---
        ALUControl = 3'b000;
        SrcA = 32'd10; 
        SrcB = 32'd20;
        #10; 
        $display("ADD: %d + %d = %d", SrcA, SrcB, ALUResult);

        // --- 测试减法 (001) ---
        ALUControl = 3'b001;
        SrcA = 32'd50; 
        SrcB = 32'd30;
        #10; 
        $display("SUB: %d - %d = %d", SrcA, SrcB, ALUResult);

        // --- 测试与运算 (010) ---
        ALUControl = 3'b010;
        SrcA = 32'hFF00_FF00; 
        SrcB = 32'h0F0F_0F0F;
        #10; 
        $display("AND: %h & %h = %h", SrcA, SrcB, ALUResult);

        // --- 测试或运算 (011) ---
        ALUControl = 3'b011;
        SrcA = 32'hFF00_FF00; 
        SrcB = 32'h0F0F_0F0F;
        #10; 
        $display("OR : %h | %h = %h", SrcA, SrcB, ALUResult);

        // --- 测试比较 SLT (101) ---
        ALUControl = 3'b101;
        SrcA = -32'd1; 
        SrcB = 32'd1;
        #10; 
        $display("SLT: %d < %d ? Result=%d (期望为1)", SrcA, SrcB, ALUResult);

        $display("====== 测试结束 ======");
        $finish; // 停止仿真
    end

endmodule