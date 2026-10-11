// ============================================================
// c_expand -- RVC 解压器（16 位压缩指令 -> 32 位标准指令）
//
// 纯组合逻辑。输入为取指对齐后的 32 位窗口（压缩指令只看低 16 位），
// 输出展开后的标准 RV32I 指令，下游译码/执行级完全无感。
// is_c 供取指级决定 PC 步进 +2 / +4。
//
// 覆盖 RV32C 全集（无浮点）：
//   Q0: c.addi4spn, c.lw, c.sw
//   Q1: c.nop/c.addi, c.jal(RV32), c.li, c.addi16sp/c.lui,
//       c.srli/c.srai/c.andi, c.sub/c.xor/c.or/c.and, c.j, c.beqz, c.bnez
//   Q2: c.slli, c.lwsp, c.jr/c.mv/c.ebreak/c.jalr/c.add, c.swsp
// 保留编码（浮点槽位、RV64 槽位、hint）一律展开为 nop。
// ============================================================
module c_expand(
    input  wire [31:0] cin,     // 对齐装配后的指令窗口
    output reg  [31:0] dout,    // 展开后的 32 位指令
    output wire        is_c
);
    assign is_c = (cin[1:0] != 2'b11);

    wire [15:0] c = cin[15:0];
    wire [2:0]  f3   = c[15:13];
    wire [4:0]  rd   = c[11:7];
    wire [4:0]  rs2  = c[6:2];
    wire [4:0]  rdp  = {2'b01, c[4:2]};     // Q0/Q1 压缩寄存器 x8-x15
    wire [4:0]  rs1p = {2'b01, c[9:7]};

    // ---- 常用立即数拼块 ----
    wire [11:0] imm6    = {{6{c[12]}}, c[12], c[6:2]};                    // addi/li/andi 的 6 位符号扩展
    wire [11:0] imm4spn = {2'b00, c[10:7], c[12:11], c[5], c[6], 2'b00};  // c.addi4spn nzuimm
    wire [11:0] immcl   = {5'b00000, c[5], c[12:10], c[6], 2'b00};        // c.lw / c.sw
    wire [11:0] immlwsp = {4'b0000, c[3:2], c[12], c[6:4], 2'b00};        // c.lwsp
    wire [11:0] immswsp = {4'b0000, c[8:7], c[12:9], 2'b00};              // c.swsp
    wire [11:0] imm16sp = {{2{c[12]}}, c[12], c[4:3], c[5], c[2], c[6], 4'b0000}; // c.addi16sp
    // CJ 跳转偏移（c.j / c.jal）：off[11|4|9:8|10|6|7|3:1|5] = c[12|11|10:9|8|7|6|5:3|2]
    wire [11:0] offcj = {c[12], c[8], c[10:9], c[6], c[7], c[2], c[11], c[5:3], 1'b0};
    wire [20:0] jimm  = {{9{offcj[11]}}, offcj};
    // CB 分支偏移（c.beqz / c.bnez）
    wire [8:0]  offcb = {c[12], c[6:5], c[2], c[11:10], c[4:3], 1'b0};
    wire [12:0] bimm  = {{4{offcb[8]}}, offcb};

    // ---- 标准指令拼装 ----
    wire [31:0] NOP = 32'h00000013;   // addi x0, x0, 0

    always @(*) begin
        dout = NOP;
        case (c[1:0])
        // ---------------- Quadrant 0 ----------------
        2'b00: case (f3)
            3'b000: dout = {imm4spn, 5'd2, 3'b000, rdp, 7'b0010011};        // c.addi4spn -> addi rd', x2, nzuimm
            3'b010: dout = {immcl, rs1p, 3'b010, rdp, 7'b0000011};          // c.lw -> lw rd', uimm(rs1')
            3'b110: dout = {immcl[11:5], rdp, rs1p, 3'b010, immcl[4:0], 7'b0100011}; // c.sw
            default: dout = NOP;                                            // 浮点/保留槽位
        endcase
        // ---------------- Quadrant 1 ----------------
        2'b01: case (f3)
            3'b000: dout = {imm6, rd, 3'b000, rd, 7'b0010011};              // c.nop / c.addi -> addi rd, rd, imm
            3'b001: dout = {jimm[20], jimm[10:1], jimm[11], jimm[19:12], 5'd1, 7'b1101111}; // c.jal -> jal x1
            3'b010: dout = {imm6, 5'd0, 3'b000, rd, 7'b0010011};            // c.li -> addi rd, x0, imm
            3'b011: if (rd == 5'd2)
                        dout = {imm16sp, 5'd2, 3'b000, 5'd2, 7'b0010011};   // c.addi16sp -> addi x2, x2, nzimm
                    else
                        dout = {{14{c[12]}}, c[12], c[6:2], rd, 7'b0110111};// c.lui -> lui rd, sext(nzimm)
            3'b100: case (c[11:10])
                2'b00: dout = {6'b000000, c[6:2], rs1p, 3'b101, rs1p, 7'b0010011};   // c.srli
                2'b01: dout = {6'b010000, c[6:2], rs1p, 3'b101, rs1p, 7'b0010011};   // c.srai
                2'b10: dout = {imm6, rs1p, 3'b111, rs1p, 7'b0010011};                // c.andi
                2'b11: if (!c[12])
                        case (c[6:5])                                                   // CA 寄存器算术
                        2'b00: dout = {7'b0100000, rdp, rs1p, 3'b000, rs1p, 7'b0110011}; // c.sub
                        2'b01: dout = {7'b0000000, rdp, rs1p, 3'b100, rs1p, 7'b0110011}; // c.xor
                        2'b10: dout = {7'b0000000, rdp, rs1p, 3'b110, rs1p, 7'b0110011}; // c.or
                        2'b11: dout = {7'b0000000, rdp, rs1p, 3'b111, rs1p, 7'b0110011}; // c.and
                        endcase
                    else dout = NOP;                                        // RV64 槽位（subw/addw）
            endcase
            3'b101: dout = {jimm[20], jimm[10:1], jimm[11], jimm[19:12], 5'd0, 7'b1101111}; // c.j -> jal x0
            3'b110: dout = {bimm[12], bimm[10:5], 5'd0, rs1p, 3'b000, bimm[4:1], bimm[11], 7'b1100011}; // c.beqz
            3'b111: dout = {bimm[12], bimm[10:5], 5'd0, rs1p, 3'b001, bimm[4:1], bimm[11], 7'b1100011}; // c.bnez
        endcase
        // ---------------- Quadrant 2 ----------------
        2'b10: case (f3)
            3'b000: dout = {6'b000000, c[6:2], rd, 3'b001, rd, 7'b0010011}; // c.slli
            3'b010: dout = {immlwsp, 5'd2, 3'b010, rd, 7'b0000011};         // c.lwsp -> lw rd, uimm(x2)
            3'b100: if (!c[12]) begin
                        if (rs2 == 5'd0)
                            dout = {12'd0, rd, 3'b000, 5'd0, 7'b1100111};   // c.jr -> jalr x0, 0(rs1)
                        else
                            dout = {7'b0000000, rs2, 5'd0, 3'b000, rd, 7'b0110011}; // c.mv -> add rd, x0, rs2
                    end else begin
                        if (rs2 != 5'd0)
                            dout = {7'b0000000, rs2, rd, 3'b000, rd, 7'b0110011};   // c.add -> add rd, rd, rs2
                        else if (rd != 5'd0)
                            dout = {12'd0, rd, 3'b000, 5'd1, 7'b1100111};   // c.jalr -> jalr x1, 0(rs1)
                        else
                            dout = 32'h00100073;                            // c.ebreak -> ebreak（本核=nop）
                    end
            3'b110: dout = {immswsp[11:5], rs2, 5'd2, 3'b010, immswsp[4:0], 7'b0100011}; // c.swsp
            default: dout = NOP;                                            // 浮点/保留槽位
        endcase
        default: dout = NOP;    // c[1:0]==11 是 32 位指令，不会被选中（is_c=0）
        endcase
    end
endmodule
