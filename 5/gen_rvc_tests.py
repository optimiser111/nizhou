# -*- coding: utf-8 -*-
import io

# ---------- RV32I ----------
def I_(imm,rs1,f3,rd,op=0x13):  return ((imm&0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def S_(imm,rs2,rs1,f3):         return (((imm>>5)&0x7F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1F)<<7)|0x23
def U_(imm20,rd,op):            return ((imm20&0xFFFFF)<<12)|(rd<<7)|op
def ADDI(rd,rs1,imm): return I_(imm,rs1,0,rd)
def LUI(rd,v):        return U_(v,rd,0x37)
def SW(rs2,imm,rs1):  return S_(imm,rs2,rs1,2)

# ---------- RVC ----------
def c_li(rd,imm):      return 0x4001 | (((imm>>5)&1)<<12) | (rd<<7) | ((imm&0x1F)<<2)
def c_addi(rd,imm):    return 0x0001 | (((imm>>5)&1)<<12) | (rd<<7) | ((imm&0x1F)<<2)
def c_lui(rd,imm6):    return 0x6001 | (((imm6>>5)&1)<<12) | (rd<<7) | ((imm6&0x1F)<<2)
def c_addi16sp(imm):
    return 0x6101 | (((imm>>9)&1)<<12) | (((imm>>4)&1)<<6) | (((imm>>6)&1)<<5) | (((imm>>7)&3)<<3) | (((imm>>5)&1)<<2)
def c_addi4spn(rdp3,imm):
    return (((imm>>4)&3)<<11) | (((imm>>6)&0xF)<<7) | (((imm>>2)&1)<<6) | (((imm>>3)&1)<<5) | (rdp3<<2)
def clcs(imm):         return (((imm>>3)&7)<<10) | (((imm>>2)&1)<<6) | (((imm>>6)&1)<<5)
def c_lw(rdp3,imm,rs1p3):  return 0x4000 | clcs(imm) | (rs1p3<<7) | (rdp3<<2)
def c_sw(rs2p3,imm,rs1p3): return 0xC000 | clcs(imm) | (rs1p3<<7) | (rs2p3<<2)
def c_slli(rd,sh):     return 0x0002 | (((sh>>5)&1)<<12) | (rd<<7) | ((sh&0x1F)<<2)
def c_srli(rdp3,sh):   return 0x8001 | (((sh>>5)&1)<<12) | ((sh&0x1F)<<2) | (rdp3<<7)
def c_srai(rdp3,sh):   return 0x8401 | (((sh>>5)&1)<<12) | ((sh&0x1F)<<2) | (rdp3<<7)
def c_andi(rdp3,imm):  return 0x8801 | (((imm>>5)&1)<<12) | (rdp3<<7) | ((imm&0x1F)<<2)
def c_ca(f,rdp3,rs2p3):    return 0x8C01 | (f<<5) | (rdp3<<7) | (rs2p3<<2)
def cj(off):  return (((off>>11)&1)<<12)|(((off>>4)&1)<<11)|(((off>>8)&3)<<9)|(((off>>10)&1)<<8)|(((off>>6)&1)<<7)|(((off>>7)&1)<<6)|(((off>>1)&7)<<3)|(((off>>5)&1)<<2)
def cb(off):  return (((off>>8)&1)<<12)|(((off>>3)&3)<<10)|(((off>>6)&3)<<5)|(((off>>1)&3)<<3)|(((off>>5)&1)<<2)
def c_j(off):          return 0xA001 | cj(off)
def c_jal(off):        return 0x2001 | cj(off)
def c_beqz(rs1p3,off): return 0xC001 | cb(off) | (rs1p3<<7)
def c_bnez(rs1p3,off): return 0xE001 | cb(off) | (rs1p3<<7)
def c_lwsp(rd,imm):    return 0x4002 | (((imm>>5)&1)<<12) | (rd<<7) | (((imm>>2)&7)<<4) | (((imm>>6)&3)<<2)
def c_swsp(rs2,imm):   return 0xC002 | (((imm>>2)&0xF)<<9) | (((imm>>6)&3)<<7) | (rs2<<2)
def c_jr(rs1):         return 0x8002 | (rs1<<7)
def c_mv(rd,rs2):      return 0x8002 | (rd<<7) | (rs2<<2)
def c_jalr(rs1):       return 0x9002 | (rs1<<7)
def c_add(rd,rs2):     return 0x9002 | (rd<<7) | (rs2<<2)
C_NOP, C_EBREAK = 0x0001, 0x9002
FENCE, ECALL, EBREAK = 0x0000000F, 0x00000073, 0x00100073

def sgn(v):
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v >= 0x80000000 else v

def li(rd, val):
    s = sgn(val)
    hi = (s + 0x800) >> 12
    lo = s - (hi << 12)
    out = []
    if hi != 0: out.append((LUI(rd, hi & 0xFFFFF), 'lui  x%d, 0x%X' % (rd, hi & 0xFFFFF)))
    if hi == 0 or lo != 0:
        out.append((ADDI(rd, rd if hi else 0, lo), 'addi x%d, x%d, %d' % (rd, rd if hi else 0, lo)))
    return out

# ---------- 两遍汇编 ----------
items = []
def H(code, asm):        items.append(('h', code, asm))
def W(code, asm):        items.append(('w', code, asm))
def J16(mk, asm, tgt):   items.append(('j16', mk, asm, tgt))
def LI(rd, val):         items.append(('li', rd, val, None))
def LI_L(rd, lbl):       items.append(('lil', rd, lbl, None))
def LABEL(n):            items.append(('label', n))
def PAD2():              items.append(('pad2',))
def TOMB(slot):
    items.append(('li', 6, 0xDEAD, 'tomb li x6,0xDEAD'))
    items.append(('w', SW(6, slot, 0), 'tomb sw x6,0x%03X(x0)' % slot))

BASE = 0x2B8
LI(5, 0x100)
W(SW(0,0xF0,0),'sw x0,0xF0(x0) clear poison0'); W(SW(0,0xF4,0),'sw x0,0xF4(x0) clear poison1')
W(SW(0,0xF8,0),'sw x0,0xF8(x0) clear poison2'); W(SW(0,0xFC,0),'sw x0,0xFC(x0) clear poison3')
LI(2, 0x200)

H(c_li(8,15),'c.li x8,15');  H(c_addi(8,5),'c.addi x8,5 ->20');  W(SW(8,0,5),'sw x8,0(x5) RAM[64]=20')
H(c_lui(13,5),'c.lui x13,5 ->0x5000');                          W(SW(13,4,5),'sw x13,4(x5) RAM[65]=0x5000')
H(c_mv(9,8),'c.mv x9,x8 ->20'); H(c_add(9,8),'c.add x9,x8 ->40'); W(SW(9,8,5),'sw x9,8(x5) RAM[66]=40')
H(c_li(10,30),'c.li x10,30')
H(c_ca(0,2,0),'c.sub x10,x8 ->10'); H(c_ca(1,2,1),'c.xor x10,x9 ->34')
H(c_ca(2,2,0),'c.or x10,x8 ->54');  H(c_ca(3,2,1),'c.and x10,x9 ->32')
W(SW(10,12,5),'sw x10,12(x5) RAM[67]=32')
H(c_li(11,3),'c.li x11,3'); H(c_slli(11,4),'c.slli x11,4 ->48'); H(c_srli(3,1),'c.srli x11,1 ->24')
W(SW(11,16,5),'sw x11,16(x5) RAM[68]=24')
H(c_li(12,-8),'c.li x12,-8'); H(c_srai(4,2),'c.srai x12,2 ->-2'); H(c_andi(4,15),'c.andi x12,15 ->14')
W(SW(12,20,5),'sw x12,20(x5) RAM[69]=14')
LI(13, 0x100)
H(c_sw(0,28,5),'c.sw x8,28(x13) RAM[71]=20')
H(c_lw(7,28,5),'c.lw x15,28(x13) ->20')
H(c_add(15,15),'c.add x15,x15 ->40 (16-bit load-use consumer)')
W(SW(15,24,5),'sw x15,24(x5) RAM[70]=40')
H(c_addi16sp(-32),'c.addi16sp -32 ->x2=0x1E0')
H(c_swsp(8,0),'c.swsp x8,0(x2) RAM[120]=20')
H(c_lwsp(14,0),'c.lwsp x14,0(x2) ->20')
W(SW(14,32,5),'sw x14,32(x5) RAM[72]=20')
H(c_addi4spn(6,64),'c.addi4spn x14,64 ->x14=0x220')
W(SW(14,36,5),'sw x14,36(x5) RAM[73]=0x220')
LI(2, 0x200)

J16(c_j,'c.j L1','L1'); TOMB(0xF0)
LABEL('L1')
H(c_li(8,0),'c.li x8,0')
J16(lambda o: c_beqz(0,o),'c.beqz x8,L2','L2'); TOMB(0xF4)
LABEL('L2')
J16(lambda o: c_bnez(0,o),'c.bnez x8,LBAD not-taken','LBAD')
H(c_li(8,7),'c.li x8,7')
J16(lambda o: c_bnez(0,o),'c.bnez x8,L3 taken','L3')
LABEL('LBAD'); TOMB(0xF8)
LABEL('L3')
J16(c_jal,'c.jal L4','L4'); TOMB(0xFC)
LABEL('L4')
W(SW(1,40,5),'sw x1,40(x5) RAM[74]=c.jal addr+2')

PAD2()
LI_L(9,'L5'); H(c_jr(9),'c.jr x9 -> L5(halfword addr)'); TOMB(0xF0)
PAD2()
LABEL('L5')
H(c_li(8,31),'c.li x8,31'); H(c_addi(8,11),'c.addi x8,11 ->42')
W(SW(8,44,5),'sw x8,44(x5) RAM[75]=42')

LI_L(9,'L6'); H(c_jalr(9),'c.jalr x9 x1=PC+2 -> L6'); TOMB(0xF4)
LABEL('L6')
W(SW(1,48,5),'sw x1,48(x5) RAM[76]=c.jalr addr+2')

for k in range(6):
    H(C_NOP, 'c.nop align-torture%d' % k)
    for code, asm in li(6, (0x11111*(k+1) << 12) & 0xFFFFF000):
        W(code, 'torture%d: %s' % (k, asm))
H(c_li(6,25),'c.li x6,25'); H(c_addi(6,25),'c.addi x6,25 ->50')
H(c_addi(6,25),'c.addi x6,25 ->75'); H(c_addi(6,3),'c.addi x6,3 ->78')
W(SW(6,52,5),'sw x6,52(x5) RAM[77]=78')

W(FENCE,'fence -> nop'); W(ECALL,'ecall -> nop'); W(EBREAK,'ebreak -> nop'); H(C_EBREAK,'c.ebreak -> nop')
H(c_li(8,25),'c.li x8,25'); H(c_addi(8,25),'c.addi x8,25 ->50')
H(c_addi(8,25),'c.addi x8,25 ->75'); H(c_addi(8,25),'c.addi x8,25 ->100')
W(SW(8,56,5),'sw x8,56(x5) RAM[78]=100 (sys instr side-effect free)')

RESTORE = [(1,0x14C),(2,0xFFFFFFFD),(5,0x12345000),(6,0x1144),(8,0x8F123456),(9,0x56),
           (10,0xFFFFFF8F),(11,0x8F),(12,0xFFFF8F12),(13,0x8F12),(14,0x3456),(15,0xFFFFFFAA)]
for rd, val in RESTORE:
    for code, asm in li(rd, val):
        W(code, 'restore: ' + asm)
W(0x00000063,'beq x0,x0,0 dead loop')

# ---- pass 1 ----
labels, addr = {}, {}
a, i = BASE, 0
for it in items:
    if it[0]=='label': labels[it[1]] = a
    elif it[0]=='pad2':
        while a%4!=2: a+=2
    elif it[0] in ('h','j16'): addr[i]=a; a+=2
    elif it[0]=='w': addr[i]=a; a+=4
    elif it[0]=='li': addr[i]=a; a+=4*len(li(it[1], it[2]))
    elif it[0]=='lil': addr[i]=a; a+=4
    i+=1

assert labels['L5'] % 4 == 2, 'L5 not halfword-aligned: 0x%X' % labels['L5']

# ---- pass 2 ----
halfs = []
a, i = BASE, 0
for it in items:
    k = it[0]
    if k=='label': i+=1; continue
    if k=='pad2':
        while a%4!=2: halfs.append((a,C_NOP,'c.nop (PAD2)')); a+=2
        i+=1; continue
    if k=='h':
        halfs.append((a, it[1], it[2])); a+=2
    elif k=='j16':
        off = labels[it[3]] - a
        halfs.append((a, it[1](off) if callable(it[1]) else it[1], '%s (off=%d)' % (it[2], off))); a+=2
    elif k=='w':
        halfs.append((a, it[1]&0xFFFF, it[2]+' [lo]')); a+=2
        halfs.append((a, (it[1]>>16)&0xFFFF, it[2]+' [hi]')); a+=2
    elif k=='li':
        for code, asm in li(it[1], it[2]):
            t = (it[3]+' ' if it[3] else '') + asm
            halfs.append((a, code&0xFFFF, t+' [lo]')); a+=2
            halfs.append((a, (code>>16)&0xFFFF, t+' [hi]')); a+=2
    elif k=='lil':
        val = labels[it[2]]
        assert val < 0x800, 'label %s too far' % it[2]
        code = ADDI(it[1], 0, val)
        halfs.append((a, code&0xFFFF, 'addi x%d,x0,0x%X [lo]' % (it[1], val))); a+=2
        halfs.append((a, (code>>16)&0xFFFF, 'addi x%d,x0,0x%X [hi]' % (it[1], val))); a+=2
    i+=1

dead = halfs[-1][0]
end_idx = halfs[-1][0]//4
print('RVC section: %d words, dead loop @ 0x%03X (imem[%d])' % (end_idx - BASE//4 + 1, dead, end_idx))
print('L5 = 0x%03X (mod4=%d), L6 = 0x%03X (mod4=%d)' % (labels['L5'], labels['L5']%4, labels['L6'], labels['L6']%4))

# ---- imem lines ----
words = {}
for ad, code, asm in halfs:
    w = ad//4; hi = (ad%4)==2
    cur = words.get(w, [0, []])
    cur[0] |= (code << 16) if hi else code
    if asm not in cur[1]: cur[1].append(asm)
    words[w] = cur
lines = []
for w in sorted(words):
    if w < BASE//4: continue
    asm = ' ; '.join(words[w][1])
    lines.append("        imem[%d] = 32'h%08X;  // 0x%03X: %s" % (w, words[w][0], w*4, asm))
section = '\n'.join(lines)

# ---- checks ----
jal_a  = [h[0] for h in halfs if h[2].startswith('c.jal L4')][0]
jalr_a = [h[0] for h in halfs if h[2].startswith('c.jalr')][0]
chks = [
 (64,  20,        'C: li/addi'),
 (65,  0x5000,    'C: lui'),
 (66,  40,        'C: mv/add'),
 (67,  32,        'C: sub/xor/or/and'),
 (68,  24,        'C: slli/srli'),
 (69,  14,        'C: srai/andi'),
 (70,  40,        'C: lw load-use'),
 (71,  20,        'C: sw'),
 (120, 20,        'C: addi16sp+swsp'),
 (72,  20,        'C: lwsp'),
 (73,  0x220,     'C: addi4spn'),
 (74,  jal_a+2,   'C: jal link'),
 (75,  42,        'C: jr halfword'),
 (76,  jalr_a+2,  'C: jalr link'),
 (77,  78,        'C: align mix'),
 (78,  100,       'C: sys nop'),
 (60,  0,         'C: poison0'),
 (61,  0,         'C: poison1'),
 (62,  0,         'C: poison2'),
 (63,  0,         'C: poison3'),
]
chk_txt = '\n'.join('        chk(soc.bus_slave.RAM[%d], 32\'h%08X, "%s");' % (i, v, n) for i, v, n in chks)
total = 56 + len(chks)

# ================= patch TB =================
p = r'D:\study\cs\nizhou\pipe\project_1.srcs\sim_1\new\soc_axi_tb.v'
s = io.open(p, encoding='gbk').read()
s = s.replace('reg  [31:0] imem [0:191];', 'reg  [31:0] imem [0:319];')
s = s.replace('for (k = 0; k < 192; k = k + 1)', 'for (k = 0; k < 320; k = k + 1)')
s = s.replace('    reg  [31:0] Instr;', '    reg  [31:0] Instr;\n    reg  [31:0] InstrN;')
s = s.replace('    always @(*) Instr = imem[PC[31:2]];',
              '    always @(*) Instr  = imem[PC[31:2]];\n    always @(*) InstrN = imem[PC[31:2] + 1];   // RVC crossing read')
s = s.replace('        .Instr     (Instr),', '        .Instr     (Instr),\n        .InstrN    (InstrN),')

old_tail = "        imem[174] = 32'h00000063;  // 0x2B8: beq  x0, x0, 0"
assert old_tail in s, 'dead loop line not found'
s = s.replace(old_tail, '        // ---------- RVC: 16/32 mix, crossing fetch, compressed jumps, sys-nop ----------\n' + section)

s = s.replace('repeat(900) @(posedge clk);', 'repeat(1400) @(posedge clk);')
s = s.replace('$display(" PC = %h (\u6b7b\u5faa\u73af\u5e94\u5728 000002b8 \u9644\u8fd1)", PC);',
              '$display(" PC = %%h (\u6b7b\u5faa\u73af\u5e94\u5728 %08x \u9644\u8fd1)", PC);' % dead)

old_last_chk = '        chk(soc.bus_slave.RAM[24], 32\'h00000014, "M: div\u540e\u8bbf\u5b58");'
assert old_last_chk in s, 'last M chk not found'
s = s.replace(old_last_chk, old_last_chk + '\n\n        // ---------- RVC + sys-nop ----------\n' + chk_txt)
s = s.replace('$display(" ALL TESTS PASSED  (56 \u9879, RV32IM + AXI4-Lite)");',
              '$display(" ALL TESTS PASSED  (%d \u9879, RV32IMC + AXI4-Lite)");' % total)
io.open(p, 'w', encoding='gbk').write(s)
print('TB patched: total checks %d' % total)
