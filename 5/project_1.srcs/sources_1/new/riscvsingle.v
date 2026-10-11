module riscvpipe(
    input  clk, reset,
    output [31:0] PC,
    input  [31:0] Instr,
    input  [31:0] InstrN,    // ★ RVC：imem[PC[31:2]+1]
    output MemWrite,
    output [31:0] ALUResult, WriteData,
    input  [31:0] ReadData,
    output [3:0] ByteEn,
    output MemRead,              // ★ AXI：MEM 级是 load（总线读请求）
    input  MemStall              // ★ AXI：总线事务未完成，全流水线保持
);
    wire        ALUSrc, RegWrite, Jump, Branch;
    wire        ZeroE;                 // datapath 内部 EX 阶段 ALU 的 Zero
    wire [1:0]  ResultSrc;
    wire [2:0]  ImmSrc;                // ★ 2 位改 3 位（U 型）
    wire [3:0]  ALUControl;
    wire        Jalr;                  // ★ 新增
    wire        MExt;                  // ★ RV32M：EX 级乘除结果选择


    // 控制器：对"译码阶段"的指令译码
    // ★ 注意：这里传的是 datapath 里的 InstrD，不是 Instr！
    // 但 InstrD 在 datapath 内部，所以需要 datapath 把它引出来，见下面说明
    wire [31:0] InstrD;
    wire MemWriteD;

    controller c(
        .op        (InstrD[6:0]),
        .funct3    (InstrD[14:12]),
        .funct7b5  (InstrD[30]),
        .funct7b0  (InstrD[25]),
        .MExt      (MExt),
        .ResultSrc (ResultSrc),
        .MemWrite  (MemWriteD),
        .ALUSrc    (ALUSrc),
        .RegWrite  (RegWrite),
        .Jump      (Jump),
        .ImmSrc    (ImmSrc),
        .ALUControl(ALUControl),
        .Branch    (Branch),
        .Jalr      (Jalr)
    );

    datapath dp(
    .clk       (clk),
    .reset     (reset),
    .ResultSrc (ResultSrc),
    .MemWrite  (MemWriteD),
    .MemWriteM (MemWrite),
    .MExt      (MExt),
    .Branch    (Branch),
    .ALUSrc    (ALUSrc),
    .RegWrite  (RegWrite),
    .Jump      (Jump),
    .ImmSrc    (ImmSrc),
    .ALUControl(ALUControl),
    .Jalr      (Jalr),
    .ZeroE     (ZeroE),
    .InstrD    (InstrD),
    .PC        (PC),
    .Instr     (Instr),
    .InstrN    (InstrN),
    .ALUResult (ALUResult),
    .WriteData (WriteData),
    .ReadData  (ReadData),
    .ByteEn    (ByteEn),
    .MemReadM  (MemRead),
    .MemStall  (MemStall)
);

endmodule
