module F_D(
    input clk, reset,
    input [31:0] InstrF,
    input [31:0] PCF,
    input [31:0] PCPlus4F,
    input        PredTakenF,    // ★ 分支预测：IF 级方向预测位
    output reg [31:0] InstrD,
    output reg [31:0] PCD,
    output reg[31:0] PCPlus4D,
    output reg       PredTakenD,
    input en,
    input CLR
    );
    always @(posedge clk or posedge reset) begin
    if (reset) begin
        InstrD   <= 32'b0;
        PCD      <= 32'b0;
        PCPlus4D <= 32'b0;
        PredTakenD <= 1'b0;
    end 
    else if(CLR) begin
        InstrD   <= 32'b0;
        PCD      <= 32'b0;
        PCPlus4D <= 32'b0;
        PredTakenD <= 1'b0;
    end
    else if(en) begin
        InstrD   <= InstrF;
        PCD      <= PCF;
        PCPlus4D <= PCPlus4F;
        PredTakenD <= PredTakenF;
    end
end

endmodule
