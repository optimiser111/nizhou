# -*- coding: utf-8 -*-
# gen_bp_tests.py — 为 soc_axi_tb 生成「分支预测」测试段
# 幂等：从 'BPSTART:' 或 'restore:' 注释处截断重生成，可重复运行。
import io, re

# ---------- RV32I 编码 ----------
def I_(imm,rs1,f3,rd,op=0x13):  return ((imm&0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def S_(imm,rs2,rs1,f3):         return (((imm>>5)&0x7F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1F)<<7)|0x23
def B_(imm,rs2,rs1,f3):
    return (((imm>>12)&1)<<31)|(((imm>>5)&0x3F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(((imm>>1)&0xF)<<8)|(((imm>>11)&1)<<7)|0x63
def J_(imm,rd):
    return (((imm>>20)&1)<<31)|(((imm>>1)&0x3FF)<<21)|(((imm>>11)&1)<<20)|(((imm>>12)&0xFF)<<12)|(rd<<7)|0x6F
def U_(imm20,rd,op):            return ((imm20&0xFFFFF)<<12)|(rd<<7)|op
def ADDI(rd,rs1,imm): return I_(imm,rs1,0,rd)
def ANDI(rd,rs1,imm): return I_(imm,rs1,7,rd)   # andi funct3=111（4 是 xori！）
def LUI(rd,v):        return U_(v,rd,0x37)
def SW(rs2,imm,rs1):  return S_(imm,rs2,rs1,2)
def LW(rd,imm,rs1):   return I_(imm,rs1,2,rd,op=0x03)
def BNE(rs1,rs2,imm): return B_(imm,rs2,rs1,1)
def BEQ(rs1,rs2,imm): return B_(imm,rs2,rs1,0)
def JAL(rd,imm):      return J_(imm,rd)

def sgn(v):
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v >= 0x80000000 else v
def li(rd, val):
    s = sgn(val); hi = (s + 0x800) >> 12; lo = s - (hi << 12)
    out = []
    if hi != 0: out.append((LUI(rd, hi & 0xFFFFF), f'lui  x{rd}, 0x{hi & 0xFFFFF:X}'))
    if hi == 0 or lo != 0:
        out.append((ADDI(rd, rd if hi else 0, lo), f'addi x{rd}, x{rd if hi else 0}, {lo}'))
    return out

# ---------- 读取 TB，定位截断点 ----------
p = r'D:\study\cs\nizhou\pipe\project_1.srcs\sim_1\new\soc_axi_tb.v'
s = io.open(p, encoding='gbk').read()
lines = s.splitlines()

imem_re = re.compile(r"^(\s*)imem\[(\d+)\]\s*=\s*32'h([0-9A-Fa-f]+);\s*//\s*(.*)$")
entries = []   # (lineno, wordidx, value, comment)
for i, l in enumerate(lines):
    m = imem_re.match(l)
    if m: entries.append((i, int(m.group(2)), int(m.group(3), 16), m.group(4)))

cut_word = cut_half = None
for lineno, w, val, cmt in entries:
    parts = [x.strip() for x in cmt.split(' ; ')]
    # parts 按地址序（低半在前）
    if len(parts) == 1: parts = parts * 2
    for half, part in enumerate(parts[:2]):
        if part.startswith('BPSTART:') or part.startswith('restore:'):
            cut_word, cut_half = w, half
            break
    if cut_word is not None: break
assert cut_word is not None, 'cut point not found (no BPSTART/restore marker)'
keep_low = None
for lineno, w, val, cmt in entries:
    if w == cut_word: keep_low = val & 0xFFFF
A0 = cut_word * 4 + cut_half * 2
first_cut_lineno = min(l for l, w, v, c in entries if w >= cut_word)
last_imem_lineno = max(l for l, w, v, c in entries)
print(f'cut at imem[{cut_word}] half{cut_half}, A0 = 0x{A0:03X}')

# ---------- BP 测试程序（全 32 位，两遍解析标签） ----------
prog = []  # (code或('b',f3,rs1,rs2,label)/('j',rd,label), asm)
def W(code, asm): prog.append((code, asm))
def BR(f3, rs1, rs2, label, asm): prog.append(('b', f3, rs1, rs2, label, asm))
def JJ(rd, label, asm): prog.append(('j', rd, label, asm))

W(ADDI(5,0,0x100), 'BPSTART: addi x5, x0, 256   基址')
# test1 简单循环：x7 计迭代，x8 计出口路径执行次数
W(ADDI(6,0,100), 'addi x6, x0, 100')
W(ADDI(7,0,0),   'addi x7, x0, 0')
W(ADDI(8,0,0),   'addi x8, x0, 0')
W(ADDI(7,7,1),   'L1: addi x7, x7, 1     循环头（出口预测失败时的误取路径）')
W(ADDI(6,6,-1),  'addi x6, x6, -1')
BR(1, 6, 0, 'L1','bne  x6, x0, L1')
W(ADDI(8,8,1),   'addi x8, x8, 1     出口路径（首次迭代预测失败时的误取路径）')
W(SW(7,228,5),   'sw   x7, 228(x5)   RAM[121]=100')
W(SW(8,232,5),   'sw   x8, 232(x5)   RAM[122]=1')
# test2 嵌套循环
W(ADDI(8,0,5),   'addi x8, x0, 5')
W(ADDI(9,0,0),   'addi x9, x0, 0')
W(ADDI(6,0,10),  'LO: addi x6, x0, 10')
W(ADDI(9,9,1),   'LI: addi x9, x9, 1')
W(ADDI(6,6,-1),  'addi x6, x6, -1')
BR(1, 6, 0, 'LI','bne  x6, x0, LI')
W(ADDI(8,8,-1),  'addi x8, x8, -1')
BR(1, 8, 0, 'LO','bne  x8, x0, LO')
W(SW(9,236,5),   'sw   x9, 236(x5)   RAM[123]=50')
# test3 交替分支：2 位预测器最差模式
W(ADDI(6,0,8),   'addi x6, x0, 8')
W(ADDI(7,0,0),   'addi x7, x0, 0')
W(ADDI(6,6,-1),  'L3: addi x6, x6, -1')
W(ANDI(10,6,1),  'andi x10, x6, 1')
BR(1, 10, 0,'S3','bne  x10, x0, S3    奇数跳')
W(ADDI(7,7,1),   'addi x7, x7, 1      偶数执行')
BR(1, 6, 0, 'L3','S3: bne  x6, x0, L3')
W(SW(7,240,5),   'sw   x7, 240(x5)   RAM[124]=4')
# test4 jal 目标处紧邻消费链接值（ForwardM=PCPlus4M 路径）
JJ(1, 'J4',      'jal  x1, J4        IF 级重定向，零气泡')
W(ADDI(11,0,-1), 'addi x11, x0, -1   墓碑：IF 重定向后永不取指')
W(ADDI(11,1,0),  'J4: addi x11, x1, 0   紧邻消费链接值')
W(SW(11,244,5),  'sw   x11, 244(x5)  RAM[125]=jal地址+4')
# test5 分支在 EX 与 AXI 读事务同拍（MemStall 中的预测失败恢复）
W(LW(12,0,5),    'lw   x12, 0(x5)    AXI 读（=20）')
BR(0, 6, 0,'S5','beq  x6, x0, S5    x6=0 跳（EX 恰逢总线等待）')
W(ADDI(12,0,-1), 'addi x12, x0, -1   墓碑')
W(SW(12,248,5),  'S5: sw x12, 248(x5)  RAM[126]=20')

# 第一遍：记录标签地址（标签为注释首个 token 以冒号结尾者）
labels = {}
a = A0
for it in prog:
    asm = it[-1]
    tok = asm.split(' ')[0]
    if tok.endswith(':'):
        labels[tok.rstrip(':')] = a
    a += 4
# 生成
halfs = []
a = A0
for it in prog:
    if it[0] == 'b':
        _, f3, rs1, rs2, label, asm = it
        off = labels[label] - a
        code = B_(off, rs2, rs1, f3)
    elif it[0] == 'j':
        _, rd, label, asm = it
        off = labels[label] - a
        code = J_(off, rd)
    else:
        code, asm = it
    halfs.append((a, code & 0xFFFF, asm + ' [lo]')); a += 2
    halfs.append((a, (code >> 16) & 0xFFFF, asm + ' [hi]')); a += 2

jal_addr = A0 + 27*4   # jal 在 prog 中的序号 27
link_val = jal_addr + 4

# ---- 恢复受检寄存器（与 RVC 恢复块一致）+ 死循环 ----
RESTORE = [(1,0x14C),(2,0xFFFFFFFD),(5,0x12345000),(6,0x1144),(7,0x63),(8,0x8F123456),(9,0x56),
           (10,0xFFFFFF8F),(11,0x8F),(12,0xFFFF8F12),(13,0x8F12),(14,0x3456),(15,0xFFFFFFAA)]
for rd, val in RESTORE:
    for code, asm in li(rd, val):
        halfs.append((a, code & 0xFFFF, f'restore: {asm} [lo]')); a += 2
        halfs.append((a, (code >> 16) & 0xFFFF, f'restore: {asm} [hi]')); a += 2
halfs.append((a, 0x0063, 'beq x0,x0,0 dead loop [lo]')); a += 2
halfs.append((a, 0x0000, 'beq x0,x0,0 dead loop [hi]')); a += 2
dead = halfs[-2][0]
print(f'dead loop at 0x{dead:03X}, last word imem[{(a-2)//4}]')

# ---------- 打包成 imem 行 ----------
words = {}
if cut_half == 1:
    words[cut_word] = [keep_low, [f'(keep low half)']]
for ad, code, asm in halfs:
    w = ad // 4; hi = (ad % 4) == 2
    cur = words.get(w, [0, []])
    cur[0] |= (code << 16) if hi else code
    cur[1].append(asm)
    words[w] = cur
new_lines = []
for w in sorted(words):
    if w < cut_word: continue
    asm = ' ; '.join(words[w][1])
    new_lines.append(f"        imem[{w}] = 32'h{words[w][0]:08X};  // 0x{w*4:03X}: {asm}")
assert (a - 2) // 4 < 320, 'imem overflow'
section = '\n'.join(new_lines)

# ---------- 写回 TB ----------
out = lines[:first_cut_lineno] + new_lines + lines[last_imem_lineno+1:]
s = '\n'.join(out) + '\n'

# repeat 周期
s, n = re.subn(r'repeat\(\d+\) @\(posedge clk\);', 'repeat(2100) @(posedge clk);', s, count=1)
assert n == 1
# PC 提示
s, n = re.subn(r'死循环应在 [0-9a-f]{8} 附近', f'死循环应在 {dead:08x} 附近', s, count=1)
assert n == 1

# 追加自检（若尚未追加）
if 'BP: loop count' not in s:
    anchor = None
    for l in out:
        if 'chk(soc.bus_slave.RAM[63]' in l: anchor = l.strip()
    assert anchor, 'RVC last chk not found'
    chks = f'''
        // ---------- 分支预测结果 ----------
        chk(soc.bus_slave.RAM[121], 32'd100,       "BP: loop count");
        chk(soc.bus_slave.RAM[122], 32'd1,         "BP: loop exit once");
        chk(soc.bus_slave.RAM[123], 32'd50,        "BP: nested loops");
        chk(soc.bus_slave.RAM[124], 32'd4,         "BP: alternating branch");
        chk(soc.bus_slave.RAM[125], 32'h{link_val:08X}, "BP: jal link fwd");
        chk(soc.bus_slave.RAM[126], 32'd20,        "BP: branch vs AXI stall");
        $display(" BP 统计: 分支解析 %0d 次, 预测失败 %0d 次, 命中率 %0d%%",
                 soc.cpu.dp.branch_predictor.stat_pred,
                 soc.cpu.dp.branch_predictor.stat_miss,
                 (soc.cpu.dp.branch_predictor.stat_pred -
                  soc.cpu.dp.branch_predictor.stat_miss) * 100 /
                 soc.cpu.dp.branch_predictor.stat_pred);'''
    s = s.replace('        ' + anchor, '        ' + anchor + chks, 1)

# PASSED 文案
s, n = re.subn(r'ALL TESTS PASSED  \(\d+ 项[^)]*\)', 'ALL TESTS PASSED  (82 项, RV32IMC + 分支预测 + AXI4-Lite)', s, count=1)
assert n == 1

io.open(p, 'w', encoding='gbk').write(s)
print('TB patched (GBK)')
