module controller(
    input  [6:0] op,
    input  [2:0] funct3,
    input        funct7b5,
    input        funct7b0,      // ★ RV32M：InstrD[25]，识别 funct7=0000001
    output wire       MExt,
    output wire [1:0] ResultSrc,
    output wire       MemWrite,
    output wire       ALUSrc,
    output wire       RegWrite, Jump,
    output wire [2:0] ImmSrc,        // ★ 2 位改 3 位（U 型）
    output wire [3:0] ALUControl,
    output wire       Branch,
    output wire       Jalr           // ★ 新增：jalr 目标用 rs1+imm
);
    wire [1:0] ALUOp;

    maindec md(op, ResultSrc, MemWrite, Branch,
               ALUSrc, RegWrite, Jump, ImmSrc, ALUOp, Jalr);
    aludec ad(op[5], funct3, funct7b5, ALUOp, ALUControl);

    // 流水线版：PCSrc 不在这里算，移到 datapath 的 EX 阶段

    // ★ RV32M：R 型且 funct7=0000001（bit30=0 且 bit25=1）为乘除指令
    //    其余控制信号与 R 型 ALU 完全相同（RegWrite/ALUSrc/ResultSrc/ALUOp），
    //    只多这一个标记位，EX 级用它切换乘除结果。
    assign MExt = (op == 7'b0110011) & funct7b0 & ~funct7b5;
endmodule
