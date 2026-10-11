// 访存阶段 -> 写回阶段 流水线寄存器
module M_W(
    input clk, reset,
    // 控制信号（MEM 阶段产生，WB 阶段用）
    input wire        RegWriteM,
    input wire [1:0]  ResultSrcM,
    // 数据信号（MEM 阶段的结果）
    input [31:0]      ALUResultM,   // ALU 结果（可能是写回数据）
    input [31:0]      ReadDataM,    // 从内存读出的数据（lw）
    input [4:0]       RdM,          // 目标寄存器编号
    input [31:0]      PCPlus4M,     // jal 写回 PC+4
    input [31:0]      PCTargetM,    // ★ 新增：auipc 结果
    // 输出到写回阶段
    output reg        RegWriteW,
    output reg [1:0]  ResultSrcW,
    output reg [31:0] ALUResultW,
    output reg [31:0] ReadDataW,
    output reg [4:0]  RdW,
    output reg [31:0] PCPlus4W,
    output reg [31:0] PCTargetW,
    input [2:0] funct3M,
    output reg [2:0] funct3W,
    input en                       // ★ AXI：en=0（MemStall）时保持 WB 级指令
);
    always@(posedge clk or posedge reset) begin
        if(reset) begin
            RegWriteW  <= 0;
            ResultSrcW <= 0;
            ALUResultW <= 0;
            ReadDataW  <= 0;
            RdW        <= 0;
            PCPlus4W   <= 0;
            PCTargetW  <= 0;
            funct3W    <= 0;
        end
        else if(en) begin
            RegWriteW  <= RegWriteM;
            ResultSrcW <= ResultSrcM;
            ALUResultW <= ALUResultM;
            ReadDataW  <= ReadDataM;
            RdW        <= RdM;
            PCPlus4W   <= PCPlus4M;
            PCTargetW  <= PCTargetM;
            funct3W    <= funct3M;
        end
    end
endmodule
