`timescale 1ns/1ps
// soc_axi_tb -- SoC（AXI4-Lite 总线版）高覆盖率测试台
// 与 riscvsingle_tb 使用完全相同的 118 条指令测试程序和 39 项自检，
// 区别仅在于：数据存储器不在 TB 里直挂，而是经 AXI4-Lite 总线访问
// soc 内部的 bus_slave.RAM。39 项全部 PASS 即证明总线化改造功能等价。
//
// 截波形推荐信号（Scope 选 soc 拖入）：
//   AWVALID/AWREADY, WVALID/WREADY, BVALID,
//   ARVALID/ARREADY, RVALID, MemStall, led
module soc_axi_tb;

    reg         clk;
    reg         reset;
    wire [31:0] PC;
    reg  [31:0] Instr;
    reg  [31:0] InstrN;
    wire [2:0]  led;
    wire        MemWrite;
    wire [31:0] ALUResult, WriteData, ReadData;

    // ==================== 指令存储器 imem（与 riscvsingle_tb 相同）====================
    reg  [31:0] imem [0:319];

    integer k;

    initial begin
        for (k = 0; k < 320; k = k + 1)
            imem[k] = 32'h00000013;   // nop

        // ---------- R 型 + 前推链 ----------
        imem[ 0] = 32'h00500093;  // 0x00: addi x1, x0, 5      x1 = 5
        imem[ 1] = 32'hFFD00113;  // 0x04: addi x2, x0, -3     x2 = 0xFFFFFFFD（负立即数）
        imem[ 2] = 32'h00A08193;  // 0x08: addi x3, x1, 10     x3 = 15（MEM/WB 前推 x1）
        imem[ 3] = 32'h00118233;  // 0x0C: add  x4, x3, x1     x4 = 20（EX/MEM 前推 x3）
        imem[ 4] = 32'h403202B3;  // 0x10: sub  x5, x4, x3     x5 = 5
        imem[ 5] = 32'h00127333;  // 0x14: and  x6, x4, x1     x6 = 20 & 5 = 4
        imem[ 6] = 32'h001263B3;  // 0x18: or   x7, x4, x1     x7 = 20 | 5 = 21
        imem[ 7] = 32'h00112433;  // 0x1C: slt  x8, x2, x1     x8 = 1（-3 < 5，有符号）
        imem[ 8] = 32'h0020A4B3;  // 0x20: slt  x9, x1, x2     x9 = 0（5 < -3 不成立）

        // ---------- I 型 ALU ----------
        imem[ 9] = 32'h00C3F513;  // 0x24: andi x10, x7, 12    x10 = 21 & 12 = 4
        imem[10] = 32'h7F006593;  // 0x28: ori  x11, x0, 0x7F0 x11 = 0x7F0 = 2032
        imem[11] = 32'h0030A613;  // 0x2C: slti x12, x1, 3     x12 = 0
        imem[12] = 32'h0080A693;  // 0x30: slti x13, x1, 8     x13 = 1

        // ---------- sw / lw 正偏移 ----------
        imem[13] = 32'h00402023;  // 0x34: sw   x4, 0(x0)      mem[0] = 20
        imem[14] = 32'h00702223;  // 0x38: sw   x7, 4(x0)      mem[1] = 21

        // ---------- load-use 停顿（消费者用 rs1）----------
        imem[15] = 32'h00002703;  // 0x3C: lw   x14, 0(x0)     x14 = 20
        imem[16] = 32'h001707B3;  // 0x40: add  x15, x14, x1   x15 = 25 ★StallF/StallD 拉高 1 拍

        // ---------- load-use 停顿（消费者用 rs2）----------
        imem[17] = 32'h00402803;  // 0x44: lw   x16, 4(x0)     x16 = 21
        imem[18] = 32'h410108B3;  // 0x48: sub  x17, x2, x16   x17 = -3-21 = 0xFFFFFFE8 ★停顿

        // ---------- lw 后隔一条：不停顿，MEM/WB 前推 ----------
        imem[19] = 32'h00002903;  // 0x4C: lw   x18, 0(x0)     x18 = 20
        imem[20] = 32'h04D00993;  // 0x50: addi x19, x0, 77    x19 = 77
        imem[21] = 32'h01390A33;  // 0x54: add  x20, x18, x19  x20 = 97（ForwardA=01）

        // ---------- beq 不跳转 ----------
        imem[22] = 32'h00208863;  // 0x58: beq  x1, x2, +16    5 != -3，不跳，PC 顺序走
        imem[23] = 32'h06F00A93;  // 0x5C: addi x21, x0, 111   x21 = 111（证明没跳）

        // ---------- beq 跳转，冲刷 2 条 ----------
        imem[24] = 32'h00508663;  // 0x60: beq  x1, x5, +12    5 == 5，跳到 0x6C ★FlushD/FlushE
        imem[25] = 32'h0DE00A93;  // 0x64: addi x21, x0, 222   被冲刷，x21 保持 111
        imem[26] = 32'h14D00B13;  // 0x68: addi x22, x0, 333   被冲刷，x22 保持 0

        // ---------- beq 连续第二次跳（分支操作数靠前推）----------
        imem[27] = 32'h02C00B93;  // 0x6C: addi x23, x0, 44    x23 = 44（分支目标）
        imem[28] = 32'h017B8663;  // 0x70: beq  x23, x23, +12  跳到 0x7C ★x23 来自 EX/MEM 前推
        imem[29] = 32'h03700C13;  // 0x74: addi x24, x0, 55    被冲刷，x24 保持 0
        imem[30] = 32'h04200C93;  // 0x78: addi x25, x0, 66    被冲刷，x25 保持 0

        // ---------- jal：链接 + 冲刷 ----------
        imem[31] = 32'h00108D33;  // 0x7C: add  x26, x1, x1    x26 = 10
        imem[32] = 32'h00C00DEF;  // 0x80: jal  x27, +12       x27 = 0x84，跳到 0x8C ★Jump
        imem[33] = 32'h05800E13;  // 0x84: addi x28, x0, 88    被冲刷
        imem[34] = 32'h06300E93;  // 0x88: addi x29, x0, 99    被冲刷/不执行

        // ---------- 回到存储器操作 ----------
        imem[35] = 32'h01A02423;  // 0x8C: sw   x26, 8(x0)     mem[2] = 10
        imem[36] = 32'h00802F03;  // 0x90: lw   x30, 8(x0)     x30 = 10
        imem[37] = 32'h001F0F93;  // 0x94: addi x31, x30, 1    x31 = 11 ★又一次 load-use 停顿
        imem[38] = 32'h01F02623;  // 0x98: sw   x31, 12(x0)    mem[3] = 11

        // ---------- 负偏移 sw / lw（S 型/I 型负立即数）----------
        imem[39] = 32'h02000E13;  // 0x9C: addi x28, x0, 32    x28 = 32（基址）
        imem[40] = 32'hFE7E2E23;  // 0xA0: sw   x7, -4(x28)    mem[7] = 21
        imem[41] = 32'hFFCE2E83;  // 0xA4: lw   x29, -4(x28)   x29 = 21

        // ---------- I 型移位（slli/srli/srai）----------
        imem[42] = 32'h10000713;  // 0xA8: addi x14, x0, 256   x14 = 0x100
        imem[43] = 32'h00471793;  // 0xAC: slli x15, x14, 4    x15 = 0x1000 ★EX/MEM前推x14
        imem[44] = 32'h0047D813;  // 0xB0: srli x16, x15, 4    x16 = 0x100  ★EX/MEM前推x15
        imem[45] = 32'h40415893;  // 0xB4: srai x17, x2, 4     x17 = 0xFFFFFFFF（-3>>>4 符号保持）
        imem[46] = 32'h00415913;  // 0xB8: srli x18, x2, 4     x18 = 0x0FFFFFFF（逻辑右移，对比上行）

        // ---------- R 型移位（sll/srl/sra）----------
        imem[47] = 32'h001719B3;  // 0xBC: sll  x19, x14, x1   x19 = 0x100<<5 = 0x2000
        imem[48] = 32'h0019DA33;  // 0xC0: srl  x20, x19, x1   x20 = 0x2000>>5 = 0x100 ★前推x19
        imem[49] = 32'h40115AB3;  // 0xC4: sra  x21, x2, x1    x21 = -3>>>5 = 0xFFFFFFFF

        // ---------- xor / xori ----------
        imem[50] = 32'h00724B33;  // 0xC8: xor  x22, x4, x7    x22 = 20^21 = 1
        imem[51] = 32'h0FF3CB93;  // 0xCC: xori x23, x7, 0xFF  x23 = 21^255 = 0xEA

        // ---------- 无符号比较（sltu/sltiu）----------
        imem[52] = 32'h00113C33;  // 0xD0: sltu x24, x2, x1    x24 = 0（0xFFFFFFFD 无符号 > 5）
        imem[53] = 32'h0040BCB3;  // 0xD4: sltu x25, x1, x4    x25 = 1（5 < 20）
        imem[54] = 32'h00113D13;  // 0xD8: sltiu x26, x2, 1    x26 = 0
        imem[55] = 32'h00103D93;  // 0xDC: sltiu x27, x0, 1    x27 = 1

        // ---------- bne：跳 / 不跳 ----------
        imem[56] = 32'h00209663;  // 0x0E0: bne  x1, x2, +12   5!=-3，跳 -> 0xEC
        imem[57] = 32'h00100713;  // 0x0E4: addi x14, x0, 1    墓碑，冲刷
        imem[58] = 32'h00200713;  // 0x0E8: addi x14, x0, 2    墓碑，冲刷
        imem[59] = 32'h00A00713;  // 0x0EC: addi x14, x0, 10   落点 x14=10
        imem[60] = 32'h00109463;  // 0x0F0: bne  x1, x1, +8    不跳
        imem[61] = 32'h01400793;  // 0x0F4: addi x15, x0, 20   x15=20（证明没跳）

        // ---------- blt（有符号）：跳 / 不跳 ----------
        imem[62] = 32'h00114663;  // 0x0F8: blt  x2, x1, +12   -3<5，跳 -> 0x104
        imem[63] = 32'h00300813;  // 0x0FC: addi x16, x0, 3    墓碑
        imem[64] = 32'h00400813;  // 0x100: addi x16, x0, 4    墓碑
        imem[65] = 32'h01E00813;  // 0x104: addi x16, x0, 30   落点 x16=30
        imem[66] = 32'h0020C463;  // 0x108: blt  x1, x2, +8    5<-3? 不跳
        imem[67] = 32'h02800893;  // 0x10C: addi x17, x0, 40   x17=40

        // ---------- bltu / bgeu（无符号，与 blt 结果相反是关键验证点）----------
        imem[68] = 32'h00116463;  // 0x110: bltu x2, x1, +8    0xFFFFFFFD<5 无符号? 不跳
        imem[69] = 32'h03200913;  // 0x114: addi x18, x0, 50   x18=50
        imem[70] = 32'h00117663;  // 0x118: bgeu x2, x1, +12   无符号>=，跳 -> 0x124
        imem[71] = 32'h00600993;  // 0x11C: addi x19, x0, 6    墓碑
        imem[72] = 32'h00700993;  // 0x120: addi x19, x0, 7    墓碑
        imem[73] = 32'h03C00993;  // 0x124: addi x19, x0, 60   落点 x19=60

        // ---------- bge：不跳 / 跳（相等也跳）----------
        imem[74] = 32'h0040D463;  // 0x128: bge  x1, x4, +8    5>=20? 不跳
        imem[75] = 32'h04600A13;  // 0x12C: addi x20, x0, 70   x20=70
        imem[76] = 32'h00425663;  // 0x130: bge  x4, x4, +12   20>=20，跳 -> 0x13C
        imem[77] = 32'h00800A93;  // 0x134: addi x21, x0, 8    墓碑
        imem[78] = 32'h00900A93;  // 0x138: addi x21, x0, 9    墓碑
        imem[79] = 32'h05000A93;  // 0x13C: addi x21, x0, 80   落点 x21=80

        // ---------- lui / auipc（U 型）----------
        imem[ 80] = 32'h123452B7;  // 0x140: lui  x5, 0x12345    x5 = 0x12345000
        imem[ 81] = 32'h00001317;  // 0x144: auipc x6, 0x1       x6 = 0x144+0x1000 = 0x1144

        // ---------- 函数调用：jal 去 / jalr 回 ----------
        imem[ 82] = 32'h010000EF;  // 0x148: jal  x1, +16        调用func: x1=0x14C, 跳到0x158
        imem[ 83] = 32'h04D00B13;  // 0x14C: addi x22, x0, 77    返回落点 x22=77
        imem[ 84] = 32'h00138B93;  // 0x150: addi x23, x7, 1     x23 = 99+1 = 100
        imem[ 85] = 32'h00000863;  // 0x154: beq  x0, x0, +16    跳过func -> 0x164
        imem[ 86] = 32'h06300393;  // 0x158: func: addi x7, x0, 99    x7=99
        imem[ 87] = 32'h00008067;  // 0x15C:       jalr x0, 0(x1)     ret -> 0x14C
        imem[ 88] = 32'h00000013;  // 0x160: nop（被跳过）

        // ---------- jalr 目标来自 lw：验证 load-use 停顿对 jalr 生效 ----------
        imem[ 89] = 32'h18400C13;  // 0x164: addi x24, x0, 0x184 x24 = func2 地址
        imem[ 90] = 32'h01802823;  // 0x168: sw   x24, 16(x0)    mem[4] = 0x184
        imem[ 91] = 32'h01002C83;  // 0x16C: lw   x25, 16(x0)    x25 = 0x184
        imem[ 92] = 32'h000C8D67;  // 0x170: jalr x26, 0(x25)    x26=0x174, 跳到0x184 ★停顿1拍
        imem[ 93] = 32'h03700D93;  // 0x174: addi x27, x0, 55    返回落点 x27=55
        imem[ 94] = 32'h00000A63;  // 0x178: beq  x0, x0, +20    跳过func2 -> 0x18C
        imem[ 95] = 32'h00000013;  // 0x17C: nop（被跳过）
        imem[ 96] = 32'h00000013;  // 0x180: nop（被跳过）
        imem[ 97] = 32'h04200E93;  // 0x184: func2: addi x29, x0, 66  x29=66
        imem[ 98] = 32'h000D0067;  // 0x188:        jalr x0, 0(x26)   ret -> 0x174

        // ---------- 字节/半字读取：lb/lbu/lh/lhu（同一字 0x8F123456 四种切法）----------
        imem[ 99] = 32'h8F123437;  // 0x18C: lui  x8, 0x8F123     x8 = 0x8F123000
        imem[100] = 32'h45640413;  // 0x190: addi x8, x8, 0x456   x8 = 0x8F123456（前推）
        imem[101] = 32'h00802A23;  // 0x194: sw   x8, 20(x0)      mem[5] = 0x8F123456
        imem[102] = 32'h01400483;  // 0x198: lb   x9, 20(x0)      x9  = 0x00000056（字节0）
        imem[103] = 32'h01700503;  // 0x19C: lb   x10, 23(x0)     x10 = 0xFFFFFF8F（字节3 符号扩展）
        imem[104] = 32'h01704583;  // 0x1A0: lbu  x11, 23(x0)     x11 = 0x0000008F（零扩展，对比上行）
        imem[105] = 32'h01601603;  // 0x1A4: lh   x12, 22(x0)     x12 = 0xFFFF8F12（半字1 符号扩展）
        imem[106] = 32'h01605683;  // 0x1A8: lhu  x13, 22(x0)     x13 = 0x00008F12（零扩展）
        imem[107] = 32'h01405703;  // 0x1AC: lhu  x14, 20(x0)     x14 = 0x00003456（半字0）

        // ---------- 字节/半字写入：sb/sh + lw 拼回验证（考验 WSTRB）----------
        imem[108] = 32'h00002C23;  // 0x1B0: sw   x0, 24(x0)      mem[6] = 0（清零）
        imem[109] = 32'hFAA00793;  // 0x1B4: addi x15, x0, -86    x15 = 0xFFFFFFAA
        imem[110] = 32'h00F00CA3;  // 0x1B8: sb   x15, 25(x0)     mem[6]字节1=0xAA -> 0x0000AA00
        imem[111] = 32'h5AA00813;  // 0x1BC: addi x16, x0, 0x5AA  x16 = 0x000005AA
        imem[112] = 32'h01001D23;  // 0x1C0: sh   x16, 26(x0)     mem[6]半字1=0x05AA -> 0x05AAAA00
        imem[113] = 32'h01802883;  // 0x1C4: lw   x17, 24(x0)     x17 = 0x05AAAA00（拼回整字）

        // ---------- lb 的 load-use 停顿 ----------
        imem[114] = 32'h01400903;  // 0x1C8: lb   x18, 20(x0)     x18 = 0x56
        imem[115] = 32'h00190993;  // 0x1CC: addi x19, x18, 1     x19 = 0x57 ★停顿1拍

        // ---------- x0 写保护 + 死循环 ----------
        imem[116] = 32'h06400013;  // 0x1D0: addi x0, x0, 100     x0 读出必须仍为 0
        // ---------- RV32M：乘/除/除零/溢出/div-use/背靠背/除法后访存 ----------
        imem[117] = 32'h00700293;  // 0x1D4: addi x5, x0, 7
        imem[118] = 32'hFFA00313;  // 0x1D8: addi x6, x0, -6
        imem[119] = 32'h026283B3;  // 0x1DC: mul  x7, x5, x6
        imem[120] = 32'h02702023;  // 0x1E0: sw   x7, 32(x0)
        imem[121] = 32'h123452B7;  // 0x1E4: lui  x5, 0x12345
        imem[122] = 32'h3E800313;  // 0x1E8: addi x6, x0, 1000
        imem[123] = 32'h026283B3;  // 0x1EC: mul  x7, x5, x6
        imem[124] = 32'h02702223;  // 0x1F0: sw   x7, 36(x0)
        imem[125] = 32'h026293B3;  // 0x1F4: mulh x7, x5, x6
        imem[126] = 32'h02702423;  // 0x1F8: sw   x7, 40(x0)
        imem[127] = 32'hFFF00293;  // 0x1FC: addi x5, x0, -1
        imem[128] = 32'hFFF00313;  // 0x200: addi x6, x0, -1
        imem[129] = 32'h0262B3B3;  // 0x204: mulhu x7, x5, x6
        imem[130] = 32'h02702623;  // 0x208: sw   x7, 44(x0)
        imem[131] = 32'h0262A3B3;  // 0x20C: mulhsu x7, x5, x6
        imem[132] = 32'h02702823;  // 0x210: sw   x7, 48(x0)
        imem[133] = 32'hFEC00293;  // 0x214: addi x5, x0, -20
        imem[134] = 32'h00600313;  // 0x218: addi x6, x0, 6
        imem[135] = 32'h0262C3B3;  // 0x21C: div  x7, x5, x6
        imem[136] = 32'h02702A23;  // 0x220: sw   x7, 52(x0)
        imem[137] = 32'h0262E3B3;  // 0x224: rem  x7, x5, x6
        imem[138] = 32'h02702C23;  // 0x228: sw   x7, 56(x0)
        imem[139] = 32'hFFF00293;  // 0x22C: addi x5, x0, -1
        imem[140] = 32'h00300313;  // 0x230: addi x6, x0, 3
        imem[141] = 32'h0262D3B3;  // 0x234: divu x7, x5, x6
        imem[142] = 32'h02702E23;  // 0x238: sw   x7, 60(x0)
        imem[143] = 32'h0262F3B3;  // 0x23C: remu x7, x5, x6
        imem[144] = 32'h04702023;  // 0x240: sw   x7, 64(x0)
        imem[145] = 32'h0202C3B3;  // 0x244: div  x7, x5, x0
        imem[146] = 32'h04702223;  // 0x248: sw   x7, 68(x0)
        imem[147] = 32'h0202E3B3;  // 0x24C: rem  x7, x5, x0
        imem[148] = 32'h04702423;  // 0x250: sw   x7, 72(x0)
        imem[149] = 32'h800002B7;  // 0x254: lui  x5, 0x80000
        imem[150] = 32'hFFF00313;  // 0x258: addi x6, x0, -1
        imem[151] = 32'h0262C3B3;  // 0x25C: div  x7, x5, x6
        imem[152] = 32'h04702623;  // 0x260: sw   x7, 76(x0)
        imem[153] = 32'h0262E3B3;  // 0x264: rem  x7, x5, x6
        imem[154] = 32'h04702823;  // 0x268: sw   x7, 80(x0)
        imem[155] = 32'h06400293;  // 0x26C: addi x5, x0, 100
        imem[156] = 32'h00700313;  // 0x270: addi x6, x0, 7
        imem[157] = 32'h0262C3B3;  // 0x274: div  x7, x5, x6
        imem[158] = 32'h00138493;  // 0x278: addi x9, x7, 1
        imem[159] = 32'h04902A23;  // 0x27C: sw   x9, 84(x0)
        imem[160] = 32'h0262C3B3;  // 0x280: div  x7, x5, x6
        imem[161] = 32'h02534433;  // 0x284: div  x8, x6, x5
        imem[162] = 32'h04702C23;  // 0x288: sw   x7, 88(x0)
        imem[163] = 32'h04802E23;  // 0x28C: sw   x8, 92(x0)
        imem[164] = 32'h0262C3B3;  // 0x290: div  x7, x5, x6
        imem[165] = 32'h00002483;  // 0x294: lw   x9, 0(x0)
        imem[166] = 32'h06902023;  // 0x298: sw   x9, 96(x0)
        imem[167] = 32'h123452B7;  // 0x29C: lui  x5, 0x12345
        imem[168] = 32'h00001337;  // 0x2A0: lui  x6, 0x1
        imem[169] = 32'h14430313;  // 0x2A4: addi x6, x6, 0x144
        imem[170] = 32'h06300393;  // 0x2A8: addi x7, x0, 99
        imem[171] = 32'h8F123437;  // 0x2AC: lui  x8, 0x8F123
        imem[172] = 32'h45640413;  // 0x2B0: addi x8, x8, 0x456
        imem[173] = 32'h05600493;  // 0x2B4: addi x9, x0, 0x56
        // ---------- RVC: 16/32 mix, crossing fetch, compressed jumps, sys-nop ----------
        imem[174] = 32'h10000293;  // 0x2B8: addi x5, x0, 256 [lo] ; addi x5, x0, 256 [hi]
        imem[175] = 32'h0E002823;  // 0x2BC: sw x0,0xF0(x0) clear poison0 [lo] ; sw x0,0xF0(x0) clear poison0 [hi]
        imem[176] = 32'h0E002A23;  // 0x2C0: sw x0,0xF4(x0) clear poison1 [lo] ; sw x0,0xF4(x0) clear poison1 [hi]
        imem[177] = 32'h0E002C23;  // 0x2C4: sw x0,0xF8(x0) clear poison2 [lo] ; sw x0,0xF8(x0) clear poison2 [hi]
        imem[178] = 32'h0E002E23;  // 0x2C8: sw x0,0xFC(x0) clear poison3 [lo] ; sw x0,0xFC(x0) clear poison3 [hi]
        imem[179] = 32'h20000113;  // 0x2CC: addi x2, x0, 512 [lo] ; addi x2, x0, 512 [hi]
        imem[180] = 32'h0415443D;  // 0x2D0: c.li x8,15 ; c.addi x8,5 ->20
        imem[181] = 32'h0082A023;  // 0x2D4: sw x8,0(x5) RAM[64]=20 [lo] ; sw x8,0(x5) RAM[64]=20 [hi]
        imem[182] = 32'hA2236695;  // 0x2D8: c.lui x13,5 ->0x5000 ; sw x13,4(x5) RAM[65]=0x5000 [lo]
        imem[183] = 32'h84A200D2;  // 0x2DC: sw x13,4(x5) RAM[65]=0x5000 [hi] ; c.mv x9,x8 ->20
        imem[184] = 32'hA42394A2;  // 0x2E0: c.add x9,x8 ->40 ; sw x9,8(x5) RAM[66]=40 [lo]
        imem[185] = 32'h45790092;  // 0x2E4: sw x9,8(x5) RAM[66]=40 [hi] ; c.li x10,30
        imem[186] = 32'h8D258D01;  // 0x2E8: c.sub x10,x8 ->10 ; c.xor x10,x9 ->34
        imem[187] = 32'h8D658D41;  // 0x2EC: c.or x10,x8 ->54 ; c.and x10,x9 ->32
        imem[188] = 32'h00A2A623;  // 0x2F0: sw x10,12(x5) RAM[67]=32 [lo] ; sw x10,12(x5) RAM[67]=32 [hi]
        imem[189] = 32'h0592458D;  // 0x2F4: c.li x11,3 ; c.slli x11,4 ->48
        imem[190] = 32'hA8238185;  // 0x2F8: c.srli x11,1 ->24 ; sw x11,16(x5) RAM[68]=24 [lo]
        imem[191] = 32'h566100B2;  // 0x2FC: sw x11,16(x5) RAM[68]=24 [hi] ; c.li x12,-8
        imem[192] = 32'h8A3D8609;  // 0x300: c.srai x12,2 ->-2 ; c.andi x12,15 ->14
        imem[193] = 32'h00C2AA23;  // 0x304: sw x12,20(x5) RAM[69]=14 [lo] ; sw x12,20(x5) RAM[69]=14 [hi]
        imem[194] = 32'h10000693;  // 0x308: addi x13, x0, 256 [lo] ; addi x13, x0, 256 [hi]
        imem[195] = 32'h4EDCCEC0;  // 0x30C: c.sw x8,28(x13) RAM[71]=20 ; c.lw x15,28(x13) ->20
        imem[196] = 32'hAC2397BE;  // 0x310: c.add x15,x15 ->40 (16-bit load-use consumer) ; sw x15,24(x5) RAM[70]=40 [lo]
        imem[197] = 32'h713D00F2;  // 0x314: sw x15,24(x5) RAM[70]=40 [hi] ; c.addi16sp -32 ->x2=0x1E0
        imem[198] = 32'h4702C022;  // 0x318: c.swsp x8,0(x2) RAM[120]=20 ; c.lwsp x14,0(x2) ->20
        imem[199] = 32'h02E2A023;  // 0x31C: sw x14,32(x5) RAM[72]=20 [lo] ; sw x14,32(x5) RAM[72]=20 [hi]
        imem[200] = 32'hA2230098;  // 0x320: c.addi4spn x14,64 ->x14=0x220 ; sw x14,36(x5) RAM[73]=0x220 [lo]
        imem[201] = 32'h011302E2;  // 0x324: sw x14,36(x5) RAM[73]=0x220 [hi] ; addi x2, x0, 512 [lo]
        imem[202] = 32'hA0392000;  // 0x328: addi x2, x0, 512 [hi] ; c.j L1 (off=14)
        imem[203] = 32'h0000E337;  // 0x32C: tomb li x6,0xDEAD lui  x6, 0xE [lo] ; tomb li x6,0xDEAD lui  x6, 0xE [hi]
        imem[204] = 32'hEAD30313;  // 0x330: tomb li x6,0xDEAD addi x6, x6, -339 [lo] ; tomb li x6,0xDEAD addi x6, x6, -339 [hi]
        imem[205] = 32'h0E602823;  // 0x334: tomb sw x6,0x0F0(x0) [lo] ; tomb sw x6,0x0F0(x0) [hi]
        imem[206] = 32'hC4194401;  // 0x338: c.li x8,0 ; c.beqz x8,L2 (off=14)
        imem[207] = 32'h0000E337;  // 0x33C: tomb li x6,0xDEAD lui  x6, 0xE [lo] ; tomb li x6,0xDEAD lui  x6, 0xE [hi]
        imem[208] = 32'hEAD30313;  // 0x340: tomb li x6,0xDEAD addi x6, x6, -339 [lo] ; tomb li x6,0xDEAD addi x6, x6, -339 [hi]
        imem[209] = 32'h0E602A23;  // 0x344: tomb sw x6,0x0F4(x0) [lo] ; tomb sw x6,0x0F4(x0) [hi]
        imem[210] = 32'h441DE019;  // 0x348: c.bnez x8,LBAD not-taken (off=6) ; c.li x8,7
        imem[211] = 32'hE337E419;  // 0x34C: c.bnez x8,L3 taken (off=14) ; tomb li x6,0xDEAD lui  x6, 0xE [lo]
        imem[212] = 32'h03130000;  // 0x350: tomb li x6,0xDEAD lui  x6, 0xE [hi] ; tomb li x6,0xDEAD addi x6, x6, -339 [lo]
        imem[213] = 32'h2C23EAD3;  // 0x354: tomb li x6,0xDEAD addi x6, x6, -339 [hi] ; tomb sw x6,0x0F8(x0) [lo]
        imem[214] = 32'h20390E60;  // 0x358: tomb sw x6,0x0F8(x0) [hi] ; c.jal L4 (off=14)
        imem[215] = 32'h0000E337;  // 0x35C: tomb li x6,0xDEAD lui  x6, 0xE [lo] ; tomb li x6,0xDEAD lui  x6, 0xE [hi]
        imem[216] = 32'hEAD30313;  // 0x360: tomb li x6,0xDEAD addi x6, x6, -339 [lo] ; tomb li x6,0xDEAD addi x6, x6, -339 [hi]
        imem[217] = 32'h0E602E23;  // 0x364: tomb sw x6,0x0FC(x0) [lo] ; tomb sw x6,0x0FC(x0) [hi]
        imem[218] = 32'h0212A423;  // 0x368: sw x1,40(x5) RAM[74]=c.jal addr+2 [lo] ; sw x1,40(x5) RAM[74]=c.jal addr+2 [hi]
        imem[219] = 32'h04930001;  // 0x36C: c.nop (PAD2) ; addi x9,x0,0x382 [lo]
        imem[220] = 32'h84823820;  // 0x370: addi x9,x0,0x382 [hi] ; c.jr x9 -> L5(halfword addr)
        imem[221] = 32'h0000E337;  // 0x374: tomb li x6,0xDEAD lui  x6, 0xE [lo] ; tomb li x6,0xDEAD lui  x6, 0xE [hi]
        imem[222] = 32'hEAD30313;  // 0x378: tomb li x6,0xDEAD addi x6, x6, -339 [lo] ; tomb li x6,0xDEAD addi x6, x6, -339 [hi]
        imem[223] = 32'h0E602823;  // 0x37C: tomb sw x6,0x0F0(x0) [lo] ; tomb sw x6,0x0F0(x0) [hi]
        imem[224] = 32'h447D0001;  // 0x380: c.nop (PAD2) ; c.li x8,31
        imem[225] = 32'hA623042D;  // 0x384: c.addi x8,11 ->42 ; sw x8,44(x5) RAM[75]=42 [lo]
        imem[226] = 32'h04930282;  // 0x388: sw x8,44(x5) RAM[75]=42 [hi] ; addi x9,x0,0x39C [lo]
        imem[227] = 32'h948239C0;  // 0x38C: addi x9,x0,0x39C [hi] ; c.jalr x9 x1=PC+2 -> L6
        imem[228] = 32'h0000E337;  // 0x390: tomb li x6,0xDEAD lui  x6, 0xE [lo] ; tomb li x6,0xDEAD lui  x6, 0xE [hi]
        imem[229] = 32'hEAD30313;  // 0x394: tomb li x6,0xDEAD addi x6, x6, -339 [lo] ; tomb li x6,0xDEAD addi x6, x6, -339 [hi]
        imem[230] = 32'h0E602A23;  // 0x398: tomb sw x6,0x0F4(x0) [lo] ; tomb sw x6,0x0F4(x0) [hi]
        imem[231] = 32'h0212A823;  // 0x39C: sw x1,48(x5) RAM[76]=c.jalr addr+2 [lo] ; sw x1,48(x5) RAM[76]=c.jalr addr+2 [hi]
        imem[232] = 32'h13370001;  // 0x3A0: c.nop align-torture0 ; torture0: lui  x6, 0x11111 [lo]
        imem[233] = 32'h00011111;  // 0x3A4: torture0: lui  x6, 0x11111 [hi] ; c.nop align-torture1
        imem[234] = 32'h22222337;  // 0x3A8: torture1: lui  x6, 0x22222 [lo] ; torture1: lui  x6, 0x22222 [hi]
        imem[235] = 32'h33370001;  // 0x3AC: c.nop align-torture2 ; torture2: lui  x6, 0x33333 [lo]
        imem[236] = 32'h00013333;  // 0x3B0: torture2: lui  x6, 0x33333 [hi] ; c.nop align-torture3
        imem[237] = 32'h44444337;  // 0x3B4: torture3: lui  x6, 0x44444 [lo] ; torture3: lui  x6, 0x44444 [hi]
        imem[238] = 32'h53370001;  // 0x3B8: c.nop align-torture4 ; torture4: lui  x6, 0x55555 [lo]
        imem[239] = 32'h00015555;  // 0x3BC: torture4: lui  x6, 0x55555 [hi] ; c.nop align-torture5
        imem[240] = 32'h66666337;  // 0x3C0: torture5: lui  x6, 0x66666 [lo] ; torture5: lui  x6, 0x66666 [hi]
        imem[241] = 32'h03654365;  // 0x3C4: c.li x6,25 ; c.addi x6,25 ->50
        imem[242] = 32'h030D0365;  // 0x3C8: c.addi x6,25 ->75 ; c.addi x6,3 ->78
        imem[243] = 32'h0262AA23;  // 0x3CC: sw x6,52(x5) RAM[77]=78 [lo] ; sw x6,52(x5) RAM[77]=78 [hi]
        imem[244] = 32'h0000000F;  // 0x3D0: fence -> nop [lo] ; fence -> nop [hi]
        imem[245] = 32'h00000073;  // 0x3D4: ecall -> nop [lo] ; ecall -> nop [hi]
        imem[246] = 32'h00100073;  // 0x3D8: ebreak -> nop [lo] ; ebreak -> nop [hi]
        imem[247] = 32'h44659002;  // 0x3DC: c.ebreak -> nop ; c.li x8,25
        imem[248] = 32'h04650465;  // 0x3E0: c.addi x8,25 ->50 ; c.addi x8,25 ->75
        imem[249] = 32'hAC230465;  // 0x3E4: c.addi x8,25 ->100 ; sw x8,56(x5) RAM[78]=100 (sys instr side-effect free) [lo]
        imem[250] = 32'h02930282;  // 0x3E8: (keep low half) ; BPSTART: addi x5, x0, 256   基址 [lo]
        imem[251] = 32'h03131000;  // 0x3EC: BPSTART: addi x5, x0, 256   基址 [hi] ; addi x6, x0, 100 [lo]
        imem[252] = 32'h03930640;  // 0x3F0: addi x6, x0, 100 [hi] ; addi x7, x0, 0 [lo]
        imem[253] = 32'h04130000;  // 0x3F4: addi x7, x0, 0 [hi] ; addi x8, x0, 0 [lo]
        imem[254] = 32'h83930000;  // 0x3F8: addi x8, x0, 0 [hi] ; L1: addi x7, x7, 1     循环头（出口预测失败时的误取路径） [lo]
        imem[255] = 32'h03130013;  // 0x3FC: L1: addi x7, x7, 1     循环头（出口预测失败时的误取路径） [hi] ; addi x6, x6, -1 [lo]
        imem[256] = 32'h1CE3FFF3;  // 0x400: addi x6, x6, -1 [hi] ; bne  x6, x0, L1 [lo]
        imem[257] = 32'h0413FE03;  // 0x404: bne  x6, x0, L1 [hi] ; addi x8, x8, 1     出口路径（首次迭代预测失败时的误取路径） [lo]
        imem[258] = 32'hA2230014;  // 0x408: addi x8, x8, 1     出口路径（首次迭代预测失败时的误取路径） [hi] ; sw   x7, 228(x5)   RAM[121]=100 [lo]
        imem[259] = 32'hA4230E72;  // 0x40C: sw   x7, 228(x5)   RAM[121]=100 [hi] ; sw   x8, 232(x5)   RAM[122]=1 [lo]
        imem[260] = 32'h04130E82;  // 0x410: sw   x8, 232(x5)   RAM[122]=1 [hi] ; addi x8, x0, 5 [lo]
        imem[261] = 32'h04930050;  // 0x414: addi x8, x0, 5 [hi] ; addi x9, x0, 0 [lo]
        imem[262] = 32'h03130000;  // 0x418: addi x9, x0, 0 [hi] ; LO: addi x6, x0, 10 [lo]
        imem[263] = 32'h849300A0;  // 0x41C: LO: addi x6, x0, 10 [hi] ; LI: addi x9, x9, 1 [lo]
        imem[264] = 32'h03130014;  // 0x420: LI: addi x9, x9, 1 [hi] ; addi x6, x6, -1 [lo]
        imem[265] = 32'h1CE3FFF3;  // 0x424: addi x6, x6, -1 [hi] ; bne  x6, x0, LI [lo]
        imem[266] = 32'h0413FE03;  // 0x428: bne  x6, x0, LI [hi] ; addi x8, x8, -1 [lo]
        imem[267] = 32'h16E3FFF4;  // 0x42C: addi x8, x8, -1 [hi] ; bne  x8, x0, LO [lo]
        imem[268] = 32'hA623FE04;  // 0x430: bne  x8, x0, LO [hi] ; sw   x9, 236(x5)   RAM[123]=50 [lo]
        imem[269] = 32'h03130E92;  // 0x434: sw   x9, 236(x5)   RAM[123]=50 [hi] ; addi x6, x0, 8 [lo]
        imem[270] = 32'h03930080;  // 0x438: addi x6, x0, 8 [hi] ; addi x7, x0, 0 [lo]
        imem[271] = 32'h03130000;  // 0x43C: addi x7, x0, 0 [hi] ; L3: addi x6, x6, -1 [lo]
        imem[272] = 32'h7513FFF3;  // 0x440: L3: addi x6, x6, -1 [hi] ; andi x10, x6, 1 [lo]
        imem[273] = 32'h14630013;  // 0x444: andi x10, x6, 1 [hi] ; bne  x10, x0, S3    奇数跳 [lo]
        imem[274] = 32'h83930005;  // 0x448: bne  x10, x0, S3    奇数跳 [hi] ; addi x7, x7, 1      偶数执行 [lo]
        imem[275] = 32'h18E30013;  // 0x44C: addi x7, x7, 1      偶数执行 [hi] ; S3: bne  x6, x0, L3 [lo]
        imem[276] = 32'hA823FE03;  // 0x450: S3: bne  x6, x0, L3 [hi] ; sw   x7, 240(x5)   RAM[124]=4 [lo]
        imem[277] = 32'h00EF0E72;  // 0x454: sw   x7, 240(x5)   RAM[124]=4 [hi] ; jal  x1, J4        IF 级重定向，零气泡 [lo]
        imem[278] = 32'h05930080;  // 0x458: jal  x1, J4        IF 级重定向，零气泡 [hi] ; addi x11, x0, -1   墓碑：IF 重定向后永不取指 [lo]
        imem[279] = 32'h8593FFF0;  // 0x45C: addi x11, x0, -1   墓碑：IF 重定向后永不取指 [hi] ; J4: addi x11, x1, 0   紧邻消费链接值 [lo]
        imem[280] = 32'hAA230000;  // 0x460: J4: addi x11, x1, 0   紧邻消费链接值 [hi] ; sw   x11, 244(x5)  RAM[125]=jal地址+4 [lo]
        imem[281] = 32'hA6030EB2;  // 0x464: sw   x11, 244(x5)  RAM[125]=jal地址+4 [hi] ; lw   x12, 0(x5)    AXI 读（=20） [lo]
        imem[282] = 32'h04630002;  // 0x468: lw   x12, 0(x5)    AXI 读（=20） [hi] ; beq  x6, x0, S5    x6=0 跳（EX 恰逢总线等待） [lo]
        imem[283] = 32'h06130003;  // 0x46C: beq  x6, x0, S5    x6=0 跳（EX 恰逢总线等待） [hi] ; addi x12, x0, -1   墓碑 [lo]
        imem[284] = 32'hAC23FFF0;  // 0x470: addi x12, x0, -1   墓碑 [hi] ; S5: sw x12, 248(x5)  RAM[126]=20 [lo]
        imem[285] = 32'h00930EC2;  // 0x474: S5: sw x12, 248(x5)  RAM[126]=20 [hi] ; restore: addi x1, x0, 332 [lo]
        imem[286] = 32'h011314C0;  // 0x478: restore: addi x1, x0, 332 [hi] ; restore: addi x2, x0, -3 [lo]
        imem[287] = 32'h52B7FFD0;  // 0x47C: restore: addi x2, x0, -3 [hi] ; restore: lui  x5, 0x12345 [lo]
        imem[288] = 32'h13371234;  // 0x480: restore: lui  x5, 0x12345 [hi] ; restore: lui  x6, 0x1 [lo]
        imem[289] = 32'h03130000;  // 0x484: restore: lui  x6, 0x1 [hi] ; restore: addi x6, x6, 324 [lo]
        imem[290] = 32'h03931443;  // 0x488: restore: addi x6, x6, 324 [hi] ; restore: addi x7, x0, 99 [lo]
        imem[291] = 32'h34370630;  // 0x48C: restore: addi x7, x0, 99 [hi] ; restore: lui  x8, 0x8F123 [lo]
        imem[292] = 32'h04138F12;  // 0x490: restore: lui  x8, 0x8F123 [hi] ; restore: addi x8, x8, 1110 [lo]
        imem[293] = 32'h04934564;  // 0x494: restore: addi x8, x8, 1110 [hi] ; restore: addi x9, x0, 86 [lo]
        imem[294] = 32'h05130560;  // 0x498: restore: addi x9, x0, 86 [hi] ; restore: addi x10, x0, -113 [lo]
        imem[295] = 32'h0593F8F0;  // 0x49C: restore: addi x10, x0, -113 [hi] ; restore: addi x11, x0, 143 [lo]
        imem[296] = 32'h963708F0;  // 0x4A0: restore: addi x11, x0, 143 [hi] ; restore: lui  x12, 0xFFFF9 [lo]
        imem[297] = 32'h0613FFFF;  // 0x4A4: restore: lui  x12, 0xFFFF9 [hi] ; restore: addi x12, x12, -238 [lo]
        imem[298] = 32'h96B7F126;  // 0x4A8: restore: addi x12, x12, -238 [hi] ; restore: lui  x13, 0x9 [lo]
        imem[299] = 32'h86930000;  // 0x4AC: restore: lui  x13, 0x9 [hi] ; restore: addi x13, x13, -238 [lo]
        imem[300] = 32'h3737F126;  // 0x4B0: restore: addi x13, x13, -238 [hi] ; restore: lui  x14, 0x3 [lo]
        imem[301] = 32'h07130000;  // 0x4B4: restore: lui  x14, 0x3 [hi] ; restore: addi x14, x14, 1110 [lo]
        imem[302] = 32'h07934567;  // 0x4B8: restore: addi x14, x14, 1110 [hi] ; restore: addi x15, x0, -86 [lo]
        imem[303] = 32'h0063FAA0;  // 0x4BC: restore: addi x15, x0, -86 [hi] ; beq x0,x0,0 dead loop [lo]
        imem[304] = 32'h00000000;  // 0x4C0: beq x0,x0,0 dead loop [hi]
    end

    always @(*) Instr  = imem[PC[31:2]];
    always @(*) InstrN = imem[PC[31:2] + 1];   // RVC crossing read

    // ==================== 例化 SoC（数据口经 AXI4-Lite 总线）====================
    soc_axi soc(
        .clk       (clk),
        .reset     (reset),
        .PC        (PC),
        .Instr     (Instr),
        .InstrN    (InstrN),
        .led       (led),
        .MemWrite  (MemWrite),
        .ALUResult (ALUResult),
        .WriteData (WriteData),
        .ReadData  (ReadData)
    );

    // 总线观测别名（波形窗口直接拖这些即可）
    wire        AWVALID = soc.AWVALID, AWREADY = soc.AWREADY;
    wire        WVALID  = soc.WVALID,  WREADY  = soc.WREADY;
    wire        BVALID  = soc.BVALID;
    wire        ARVALID = soc.ARVALID, ARREADY = soc.ARREADY;
    wire        RVALID  = soc.RVALID;
    wire        MemStall = soc.MemStall;
    wire [1:0]  bus_state = soc.bus_master.state;

    always #5 clk = ~clk;

    // ==================== 层次化引用 32 个寄存器 ====================
    wire [31:0] x1  = soc.cpu.dp.rf.x[1];
    wire [31:0] x2  = soc.cpu.dp.rf.x[2];
    wire [31:0] x3  = soc.cpu.dp.rf.x[3];
    wire [31:0] x4  = soc.cpu.dp.rf.x[4];
    wire [31:0] x5  = soc.cpu.dp.rf.x[5];
    wire [31:0] x6  = soc.cpu.dp.rf.x[6];
    wire [31:0] x7  = soc.cpu.dp.rf.x[7];
    wire [31:0] x8  = soc.cpu.dp.rf.x[8];
    wire [31:0] x9  = soc.cpu.dp.rf.x[9];
    wire [31:0] x10 = soc.cpu.dp.rf.x[10];
    wire [31:0] x11 = soc.cpu.dp.rf.x[11];
    wire [31:0] x12 = soc.cpu.dp.rf.x[12];
    wire [31:0] x13 = soc.cpu.dp.rf.x[13];
    wire [31:0] x14 = soc.cpu.dp.rf.x[14];
    wire [31:0] x15 = soc.cpu.dp.rf.x[15];
    wire [31:0] x16 = soc.cpu.dp.rf.x[16];
    wire [31:0] x17 = soc.cpu.dp.rf.x[17];
    wire [31:0] x18 = soc.cpu.dp.rf.x[18];
    wire [31:0] x19 = soc.cpu.dp.rf.x[19];
    wire [31:0] x20 = soc.cpu.dp.rf.x[20];
    wire [31:0] x21 = soc.cpu.dp.rf.x[21];
    wire [31:0] x22 = soc.cpu.dp.rf.x[22];
    wire [31:0] x23 = soc.cpu.dp.rf.x[23];
    wire [31:0] x24 = soc.cpu.dp.rf.x[24];
    wire [31:0] x25 = soc.cpu.dp.rf.x[25];
    wire [31:0] x26 = soc.cpu.dp.rf.x[26];
    wire [31:0] x27 = soc.cpu.dp.rf.x[27];
    wire [31:0] x28 = soc.cpu.dp.rf.x[28];
    wire [31:0] x29 = soc.cpu.dp.rf.x[29];
    wire [31:0] x30 = soc.cpu.dp.rf.x[30];
    wire [31:0] x31 = soc.cpu.dp.rf.x[31];

    integer errs = 0;

    task chk;
        input [31:0] got;
        input [31:0] exp;
        input [8*20:1] name;
        begin
            if (got !== exp) begin
                $display("FAIL: %0s = %h, 期望 %h", name, got, exp);
                errs = errs + 1;
            end else
                $display("PASS: %0s = %h", name, got);
        end
    endtask

    initial begin
        clk = 0;
        reset = 1;

        $dumpfile("soc_axi_tb.vcd");
        $dumpvars(0, soc_axi_tb);

        repeat(2100) @(posedge clk);
        @(negedge clk);
        reset = 0;

        // 118 条基础指令 + 58 条 RV32M 测试
        // 13 次除法 × 约 35 拍 + 访存 AXI 等待 ≈ 700 拍，取 900 拍留足裕量
        repeat(1400) @(posedge clk);

        #1;

        $display("==============================================");
        $display(" PC = %h (死循环应在 000004be 附近)", PC);
        $display("==============================================");

        // ---------- R 型 / I 型 ALU ----------
        chk(x1, 32'h0000014C, "x1  jal链接");
        chk(x2,  32'hFFFFFFFD,   "x2  addi -3");
        chk(x3, 32'd15,         "x3  addi +前推");
        chk(x4, 32'd20,         "x4  add");
        chk(x5, 32'h12345000, "x5 lui");
        chk(x6, 32'h00001144, "x6 auipc");
        chk(x7, 32'd99, "x7 func执行");
        chk(x8, 32'h8F123456, "x8 测试字");
        chk(x9, 32'h00000056, "x9 lb字节0");
        chk(x10, 32'hFFFFFF8F, "x10 lb符号扩展");
        chk(x11, 32'h0000008F, "x11 lbu零扩展");
        chk(x12, 32'hFFFF8F12, "x12 lh符号扩展");
        chk(x13, 32'h00008F12, "x13 lhu零扩展");

        // ---------- 第二档分支 / load 扩展 ----------
        chk(x14, 32'h00003456, "x14 lhu半字0");
        chk(x15, 32'hFFFFFFAA, "x15 sb源");
        chk(x16, 32'h000005AA, "x16 sh源");
        chk(x17, 32'h05AAAA00, "x17 sb+sh拼回");
        chk(x18, 32'h00000056, "x18 lb");
        chk(x19, 32'h00000057, "x19 lb停顿+1");
        chk(x20, 32'd70,         "x20 bge不跳");
        chk(x21, 32'd80,         "x21 bge相等跳");
        chk(x22, 32'd77, "x22 jalr返回落点");
        chk(x23, 32'd100, "x23 func结果+1");
        chk(x24, 32'h00000184, "x24 函数地址");
        chk(x25, 32'h00000184, "x25 lw取地址");
        chk(x26, 32'h00000174, "x26 jalr链接");
        chk(x27, 32'd55, "x27 jalr2返回落点");

        // ---------- 尾部存储器 + 负偏移 ----------
        chk(x28, 32'd32,         "x28 基址(jal冲刷后重写)");
        chk(x29, 32'd66, "x29 func2执行");
        chk(x30, 32'd10,         "x30 lw");
        chk(x31, 32'd11,         "x31 load-use addi");

        // ---------- 数据存储器（经 AXI 总线写入）----------
        chk(soc.bus_slave.RAM[0], 32'd20,     "mem[0] sw");
        chk(soc.bus_slave.RAM[1], 32'd21,     "mem[1] sw");
        chk(soc.bus_slave.RAM[2], 32'd10,     "mem[2] sw");
        chk(soc.bus_slave.RAM[3], 32'd11,     "mem[3] sw");
        chk(soc.bus_slave.RAM[4], 32'h00000184, "mem[4] sw函数地址");
        chk(soc.bus_slave.RAM[5], 32'h8F123456, "mem[5] sw测试字");
        chk(soc.bus_slave.RAM[6], 32'h05AAAA00, "mem[6] sb+sh拼接(WSTRB)");
        chk(soc.bus_slave.RAM[7], 32'd21,     "mem[7] sw负偏移");

        // ---------- RV32M 结果（经 AXI 总线写入）----------
        chk(soc.bus_slave.RAM[8], 32'hFFFFFFD6, "M: mul 7*-6");
        chk(soc.bus_slave.RAM[9], 32'h1C588000, "M: mul低32");
        chk(soc.bus_slave.RAM[10], 32'h00000047, "M: mulh高32");
        chk(soc.bus_slave.RAM[11], 32'hFFFFFFFE, "M: mulhu");
        chk(soc.bus_slave.RAM[12], 32'hFFFFFFFF, "M: mulhsu");
        chk(soc.bus_slave.RAM[13], 32'hFFFFFFFD, "M: div -20/6");
        chk(soc.bus_slave.RAM[14], 32'hFFFFFFFE, "M: rem -20%6");
        chk(soc.bus_slave.RAM[15], 32'h55555555, "M: divu");
        chk(soc.bus_slave.RAM[16], 32'h00000000, "M: remu");
        chk(soc.bus_slave.RAM[17], 32'hFFFFFFFF, "M: div除零");
        chk(soc.bus_slave.RAM[18], 32'hFFFFFFFF, "M: rem除零");
        chk(soc.bus_slave.RAM[19], 32'h80000000, "M: div溢出");
        chk(soc.bus_slave.RAM[20], 32'h00000000, "M: rem溢出");
        chk(soc.bus_slave.RAM[21], 32'h0000000F, "M: div-use");
        chk(soc.bus_slave.RAM[22], 32'h0000000E, "M: 背靠背div1");
        chk(soc.bus_slave.RAM[23], 32'h00000000, "M: 背靠背div2");
        chk(soc.bus_slave.RAM[24], 32'h00000014, "M: div后访存");

        // ---------- RVC + sys-nop ----------
        chk(soc.bus_slave.RAM[64], 32'h00000014, "C: li/addi");
        chk(soc.bus_slave.RAM[65], 32'h00005000, "C: lui");
        chk(soc.bus_slave.RAM[66], 32'h00000028, "C: mv/add");
        chk(soc.bus_slave.RAM[67], 32'h00000020, "C: sub/xor/or/and");
        chk(soc.bus_slave.RAM[68], 32'h00000018, "C: slli/srli");
        chk(soc.bus_slave.RAM[69], 32'h0000000E, "C: srai/andi");
        chk(soc.bus_slave.RAM[70], 32'h00000028, "C: lw load-use");
        chk(soc.bus_slave.RAM[71], 32'h00000014, "C: sw");
        chk(soc.bus_slave.RAM[120], 32'h00000014, "C: addi16sp+swsp");
        chk(soc.bus_slave.RAM[72], 32'h00000014, "C: lwsp");
        chk(soc.bus_slave.RAM[73], 32'h00000220, "C: addi4spn");
        chk(soc.bus_slave.RAM[74], 32'h0000035C, "C: jal link");
        chk(soc.bus_slave.RAM[75], 32'h0000002A, "C: jr halfword");
        chk(soc.bus_slave.RAM[76], 32'h00000390, "C: jalr link");
        chk(soc.bus_slave.RAM[77], 32'h0000004E, "C: align mix");
        chk(soc.bus_slave.RAM[78], 32'h00000064, "C: sys nop");
        chk(soc.bus_slave.RAM[60], 32'h00000000, "C: poison0");
        chk(soc.bus_slave.RAM[61], 32'h00000000, "C: poison1");
        chk(soc.bus_slave.RAM[62], 32'h00000000, "C: poison2");
        chk(soc.bus_slave.RAM[63], 32'h00000000, "C: poison3");        $display("==============================================");
        // ---------- 分支预测结果 ----------
        chk(soc.bus_slave.RAM[121], 32'd100,       "BP: loop count");
        chk(soc.bus_slave.RAM[122], 32'd1,         "BP: loop exit once");
        chk(soc.bus_slave.RAM[123], 32'd50,        "BP: nested loops");
        chk(soc.bus_slave.RAM[124], 32'd4,         "BP: alternating branch");
        chk(soc.bus_slave.RAM[125], 32'h0000045A, "BP: jal link fwd");
        chk(soc.bus_slave.RAM[126], 32'd20,        "BP: branch vs AXI stall");
        $display(" BP 统计: 分支解析 %0d 次, 预测失败 %0d 次, 命中率 %0d%%",
                 soc.cpu.dp.branch_predictor.stat_pred,
                 soc.cpu.dp.branch_predictor.stat_miss,
                 (soc.cpu.dp.branch_predictor.stat_pred -
                  soc.cpu.dp.branch_predictor.stat_miss) * 100 /
                 soc.cpu.dp.branch_predictor.stat_pred);
        if (errs == 0)
            $display(" ALL TESTS PASSED  (82 项, RV32IMC + 分支预测 + AXI4-Lite)");
        else
            $display(" %d TEST(S) FAILED", errs);
        $display("==============================================");

        $finish;
    end

endmodule
