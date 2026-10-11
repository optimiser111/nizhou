module ALU(
    input [31:0] SrcA,
    input [31:0] SrcB,
    input [3:0] ALUControl,
    output reg [31:0] ALUResult,
    output Zero
    );
    assign Zero = (ALUResult == 32'b0);
    always@(*)
    begin
        case(ALUControl)
            4'b0000: ALUResult = SrcA + SrcB;
            4'b0001: ALUResult = SrcA - SrcB;
            4'b0010: ALUResult = SrcA & SrcB;
            4'b0011: ALUResult = SrcA | SrcB;
            4'b0100: ALUResult = SrcA ^ SrcB;
            // 有符号小于
            4'b0101: ALUResult = {31'b0, ($signed(SrcA) < $signed(SrcB))};
            // 无符号小于
            4'b0110: ALUResult = {31'b0, (SrcA < SrcB)};
            // 移位量只取低 5 位（R 型 rs2 / I 型 shamt 都适用）
            4'b0111: ALUResult = SrcA << SrcB[4:0];
            4'b1000: ALUResult = SrcA >> SrcB[4:0];
            4'b1001: ALUResult = $signed(SrcA) >>> SrcB[4:0];
            4'b1010: ALUResult = SrcB;              // ★ lui：直通（imm<<12 由 extend 完成）
            default: ALUResult = 32'b0;   // ★ 消除 latch，综合必须
        endcase
    end
endmodule
