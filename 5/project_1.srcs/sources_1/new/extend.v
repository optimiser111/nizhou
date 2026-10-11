module extend(
    input [31:7] instr,
    input [2:0] immsrc,              // ★ 2 位改 3 位
    output reg [31:0] immext
);
always@(*)
case(immsrc)
    3'b000:  immext = {{20{instr[31]}}, instr[31:20]};                          // I
    3'b001:  immext = {{20{instr[31]}}, instr[31:25], instr[11:7]};             // S
    3'b010:  immext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0}; // B
    3'b011:  immext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0}; // J
    3'b100:  immext = {instr[31:12], 12'b0};                                    // ★ U（lui/auipc）
    default: immext = 32'b0;           // 建议顺手把 x 改成 0，综合更干净
endcase
endmodule
