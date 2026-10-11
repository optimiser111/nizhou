`timescale 1ns / 1ps

module tb_maindec();

    // 1. 声明输入输出变量
    reg  [6:0]  op;
    wire [1:0]  ResultSrc;
    wire        MemWrite;
    wire        Branch, ALUSrc;
    wire        RegWrite, Jump;
    wire [1:0]  ImmSrc;
    wire [1:0]  ALUOp;

    // 2. 实例化被测模块
    maindec uut (
        .op(op),
        .ResultSrc(ResultSrc),
        .MemWrite(MemWrite),
        .Branch(Branch), 
        .ALUSrc(ALUSrc),
        .RegWrite(RegWrite), 
        .Jump(Jump),
        .ImmSrc(ImmSrc),
        .ALUOp(ALUOp)
    );

    // 辅助变量：用于打印指令类型名称
    reg [10*8:0] inst_type; 

    // 3. 测试主流程
    initial begin
        // 打印表头
        $display("========================================================================================");
        $display("| %-6s | %-9s | %-4s | %-6s | %-4s | %-8s | %-4s | %-6s | %-5s |", 
                 "Opcode", "Inst_Type", "ResS", "MemW", "Bran", "RegW", "Jump", "ALUSrc", "ALUOp");
        $display("========================================================================================");

        // 测试 Load (I-type)
        op = 7'b0000011; inst_type = "Load"; #5; print_result();

        // 测试 Store (S-type)
        op = 7'b0100011; inst_type = "Store"; #5; print_result();

        // 测试 R-type
        op = 7'b0110011; inst_type = "R-type"; #5; print_result();

        // 测试 Branch (B-type)
        op = 7'b1100011; inst_type = "Branch"; #5; print_result();

        // 测试 I-type ALU
        op = 7'b0010011; inst_type = "I-type ALU"; #5; print_result();

        // 测试 JAL (J-type)
        op = 7'b1101111; inst_type = "JAL"; #5; print_result();

        // 测试非法/未定义指令
        op = 7'b0000000; inst_type = "Illegal"; #5; print_result();

        $display("========================================================================================");
        $display("测试完成！");
        $finish;
    end

    // 4. 打印格式化结果的 Task
    task print_result;
        begin
            $display("| %b | %-9s | %b   | %b    | %b    | %b        | %b    | %b      | %b     |", 
                     op, inst_type, ResultSrc, MemWrite, Branch, RegWrite, Jump, ALUSrc, ALUOp);
        end
    endtask

endmodule