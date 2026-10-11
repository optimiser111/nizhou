module D_E(
    input clk, reset,
    input wire [1:0] ResultSrcD,
    input wire MemWriteD,
    input wire BranchD, ALUSrcD,
    input wire RegWriteD, JumpD,
    input wire [3:0] ALUControlD,        // ★ 3 位改 4 位
    output reg [1:0] ResultSrcE,
    output reg MemWriteE,
    output reg BranchE, ALUSrcE,
    output reg RegWriteE, JumpE,
    output reg [3:0] ALUControlE,        // ★ 3 位改 4 位
    input [31:0] RD1D,
    input [31:0] RD2D,
    input [31:0] PCD,
    input [4:0] RdD,
    input [31:0] ImmExtD,
    input [31:0] PCPlus4D,
    input [4:0] Rs1D,
    input [4:0] Rs2D,
    output reg [31:0] RD1E,
    output reg [31:0] RD2E,
    output reg [31:0] PCE,
    output reg [4:0] RdE,
    output reg [31:0] ImmExtE,
    output reg [31:0] PCPlus4E,
    output reg [4:0] Rs1E,
    output reg [4:0] Rs2E,
    input CLR,
    input [2:0] funct3D,
    output reg [2:0] funct3E,
    input wire JalrD,              // ★ 新增：jalr 控制信号
    output reg JalrE,
    input wire MExtD,              // ★ RV32M：乘除指令标记
    output reg MExtE,
    input wire PredTakenD,         // ★ 分支预测：该分支在 IF 级的方向预测
    output reg PredTakenE,
    input en                       // ★ AXI：en=0（MemStall）时保持，CLR 同时被屏蔽
    );
    always@(posedge clk or posedge reset)
    begin
        if(reset) begin
                    ResultSrcE <= 0;
                    MemWriteE <= 0;
                    BranchE <= 0;
                    ALUSrcE <= 0;
                    RegWriteE <= 0;
                    JumpE <= 0;
                    ALUControlE <= 0;
                    RD1E <= 0  ;
                    RD2E <= 0 ;
                    PCE  <= 0  ;
                    RdE   <= 0  ;
                    ImmExtE  <= 0;
                    PCPlus4E <= 0;
                    Rs1E <= 0;
                    Rs2E <= 0;
                    funct3E <= 0;
                    JalrE <= 0;
                    MExtE <= 0;
                    PredTakenE <= 0;
                     end
            else if(en) begin
            if(CLR) begin
                    ResultSrcE <= 0;
                    MemWriteE <= 0;
                    BranchE <= 0;
                    ALUSrcE <= 0;
                    RegWriteE <= 0;
                    JumpE <= 0;
                    ALUControlE <= 0;
                    RD1E <= 0  ;
                    RD2E <= 0 ;
                    PCE  <= 0  ;
                    RdE   <= 0  ;
                    ImmExtE  <= 0;
                    PCPlus4E <= 0;
                    Rs1E <= 0;
                    Rs2E <= 0;
                    funct3E <= 0;
                    JalrE <= 0;
                    MExtE <= 0;
                    PredTakenE <= 0;
            end
            else
            begin
            ResultSrcE <= ResultSrcD;
            MemWriteE <= MemWriteD;
            BranchE <= BranchD;
            ALUSrcE <= ALUSrcD;
            RegWriteE <= RegWriteD;
            JumpE <= JumpD;
            ALUControlE <= ALUControlD;
            RD1E <= RD1D  ;
            RD2E <= RD2D ;
            PCE  <= PCD  ;
            RdE   <= RdD  ;
            ImmExtE  <= ImmExtD;
            PCPlus4E <= PCPlus4D;
            Rs1E <= Rs1D;
            Rs2E <= Rs2D;
            funct3E <= funct3D;
            JalrE <= JalrD;
            MExtE <= MExtD;
            PredTakenE <= PredTakenD;
            end
            end
            // en=0：全部保持（AXI 总线等待期间冻结 EX 级指令）
    end
endmodule
