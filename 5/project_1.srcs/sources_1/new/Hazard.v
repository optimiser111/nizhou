module Hazard(
    input  [4:0] Rs1E,
    input  [4:0] Rs2E,
    input  [4:0] RdM,
    input  [4:0] RdW,
    input        RegWriteM,
    input        RegWriteW,
    output reg [1:0] ForwardAE,
    output reg [1:0] ForwardBE,
    
    output reg StallF,
    output reg StallD,
    input [4:0] Rs1D,
    input [4:0] Rs2D,
    output reg FlushE,
    input ResultSrcE0,
    input [4:0] RdE,
    
    input PCSrcE,
    output reg FlushD
);
    reg lwStall;
    always @(*) begin
        // ---- SrcA 前推判断（rs1）----
        if (RegWriteM && (RdM != 0) && (RdM == Rs1E))
            ForwardAE = 2'b10;   // EX/MEM 前推（最新，优先）
        else if (RegWriteW && (RdW != 0) && (RdW == Rs1E))
            ForwardAE = 2'b01;   // MEM/WB 前推
        else
            ForwardAE = 2'b00;   // 不前推，用寄存器堆读出的值

        // ---- SrcB 前推判断（rs2）----
        if (RegWriteM && (RdM != 0) && (RdM == Rs2E))
            ForwardBE = 2'b10;
        else if (RegWriteW && (RdW != 0) && (RdW == Rs2E))
            ForwardBE = 2'b01;
        else
            ForwardBE = 2'b00;
            
        lwStall = ResultSrcE0 & ((Rs1D == RdE) | (Rs2D == RdE));
        StallF = lwStall;
        StallD = lwStall;
        FlushE = lwStall | PCSrcE;
        
        FlushD = PCSrcE;
    end
endmodule
