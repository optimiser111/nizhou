`timescale 1ns/1ps
// riscvpipe_cover_tb -- 5级流水线CPU高覆盖率测试台
// 截波形推荐信号（Scope 选 uut -> dp 拖入）：
//   PC, Instr, InstrD, PCSrcE, PCTargetE, ForwardAE, ForwardBE,
//   StallF, StallD, FlushE, FlushD, RegWriteW, RdW, ResultW
module riscvpipe_cover_tb;

    reg         clk;
    reg         reset;
    wire [31:0] PC;
    wire [31:0] Instr;
    wire [31:0] InstrN;
    wire        MemWrite;
    wire [31:0] ALUResult, WriteData;
    wire [31:0] ReadData;

    // ==================== 指令存储器 imem ====================
        reg  [31:0] imem [0:127];        // 0:63 改 0:127

    integer k;

    initial begin
        for (k = 0; k < 128; k = k + 1)
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

        // ---------- x0 写保护 + 死循环 ----------
                // ---------- 扩展指令：I 型移位（slli/srli/srai）----------
        imem[42] = 32'h10000713;  // 0xA8: addi x14, x0, 256   x14 = 0x100
        imem[43] = 32'h00471793;  // 0xAC: slli x15, x14, 4    x15 = 0x1000 ★EX/MEM前推x14
        imem[44] = 32'h0047D813;  // 0xB0: srli x16, x15, 4    x16 = 0x100  ★EX/MEM前推x15
        imem[45] = 32'h40415893;  // 0xB4: srai x17, x2, 4     x17 = 0xFFFFFFFF（-3>>>4 符号保持）
        imem[46] = 32'h00415913;  // 0xB8: srli x18, x2, 4     x18 = 0x0FFFFFFF（逻辑右移，对比上行）

        // ---------- 扩展指令：R 型移位（sll/srl/sra）----------
        imem[47] = 32'h001719B3;  // 0xBC: sll  x19, x14, x1   x19 = 0x100<<5 = 0x2000
        imem[48] = 32'h0019DA33;  // 0xC0: srl  x20, x19, x1   x20 = 0x2000>>5 = 0x100 ★前推x19
        imem[49] = 32'h40115AB3;  // 0xC4: sra  x21, x2, x1    x21 = -3>>>5 = 0xFFFFFFFF

        // ---------- 扩展指令：xor / xori ----------
        imem[50] = 32'h00724B33;  // 0xC8: xor  x22, x4, x7    x22 = 20^21 = 1
        imem[51] = 32'h0FF3CB93;  // 0xCC: xori x23, x7, 0xFF  x23 = 21^255 = 0xEA

        // ---------- 扩展指令：无符号比较（sltu/sltiu）----------
        imem[52] = 32'h00113C33;  // 0xD0: sltu x24, x2, x1    x24 = 0（0xFFFFFFFD 无符号 > 5）
        imem[53] = 32'h0040BCB3;  // 0xD4: sltu x25, x1, x4    x25 = 1（5 < 20）
        imem[54] = 32'h00113D13;  // 0xD8: sltiu x26, x2, 1    x26 = 0
        imem[55] = 32'h00103D93;  // 0xDC: sltiu x27, x0, 1    x27 = 1

        // ---------- x0 写保护 + 死循环 ----------
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

        // ---------- x0 写保护 + 死循环 ----------
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

        // ---------- x0 写保护 + 死循环 ----------
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

        // ---------- 字节/半字写入：sb/sh + lw 拼回验证 ----------
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
        imem[117] = 32'h00000063;  // 0x1D4: beq  x0, x0, 0       原地死循环




    end

    assign Instr  = imem[PC[31:2]];
    assign InstrN = imem[PC[31:2] + 1];   // RVC 跨字读口（本程序全 32 位，实际用不到）

    // ==================== 数据存储器 dmem ====================
    reg [31:0] dmem [0:63];

    assign ReadData = dmem[ALUResult[31:2]];
    wire [3:0] ByteEn;
    always @(posedge clk) begin
        if (MemWrite) begin
            if (ByteEn[0]) dmem[ALUResult[31:2]][7:0]   <= WriteData[7:0];
            if (ByteEn[1]) dmem[ALUResult[31:2]][15:8]  <= WriteData[15:8];
            if (ByteEn[2]) dmem[ALUResult[31:2]][23:16] <= WriteData[23:16];
            if (ByteEn[3]) dmem[ALUResult[31:2]][31:24] <= WriteData[31:24];
        end
    end

    // ==================== 例化流水线 CPU ====================
    riscvpipe uut (
        .clk       (clk),
        .reset     (reset),
        .PC        (PC),
        .Instr     (Instr),
        .InstrN    (InstrN),
        .MemWrite  (MemWrite),
        .ALUResult (ALUResult),
        .WriteData (WriteData),
        .ReadData  (ReadData),
        .ByteEn(ByteEn),
        .MemRead   (),          // 理想存储器 TB：不用总线信号
        .MemStall  (1'b0)       // 单周期存储器，永不等待
    );

    always #5 clk = ~clk;

    // ==================== 层次化引用 32 个寄存器 ====================
    wire [31:0] x1  = uut.dp.rf.x[1];
    wire [31:0] x2  = uut.dp.rf.x[2];
    wire [31:0] x3  = uut.dp.rf.x[3];
    wire [31:0] x4  = uut.dp.rf.x[4];
    wire [31:0] x5  = uut.dp.rf.x[5];
    wire [31:0] x6  = uut.dp.rf.x[6];
    wire [31:0] x7  = uut.dp.rf.x[7];
    wire [31:0] x8  = uut.dp.rf.x[8];
    wire [31:0] x9  = uut.dp.rf.x[9];
    wire [31:0] x10 = uut.dp.rf.x[10];
    wire [31:0] x11 = uut.dp.rf.x[11];
    wire [31:0] x12 = uut.dp.rf.x[12];
    wire [31:0] x13 = uut.dp.rf.x[13];
    wire [31:0] x14 = uut.dp.rf.x[14];
    wire [31:0] x15 = uut.dp.rf.x[15];
    wire [31:0] x16 = uut.dp.rf.x[16];
    wire [31:0] x17 = uut.dp.rf.x[17];
    wire [31:0] x18 = uut.dp.rf.x[18];
    wire [31:0] x19 = uut.dp.rf.x[19];
    wire [31:0] x20 = uut.dp.rf.x[20];
    wire [31:0] x21 = uut.dp.rf.x[21];
    wire [31:0] x22 = uut.dp.rf.x[22];
    wire [31:0] x23 = uut.dp.rf.x[23];
    wire [31:0] x24 = uut.dp.rf.x[24];
    wire [31:0] x25 = uut.dp.rf.x[25];
    wire [31:0] x26 = uut.dp.rf.x[26];
    wire [31:0] x27 = uut.dp.rf.x[27];
    wire [31:0] x28 = uut.dp.rf.x[28];
    wire [31:0] x29 = uut.dp.rf.x[29];
    wire [31:0] x30 = uut.dp.rf.x[30];
    wire [31:0] x31 = uut.dp.rf.x[31];

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

        $dumpfile("riscvpipe_cover_tb.vcd");
        $dumpvars(0, riscvpipe_cover_tb);

        repeat(3) @(posedge clk);
        @(negedge clk);
        reset = 0;

        // 44 条指令 + 3 拍 load-use 停顿 + 4 拍流水线填充，70 拍足够
                // 58 条指令 + 3 拍停顿 + 4 拍填充，85 拍足够
         repeat(180) @(posedge clk);




        #1;

        $display("==============================================");
        $display(" PC = %h (死循环应在 000001d4 附近)", PC);



        $display("==============================================");

        // ---------- R 型 / I 型 ALU ----------
        chk(x1, 32'h0000014C, "x1  jal链接");

        chk(x2,  32'hFFFFFFFD,   "x2  addi -3");
        chk(x3,  32'd15,         "x3  addi +前推");
        chk(x4,  32'd20,         "x4  add");
        chk(x5, 32'h12345000, "x5 lui");
        chk(x6, 32'h00001144, "x6 auipc");
        chk(x7, 32'd99, "x7 func执行");
        chk(x8, 32'h8F123456, "x8 测试字");
        chk(x9, 32'h00000056, "x9 lb字节0");
        chk(x10, 32'hFFFFFF8F, "x10 lb符号扩展");
        chk(x11, 32'h0000008F, "x11 lbu零扩展");
        chk(x12, 32'hFFFF8F12, "x12 lh符号扩展");
        chk(x13, 32'h00008F12, "x13 lhu零扩展");

        // ---------- load-use 停顿 ----------
                // ---------- load-use 停顿（原覆盖，寄存器后被复写）----------
                // ---------- 第二档分支（bne/blt/bltu/bgeu/bge）----------
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

        // ---------- 数据存储器 ----------
        chk(dmem[0], 32'd20,     "mem[0] sw");
        chk(dmem[1], 32'd21,     "mem[1] sw");
        chk(dmem[2], 32'd10,     "mem[2] sw");
        chk(dmem[3], 32'd11,     "mem[3] sw");
        chk(dmem[4], 32'h00000184, "mem[4] sw函数地址");
        chk(dmem[5], 32'h8F123456, "mem[5] sw测试字");
        chk(dmem[6], 32'h05AAAA00, "mem[6] sb+sh拼接");

        chk(dmem[7], 32'd21,     "mem[7] sw负偏移");

        $display("==============================================");
        if (errs == 0)
        $display(" ALL TESTS PASSED  (39 项, 37 条指令)");



        else
            $display(" %d TEST(S) FAILED", errs);
        $display("==============================================");

        $finish;
    end

endmodule
