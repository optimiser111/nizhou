module maindec(
    input [6:0] op,
    output wire [1:0] ResultSrc,
    output wire MemWrite,
    output wire Branch, ALUSrc,
    output wire RegWrite, Jump,
    output wire [2:0] ImmSrc,        // ★ 3 位
    output wire [1:0] ALUOp,
    output wire       Jalr           // ★ 新增
    );
    reg [12:0] controls;             // ★ 13 位
    assign {RegWrite, ImmSrc, ALUSrc, MemWrite,
            ResultSrc, Branch, ALUOp, Jump, Jalr} = controls;
    always@(*) begin
        case(op)
        7'b0000011: controls = 13'b1_000_1_0_01_0_00_0_0;  // lw
        7'b0100011: controls = 13'b0_001_1_1_00_0_00_0_0;  // sw
        7'b0110011: controls = 13'b1_000_0_0_00_0_10_0_0;  // R 型
        7'b1100011: controls = 13'b0_010_0_0_00_1_01_0_0;  // 分支
        7'b0010011: controls = 13'b1_000_1_0_00_0_10_0_0;  // I 型 ALU
        7'b1101111: controls = 13'b1_011_0_0_10_0_00_1_0;  // jal（ImmSrc=011）
        7'b0110111: controls = 13'b1_100_1_0_00_0_11_0_0;  // ★ lui（U型+ALU直通B）
        7'b0010111: controls = 13'b1_100_0_0_11_0_00_0_0;  // ★ auipc（ResultSrc=11）
        7'b1100111: controls = 13'b1_000_1_0_10_0_00_1_1;  // ★ jalr（I型+链接+Jalr）
        7'b0001111: controls = 13'b0_000_0_0_00_0_00_0_0;  // ★ fence/fence.i：单核、无缓存、顺序执行，
                                                            //   规范允许实现为 nop（RV32I 补完）
        7'b1110011: controls = 13'b0_000_0_0_00_0_00_0_0;  // ★ ecall/ebreak：本核未实现特权架构，
                                                            //   安全降级为 nop（不产生副作用）
        default:    controls = 13'b0_000_0_0_00_0_00_0_0;  // nop
        endcase
    end
endmodule
