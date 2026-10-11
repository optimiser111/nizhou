const PptxGenJS = require('pptxgenjs');
const pres = new PptxGenJS();
pres.layout = 'LAYOUT_16x9';

const colors = {
  dark: '0F1C2E',
  primary: '1E3A5F',
  secondary: '2E5A8B',
  accent: '00B4D8',
  light: 'F4F6F8',
  textLight: 'FFFFFF',
  textDark: '1A1A1A',
  green: '2E7D32',
  orange: 'F57C00'
};

function titleStyle(size = 36) {
  return { fontSize: size, fontFace: 'Cambria', bold: true, color: colors.textLight };
}
function bodyStyle(color = colors.textDark, size = 16) {
  return { fontSize: size, fontFace: 'Calibri', color: color };
}
function subtitleStyle() {
  return { fontSize: 20, fontFace: 'Calibri', color: colors.accent };
}

// Slide 1: Title
let slide = pres.addSlide();
slide.background = { color: colors.dark };
slide.addText('基于 RISC-V 的五级流水线 CPU 设计与实现', {
  x: 0.5, y: 2.2, w: 9, h: 1.2,
  ...titleStyle(40), align: 'center'
});
slide.addText('逆舟实验室面试评估项目（Nizhou Lab Assessment）', {
  x: 0.5, y: 3.5, w: 9, h: 0.6,
  ...subtitleStyle(), align: 'center'
});
slide.addShape('ROUNDED_RECTANGLE', {
  x: 4.25, y: 4.4, w: 1.5, h: 0.45, fill: colors.accent, rectRadius: 0.2
});
slide.addText('2026.10', {
  x: 4.25, y: 4.4, w: 1.5, h: 0.45,
  fontSize: 14, fontFace: 'Calibri', color: colors.textLight, align: 'center'
});

// Slide 2: Deliverable Checklist
slide = pres.addSlide();
slide.addText('交付清单与完成情况', { x: 0.5, y: 0.4, w: 9, h: 0.7, ...titleStyle(36), color: colors.primary });
let rows = [
  [{ text: '交付项', options: { bold: true, fill: colors.primary, color: colors.textLight } },
   { text: '具体要求', options: { bold: true, fill: colors.primary, color: colors.textLight } },
   { text: '权重 / 状态', options: { bold: true, fill: colors.primary, color: colors.textLight } }],
  ['微架构设计文档', '数据通路图、FSM、指令子集清单', '35% ✅'],
  ['RTL 工程源码', '完整 Verilog/SV 与核心 Testbench', '35% ✅'],
  ['仿真报告与波形', 'EDA 仿真截图及文字说明', '30% ✅'],
  ['进阶加分项', '多级流水线 / 标准总线 / FPGA 上板 Demo', '+20% 待做']
];
slide.addTable(rows, {
  x: 0.5, y: 1.3, w: 9, h: 3.8,
  fontSize: 16, fontFace: 'Calibri', color: colors.textDark,
  fill: { color: colors.light }, border: { pt: 1, color: 'D0D0D0' },
  colW: [2.4, 5.0, 1.6], valign: 'middle'
});
slide.addText('本汇报基于实际完成的 RTL 工程与仿真结果，三项基础交付已全部验证通过。', {
  x: 0.5, y: 5.3, w: 9, h: 0.5, ...bodyStyle(colors.secondary, 15), italic: true
});

// Slide 3: ISA
slide = pres.addSlide();
slide.addText('指令集架构：RV32I 基础整数集（37 条）', { x: 0.5, y: 0.4, w: 9, h: 0.7, ...titleStyle(36), color: colors.primary });
let isaRows = [
  [{ text: '类别', options: { bold: true, fill: colors.primary, color: colors.textLight } },
   { text: '指令', options: { bold: true, fill: colors.primary, color: colors.textLight } },
   { text: '数量', options: { bold: true, fill: colors.primary, color: colors.textLight } }],
  ['R 型运算', 'add / sub / and / or / xor / sll / srl / sra / slt / sltu', '10'],
  ['I 型运算', 'addi / andi / ori / xori / slli / srli / srai / slti / sltiu', '9'],
  ['Load', 'lb / lh / lw / lbu / lhu', '5'],
  ['Store', 'sb / sh / sw', '3'],
  ['Branch', 'beq / bne / blt / bge / bltu / bgeu', '6'],
  ['跳转 / U 型', 'jal / jalr / lui / auipc', '4']
];
slide.addTable(isaRows, {
  x: 0.5, y: 1.3, w: 9, h: 3.6,
  fontSize: 14, fontFace: 'Calibri', color: colors.textDark,
  fill: { color: colors.light }, border: { pt: 1, color: 'D0D0D0' },
  colW: [1.6, 6.0, 1.4], valign: 'middle'
});
slide.addText('六种指令格式全部覆盖：R / I / S / B / U / J', {
  x: 0.5, y: 5.1, w: 9, h: 0.4,
  ...subtitleStyle(), align: 'center'
});

// Slide 4: Pipeline stages
slide = pres.addSlide();
slide.addText('五级流水线微架构', { x: 0.5, y: 0.4, w: 9, h: 0.7, ...titleStyle(36), color: colors.primary });
let stages = ['IF', 'ID', 'EX', 'MEM', 'WB'];
let x0 = 0.6;
let y0 = 2.0;
let boxW = 1.6;
let boxH = 1.0;
stages.forEach((s, i) => {
  let x = x0 + i * (boxW + 0.2);
  slide.addShape('ROUNDED_RECTANGLE', { x: x, y: y0, w: boxW, h: boxH, fill: colors.primary, rectRadius: 0.1 });
  slide.addText(s, { x: x, y: y0 + 0.25, w: boxW, h: 0.5,
    fontSize: 28, fontFace: 'Cambria', bold: true, color: colors.textLight, align: 'center' });
  let labels = [
    'PC+4\n取指',
    '译码\n读寄存器',
    'ALU\n分支/跳转',
    '访存\n字节使能',
    '写回\n结果选择'
  ];
  slide.addText(labels[i], { x: x, y: y0 + 1.15, w: boxW, h: 0.8,
    fontSize: 12, fontFace: 'Calibri', color: colors.textDark, align: 'center' });
  if (i < stages.length - 1) {
    slide.addShape('RIGHT_ARROW', { x: x + boxW + 0.02, y: y0 + 0.35, w: 0.18, h: 0.3, fill: colors.accent });
  }
});
slide.addText('流水线寄存器：F_D / D_E / E_M / M_W，含 stall/flush 控制', {
  x: 0.5, y: 4.4, w: 9, h: 0.5,
  ...bodyStyle(colors.secondary, 16), align: 'center', italic: true
});

// Slide 5: Datapath blocks
slide = pres.addSlide();
slide.addText('数据通路核心模块', { x: 0.5, y: 0.4, w: 9, h: 0.7, ...titleStyle(36), color: colors.primary });
let blocks = [
  ['riscvpipe', '顶层模块：连接 controller 与 datapath'],
  ['controller', '组合译码：maindec + aludec，输出控制信号'],
  ['datapath', '五级数据通路 + 冒险单元 Hazard'],
  ['regfile', '32 个通用寄存器，negedge 写避免同拍竞争'],
  ['ALU', '支持 add/sub/and/or/xor/slt/sltu/移位/直通'],
  ['load_ext', 'WB 级字节/半字抽取（lb/lh/lbu/lhu）'],
  ['Hazard', '前推 + load-use 停顿 + 分支冲刷']
];
blocks.forEach((b, i) => {
  let row = Math.floor(i / 2);
  let col = i % 2;
  let x = 0.5 + col * 4.7;
  let y = 1.4 + row * 1.35;
  slide.addShape('ROUNDED_RECTANGLE', { x: x, y: y, w: 4.3, h: 1.1, fill: colors.light, rectRadius: 0.1,
    line: { color: colors.accent, pt: 1.5 } });
  slide.addText(b[0], { x: x + 0.15, y: y + 0.15, w: 4.0, h: 0.4,
    fontSize: 18, fontFace: 'Cambria', bold: true, color: colors.primary });
  slide.addText(b[1], { x: x + 0.15, y: y + 0.55, w: 4.0, h: 0.5,
    fontSize: 13, fontFace: 'Calibri', color: colors.textDark });
});

// Slide 6: Hazard handling
slide = pres.addSlide();
slide.addText('冒险处理：前推 + 停顿 + 冲刷', { x: 0.5, y: 0.4, w: 9, h: 0.7, ...titleStyle(36), color: colors.primary });
let hazards = [
  ['01', 'MEM/WB 前推', 'ALU 源操作数来自刚写回的寄存器', 'EX 级源寄存器 == RdW 且 RegWriteW'],
  ['10', 'EX/MEM 前推', '上一条 ALU 结果直接送给当前 EX 级', 'EX 级源寄存器 == RdM 且 RegWriteM'],
  ['Stall', 'load-use 停顿', 'lw/lb/lh 紧跟消费者时冻结 PC/IF_ID', 'ResultSrcE[0] & (Rs1D==RdE | Rs2D==RdE)'],
  ['Flush', '分支/跳转冲刷', 'taken 分支或 jal/jalr 清空 ID/EX', 'FlushD=PCSrcE, FlushE=lwStall|PCSrcE']
];
hazards.forEach((h, i) => {
  let y = 1.3 + i * 1.05;
  slide.addShape('ELLIPSE', { x: 0.5, y: y + 0.05, w: 0.55, h: 0.55, fill: colors.accent });
  slide.addText(h[0], { x: 0.5, y: y + 0.12, w: 0.55, h: 0.4,
    fontSize: 16, fontFace: 'Cambria', bold: true, color: colors.textLight, align: 'center' });
  slide.addText(h[1], { x: 1.3, y: y + 0.05, w: 2.0, h: 0.35,
    fontSize: 17, fontFace: 'Cambria', bold: true, color: colors.primary });
  slide.addText(h[2], { x: 1.3, y: y + 0.42, w: 4.0, h: 0.35,
    fontSize: 13, fontFace: 'Calibri', color: colors.textDark });
  slide.addText(h[3], { x: 5.5, y: y + 0.12, w: 4.0, h: 0.6,
    fontSize: 12, fontFace: 'Courier New', color: colors.secondary, fontFace: 'Calibri' });
});

// Slide 7: Verification strategy
slide = pres.addSlide();
slide.addText('验证策略与高覆盖率 Testbench', { x: 0.5, y: 0.4, w: 9, h: 0.7, ...titleStyle(36), color: colors.primary });
let verRows = [
  ['验证方法', '覆盖点'],
  ['机器码脚本生成', '用 Python 精确生成 RV32I 编码，避免手算 hex 出错'],
  ['墓碑法（Tombstone）', 'taken 分支后跟两条写同一寄存器的 addi，冲刷失败即被抓'],
  ['符号/零扩展对照', 'lb vs lbu、lh vs lhu 同地址读出结果相反，验证 load_ext'],
  ['sb+sh 拼回', '先写字节/半字，再用 lw 读回整字，验证字节使能'],
  ['load-use 停顿', 'lw/lb 后紧跟消费者，检查 StallF/StallD 拉高'],
  [' jal/jalr 往返', '函数调用 + 返回，验证链接地址与 PC 目标选择']
];
slide.addTable(verRows, {
  x: 0.5, y: 1.3, w: 9, h: 3.8,
  fontSize: 14, fontFace: 'Calibri', color: colors.textDark,
  fill: { color: colors.light }, border: { pt: 1, color: 'D0D0D0' },
  colW: [2.4, 6.6], valign: 'middle'
});

// Slide 8: Extension process
slide = pres.addSlide();
slide.addText('指令集扩展过程（4 个阶段）', { x: 0.5, y: 0.4, w: 9, h: 0.7, ...titleStyle(36), color: colors.primary });
let exts = [
  ['1', '基础 R/I 型', 'add/sub/and/or/slt + addi/andi/ori/slti', '13 条'],
  ['2', '移位与比较', 'xor/xori/sll/slli/srl/srli/sra/srai/sltu/sltiu', '23 条'],
  ['3', '分支齐套', 'bne/blt/bge/bltu/bgeu + lui/auipc/jalr', '31 条'],
  ['4', '字节/半字访存', 'lb/lh/lbu/lhu/sb/sh', '37 条']
];
exts.forEach((e, i) => {
  let y = 1.3 + i * 1.1;
  slide.addShape('ROUNDED_RECTANGLE', { x: 0.5, y: y, w: 9, h: 0.95, fill: colors.light, rectRadius: 0.08,
    line: { color: colors.accent, pt: 1 } });
  slide.addShape('ELLIPSE', { x: 0.7, y: y + 0.2, w: 0.55, h: 0.55, fill: colors.primary });
  slide.addText(e[0], { x: 0.7, y: y + 0.27, w: 0.55, h: 0.4,
    fontSize: 18, fontFace: 'Cambria', bold: true, color: colors.textLight, align: 'center' });
  slide.addText(e[1], { x: 1.5, y: y + 0.15, w: 2.2, h: 0.35,
    fontSize: 17, fontFace: 'Cambria', bold: true, color: colors.primary });
  slide.addText(e[2], { x: 1.5, y: y + 0.52, w: 5.0, h: 0.35,
    fontSize: 13, fontFace: 'Calibri', color: colors.textDark });
  slide.addText(e[3], { x: 7.0, y: y + 0.25, w: 1.4, h: 0.45,
    fontSize: 18, fontFace: 'Cambria', bold: true, color: colors.green, align: 'center' });
});

// Slide 9: Results
slide = pres.addSlide();
slide.addText('仿真验证结果', { x: 0.5, y: 0.4, w: 9, h: 0.7, ...titleStyle(36), color: colors.primary });
slide.addShape('ROUNDED_RECTANGLE', { x: 2.5, y: 1.6, w: 5, h: 1.4, fill: colors.green, rectRadius: 0.15 });
slide.addText('ALL TESTS PASSED', { x: 2.5, y: 1.75, w: 5, h: 0.7,
  fontSize: 36, fontFace: 'Cambria', bold: true, color: colors.textLight, align: 'center' });
slide.addText('39 项断言，覆盖 37 条 RV32I 指令', { x: 2.5, y: 2.4, w: 5, h: 0.4,
  fontSize: 16, fontFace: 'Calibri', color: colors.textLight, align: 'center' });
let resultBullets = [
  'R 型 / I 型 ALU：加减、逻辑、比较、移位全部通过',
  '访存：sw/lw、sb/sh/lb/lh/lbu/lhu 字节/半字对齐正确',
  '分支：beq/bne/blt/bge/bltu/bgeu taken/not-taken + 冲刷验证',
  '跳转：jal/jalr 链接地址、函数往返、jalr 目标来自 load 结果',
  '最终 PC 稳定在 0x1D4 附近三点循环（死循环预期行为）'
];
slide.addText(resultBullets.map(t => ({ text: t, options: { bullet: true } })), {
  x: 1.0, y: 3.4, w: 8, h: 2.2,
  fontSize: 15, fontFace: 'Calibri', color: colors.textDark,
  paraSpaceAfter: 8, lineSpacing: 22
});

// Slide 10: Conclusion
slide = pres.addSlide();
slide.background = { color: colors.dark };
slide.addText('总结与后续计划', { x: 0.5, y: 0.6, w: 9, h: 0.8, ...titleStyle(38) });
let conclusionItems = [
  '已完成：五级流水线、RV32I 37 条指令、39 项断言 100% 通过',
  '已完成：三级冒险处理（前推 / 停顿 / 冲刷），无气泡设计正确',
  '下一步：构建 soc_top，集成 ROM/RAM 与 LED MMIO，跑综合布局布线',
  '加分项：FPGA 物理上板 Demo（xc7k325tffg900-2 / Vivado 2018.3）'
];
conclusionItems.forEach((item, i) => {
  let y = 1.8 + i * 0.9;
  slide.addShape('ELLIPSE', { x: 0.7, y: y + 0.12, w: 0.3, h: 0.3, fill: colors.accent });
  slide.addText(item, { x: 1.2, y: y, w: 8, h: 0.6,
    fontSize: 18, fontFace: 'Calibri', color: colors.textLight });
});
slide.addText('谢谢', { x: 0.5, y: 5.0, w: 9, h: 0.6,
  fontSize: 24, fontFace: 'Cambria', bold: true, color: colors.accent, align: 'center' });

const outPath = 'D:\\study\\cs\\nizhou\\pipe\\report\\RISCV_Pipeline_CPU_Report.pptx';
pres.writeFile({ fileName: outPath })
  .then(() => console.log('PPT saved to:', outPath))
  .catch(err => { console.error(err); process.exit(1); });
