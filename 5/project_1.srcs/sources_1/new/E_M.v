// 执行阶段 -> 访存阶段 流水线寄存器
module E_M(
    input clk, reset,
    // 控制信号（EX 阶段产生，MEM/WB 阶段用）
    input wire        RegWriteE,
    input wire [1:0]  ResultSrcE,
    input wire        MemWriteE,
    // 数据信号（EX 阶段的运算结果）
    input [31:0]      ALUResultE,   // ALU 算出的结果（地址 or 运算值）
    input [31:0]      WriteDataE,   // 要写入内存的数据（sw 的 rs2）
    input [4:0]       RdE,          // 目标寄存器编号
    input [31:0]      PCPlus4E,     // jal 写回 PC+4 用
    input [31:0]      PCTargetE,    // ★ 新增：auipc 结果（PC+imm<<12）
    // 输出到访存阶段
    output reg        RegWriteM,
    output reg [1:0]  ResultSrcM,
    output reg        MemWriteM,
    output reg [31:0] ALUResultM,
    output reg [31:0] WriteDataM,
    output reg [4:0]  RdM,
    output reg [31:0] PCPlus4M,
    output reg [31:0] PCTargetM,
    input [2:0] funct3E,
    output reg [2:0] funct3M,
    input en                       // ★ AXI：en=0（MemStall）时保持 MEM 级指令
);
    always@(posedge clk or posedge reset) begin
        if(reset) begin
            RegWriteM  <= 0;
            ResultSrcM <= 0;
            MemWriteM  <= 0;
            ALUResultM <= 0;
            WriteDataM <= 0;
            RdM        <= 0;
            PCPlus4M   <= 0;
            PCTargetM  <= 0;
            funct3M    <= 0;
        end
        else if(en) begin
            RegWriteM  <= RegWriteE;
            ResultSrcM <= ResultSrcE;
            MemWriteM  <= MemWriteE;
            ALUResultM <= ALUResultE;
            WriteDataM <= WriteDataE;
            RdM        <= RdE;
            PCPlus4M   <= PCPlus4E;
            PCTargetM  <= PCTargetE;
            funct3M    <= funct3E;
        end
    end
endmodule
