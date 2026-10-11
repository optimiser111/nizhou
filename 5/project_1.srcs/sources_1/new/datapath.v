module datapath(
    input clk,
    input reset,
    // 来自 controller 的控制信号（译码阶段产生）
    input [1:0]  ResultSrc,
    input        MemWrite,
    input        Branch,
    input        ALUSrc,
    input        RegWrite,
    input        Jump,
    input [2:0]  ImmSrc,           // ★ 2 位改 3 位（U 型）
    input [3:0]  ALUControl,       // ★ 3 位改 4 位
    input        Jalr,             // ★ 新增：jalr 目标用 rs1+imm
    output       ZeroE,
    output [31:0] InstrD,
    output       MemWriteM,
    output [31:0] PC,
    input  [31:0] Instr,
    input  [31:0] InstrN,       // ★ RVC：imem[PC[31:2]+1]，跨字装配用
    output [31:0] ALUResult,
    output [31:0] WriteData,
    input  [31:0] ReadData,
    output [3:0]  ByteEn,
    output        MemReadM,     // ★ AXI：MEM 级是 load（ResultSrcM==01）
    input         MemStall,     // ★ AXI：总线等待，冻结全部流水寄存器
    input         MExt          // ★ RV32M：ID 级乘除指令标记（流水到 EX 用）
);
    
    wire [2:0]  funct3M, funct3W;
    wire [31:0] WriteDataAlnM;     // 对齐后的写数据
    reg  [3:0]  ByteEnM;
    wire [31:0] ReadDataExtW;      // load_ext 输出
   
    // ============ IF 阶段 ============
    wire [31:0] PCF, PCNextF, PCPlus4F;
    wire [31:0] InstrF;

    // ============ IF/ID 寄存器输出 ============
    wire [31:0] PCD, PCPlus4D;

    // ============ ID 阶段 ============
    wire [31:0] RD1D, RD2D;
    wire [31:0] ImmExtD;
    wire [4:0]  Rs1D, Rs2D, RdD;
    wire        PredTakenD;            // ★ 分支预测：IF 级预测位（随指令下行）

    // ============ ID/EX 寄存器输出 ============
    wire [1:0]  ResultSrcE;
    wire        MemWriteE, BranchE, ALUSrcE, RegWriteE, JumpE;
    wire [3:0]  ALUControlE;       // ★ 3 位改 4 位
    wire [31:0] RD1E, RD2E, PCE, ImmExtE, PCPlus4E;
    wire [4:0]  RdE;
    wire [4:0]  Rs1E, Rs2E;
    wire [2:0]  funct3E;
    wire        LessE, LessUE, BranchTakenE;
    wire        PredTakenE;            // ★ 分支预测：EX 级校验用
    wire        MispredictE;           // ★ 预测失败（方向错误）


    // ============ EX 阶段 ============
    wire [31:0] SrcAE, SrcBE;
    wire [31:0] WriteDataE;
    wire [31:0] ALUResultE;
    wire [31:0] PCTargetE;
    wire [31:0] PCTargetFinalE;    // ★ jalr 选择后的跳转目标
    wire        JalrE;
    wire        PCSrcE;
    wire [1:0]  ForwardAE, ForwardBE;

    // ============ 冒险控制信号 ============
    wire        StallF, StallD, FlushE;
    wire        MExtE;               // ★ RV32M：EX 级乘除标记
    wire        DivStall;            // ★ RV32M：除法未完成，冻结全流水线
    wire        StallAll;            // MemStall(AXI) | DivStall(除法)
    wire [31:0] ALUOutE;             // ALU 原始输出（M 扩展 mux 之前）

    // ============ EX/MEM 寄存器输出 ============
    wire        RegWriteM;
    wire        MemWriteM_int;     // E_M 原始 MemWriteM（门控前）
    wire [1:0]  ResultSrcM;
    wire [31:0] ALUResultM, WriteDataM, PCPlus4M;
    wire [31:0] PCTargetM;         // ★ auipc 结果锁存
    wire [4:0]  RdM;
    wire FlushD;
    // ============ MEM/WB 寄存器输出 ============
    wire        RegWriteW;
    wire [1:0]  ResultSrcW;
    wire [31:0] ALUResultW, ReadDataW, PCPlus4W;
    wire [31:0] PCTargetW;         // ★ auipc 结果锁存
    wire [4:0]  RdW;

    // ============ WB 阶段 ============
    wire [31:0] ResultW;
    wire [31:0] ResultW_pre;       // ★ resultmux 输出（auipc 前）

    // ============ 输出映射 ============
    assign PC        = PCF;
    assign ALUResult = ALUResultM;
    assign WriteData = WriteDataAlnM;

    // ID 阶段拆指令字段
    assign Rs1D = InstrD[19:15];
    assign Rs2D = InstrD[24:20];
    assign RdD  = InstrD[11:7];

    // ============ EX 阶段：PC 选择 ============
        // 比较用前推后的 SrcAE/SrcBE，ZeroE 仍是 ALU 减法的判零
    assign LessE  = ($signed(SrcAE) < $signed(SrcBE));   // 有符号小于
    assign LessUE = (SrcAE < SrcBE);                     // 无符号小于

    assign BranchTakenE = BranchE & (
            (funct3E == 3'b000) &  ZeroE  |   // beq
            (funct3E == 3'b001) & ~ZeroE  |   // bne
            (funct3E == 3'b100) &  LessE  |   // blt
            (funct3E == 3'b101) & ~LessE  |   // bge
            (funct3E == 3'b110) &  LessUE |   // bltu
            (funct3E == 3'b111) & ~LessUE );  // bgeu

    // ★ 分支预测：EX 级重定向只剩两种——
    //   1) 分支预测失败恢复（实际方向 ^ 预测方向）
    //   2) jalr（目标依赖寄存器，IF 级无法预测，维持原 EX 定向）
    //   jal 与预测跳的分支已在 IF 级重定向；预测/实际均不跳则零开销。
    assign MispredictE = BranchE & (BranchTakenE ^ PredTakenE);
    assign PCSrcE = MispredictE | (JumpE & JalrE);


    // ============================================
    // IF 阶段：RVC 取指对齐 + 解压
    // ============================================
    // hbuf：半字缓冲。当前指令的起始半字可能来自上一个已取字的高半
    // （PC ≡ 2 mod 4）。取指每拍至多读一个字：
    //   对齐（!hbuf_valid && PCF[1]==0）  -> 用 Instr = imem[PC[31:2]]
    //   跨字                              -> 用 InstrN = imem[PC[31:2]+1] 的低半拼接
    reg  [15:0] hbuf;
    reg         hbuf_valid;
    wire [15:0] cur16   = hbuf_valid ? hbuf : (PCF[1] ? Instr[31:16] : Instr[15:0]);
    wire        is32    = (cur16[1:0] == 2'b11);       // 低两位 11 = 32 位指令
    wire        aligned = ~hbuf_valid & ~PCF[1];
    wire [31:0] instr_asm = is32 ? (aligned ? Instr : {InstrN[15:0], cur16})
                                 : {16'h0000, cur16};
    wire [31:0] instr_exp;                              // 解压结果
    wire        is_c;
    c_expand c_ext(.cin(instr_asm), .dout(instr_exp), .is_c(is_c));
    assign InstrF = is_c ? instr_exp : instr_asm;      // 下游只见标准 32 位指令

    // 顺序下一 PC：压缩指令 +2，普通指令 +4（链接/auipc 均用此值，语义正确）
    assign PCPlus4F = PCF + (is_c ? 32'd2 : 32'd4);

    // ============================================
    // IF 阶段：分支预测（BHT 方向 + 立即数目标）
    // ============================================
    // InstrF 在 IF 当拍组合可得（imem 组合读 + 解压器），因此
    // 分支/jal 在 IF 即可译码并重定向，预测命中零气泡：
    //   jal（含 c.j/c.jal 解压形式）-> 无条件重定向
    //   分支（含 c.beqz/c.bnez 解压形式）-> BHT 预测跳则重定向
    // 目标直接由指令立即数算出（非 BTB），故方向是唯一预测量，
    // 预测失败只可能错方向、不可能错目标。
    wire        f_branch = (InstrF[6:0] == 7'b1100011);
    wire        f_jal    = (InstrF[6:0] == 7'b1101111);
    wire [31:0] f_bimm   = {{20{InstrF[31]}}, InstrF[7], InstrF[30:25], InstrF[11:8], 1'b0};
    wire [31:0] f_jimm   = {{12{InstrF[31]}}, InstrF[19:12], InstrF[20], InstrF[30:21], 1'b0};
    wire        bht_taken_f;
    wire [31:0] PCTargetF = PCF + (f_jal ? f_jimm : f_bimm);
    wire        PredRedirectF = f_jal | (f_branch & bht_taken_f);
    wire        PredTakenF    = f_branch & bht_taken_f;   // 仅分支需携带预测位

    bpu #(10) branch_predictor(
        .clk          (clk),
        .reset        (reset),
        .pc_f         (PCF),
        .pred_taken_f (bht_taken_f),
        .upd_en       (BranchE & ~StallAll),   // 冻结期间不更新，每条分支恰一次
        .upd_pc       (PCE),
        .upd_taken    (BranchTakenE),
        .upd_pred     (PredTakenE),
        .stat_pred    (),                      // TB 分层引用读取
        .stat_miss    ()
    );

    // hbuf 更新：重定向（分支/跳转命中）清空重新对齐；stall 时整体保持
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            hbuf <= 16'h0000; hbuf_valid <= 1'b0;
        end else if (~(StallF | StallAll)) begin
            if (PCSrcE | PredRedirectF) begin
                hbuf_valid <= 1'b0;                     // 重定向（EX 恢复 / IF 预测）后按目标地址重新对齐
            end else if (is32) begin
                hbuf       <= aligned ? 16'h0000 : InstrN[31:16];
                hbuf_valid <= ~aligned;                 // 跨字 32 位指令后仍停在高半
            end else begin
                hbuf       <= (hbuf_valid | PCF[1]) ? 16'h0000 : Instr[31:16];
                hbuf_valid <= ~(hbuf_valid | PCF[1]);   // 低半起步的 16 位指令消费后缓存高半
            end
        end
    end

    flopren pcreg(clk, reset, ~(StallF | StallAll), PCNextF, PCF);  // ★ 总线/除法等待冻结 PC
    // ★ EX 重定向目标选择：
    //   jalr        -> rs1+imm（ALU 结果，已前推），清 bit0
    //   预测失败    -> 实际跳：PCTargetE；实际不跳：PCPlus4E（顺序流）
    wire [31:0] RecoverTargetE = BranchTakenE ? PCTargetE : PCPlus4E;
    mux2 jtargetmux(RecoverTargetE, {ALUResultE[31:1], 1'b0}, JalrE, PCTargetFinalE);
    // ★ 下一 PC 优先级：EX 重定向（恢复/jalr） > IF 预测重定向 > 顺序
    //   EX 是更老的指令，预测失败时同拍 IF 级的预测重定向必须让路
    assign PCNextF = PCSrcE        ? PCTargetFinalE :
                     PredRedirectF ? PCTargetF      : PCPlus4F;

    // ============================================
    // IF/ID 寄存器
    // ============================================
    F_D f_d(
        .clk      (clk),
        .reset    (reset),
        .InstrF   (InstrF),
        .PCF      (PCF),
        .PCPlus4F (PCPlus4F),
        .PredTakenF(PredTakenF),
        .InstrD   (InstrD),
        .PCD      (PCD),
        .PCPlus4D (PCPlus4D),
        .PredTakenD(PredTakenD),
        .en       (~StallD & ~StallAll),
        .CLR      (FlushD)
        );

    // ============================================
    // ID 阶段
    // ============================================
    regfile rf(clk, RegWriteW, Rs1D, Rs2D, RdW, ResultW, RD1D, RD2D);
    extend ext(InstrD[31:7], ImmSrc, ImmExtD);

    // ============================================
    // ID/EX 寄存器
    // ============================================
    D_E d_e(
            .clk        (clk),
            .reset      (reset),
            .en         (~StallAll),
            .ResultSrcD (ResultSrc),
            .MemWriteD  (MemWrite),
            .BranchD    (Branch),
            .ALUSrcD    (ALUSrc),
            .RegWriteD  (RegWrite),
            .JumpD      (Jump),
            .ALUControlD(ALUControl),
            .RD1D       (RD1D),
            .RD2D       (RD2D),
            .PCD        (PCD),
            .RdD        (RdD),
            .ImmExtD    (ImmExtD),
            .PCPlus4D   (PCPlus4D),
            .Rs1D       (Rs1D),
            .Rs2D       (Rs2D),
            .ResultSrcE (ResultSrcE),
            .MemWriteE  (MemWriteE),
            .BranchE    (BranchE),
            .ALUSrcE    (ALUSrcE),
            .RegWriteE  (RegWriteE),
            .JumpE      (JumpE),
            .ALUControlE(ALUControlE),
            .RD1E       (RD1E),
            .RD2E       (RD2E),
            .PCE        (PCE),
            .RdE        (RdE),
            .ImmExtE    (ImmExtE),
            .PCPlus4E   (PCPlus4E),
            .Rs1E       (Rs1E),
            .Rs2E       (Rs2E),
            .CLR        (FlushE),
            .funct3D    (InstrD[14:12]),
            .funct3E    (funct3E),
            .JalrD      (Jalr),
            .JalrE      (JalrE),
            .MExtD      (MExt),
            .MExtE      (MExtE),
            .PredTakenD (PredTakenD),
            .PredTakenE (PredTakenE)
            );

    // ============================================
    // EX 阶段：前推 + ALU
    // ============================================
    Hazard hz(
        .Rs1E       (Rs1E),
        .Rs2E       (Rs2E),
        .RdM        (RdM),
        .RdW        (RdW),
        .RegWriteM  (RegWriteM),
        .RegWriteW  (RegWriteW),
        .ForwardAE  (ForwardAE),
        .ForwardBE  (ForwardBE),
        .StallF     (StallF),
        .StallD     (StallD),
        .Rs1D       (Rs1D),
        .Rs2D       (Rs2D),
        .FlushE     (FlushE),
        .ResultSrcE0(ResultSrcE[0]),
        .RdE        (RdE),
        .PCSrcE     (PCSrcE),
        .FlushD     (FlushD)
        );

    // ★ 分支预测暴露的前推缺口：EX 定向时代，jal 与消费者之间隔着 2 拍惩罚，
    //   消费者到达 EX 时 jal 已在 WB，前推网络只携带 ALUResultM 恰好够用；
    //   IF 预测把 jal 惩罚降为 0，紧随目标的消费者（EX 级）恰逢 jal 在 MEM 级——
    //   链接值（PC+4）不经过 ALU，必须按 ResultSrcM 选择正确的前推来源：
    //     10 = 链接值 PCPlus4M（jal/jalr）
    //     11 = auipc 结果 PCTargetM（顺带修复 auipc 紧邻消费者的同类隐患）
    wire [31:0] ForwardM = (ResultSrcM == 2'b10) ? PCPlus4M  :
                           (ResultSrcM == 2'b11) ? PCTargetM : ALUResultM;

    // SrcA 三选一：00=寄存器堆  01=WB前推  10=MEM前推
    mux3 forwardamux(RD1E, ResultW, ForwardM, ForwardAE, SrcAE);

    // SrcB：先前推（得 WriteDataE），再选立即数
    mux3 forwardbmux(RD2E, ResultW, ForwardM, ForwardBE, WriteDataE);
    mux2 srcbmux(WriteDataE, ImmExtE, ALUSrcE, SrcBE);

    ALU alu(SrcAE, SrcBE, ALUControlE, ALUOutE, ZeroE);
    adder pcaddbranch(PCE, ImmExtE, PCTargetE);

    // ============================================
    // EX 阶段：RV32M 乘除扩展
    // ============================================
    // 除法：多周期迭代（div32），结果未好时 DivStall 冻结整条流水线。
    //   操作数锁存的是"前推后"的 SrcAE/WriteDataE，进入 EX 当拍即正确。
    //   注意：总线事务期间上游是冻结的，除法不可能与 AXI 事务同时进行；
    //   而除法期间到达 MEM 级的访存指令，其请求被 ~DivStall 门控（见下方输出）。
    wire        IsDivE  = MExtE & funct3E[2];            // funct3=1xx：div/rem 系
    wire        div_start, div_busy, div_done;
    wire [31:0] div_q, div_r;

    assign div_start = IsDivE & ~div_busy & ~div_done;   // 空闲时进入 EX 即启动
    assign DivStall  = IsDivE & ~div_done;               // 结果未好则冻结
    // ack 必须等 EX 级"真正离开"（无 AXI 等待）才清 done：
    // 若完成当拍恰有 MEM 级访存事务（除法前的 store 被门控后补发），
    // MemStall 会把除法指令继续压在 EX，此时清 done 会导致除法器重复启动而死锁。
    wire        div_ack = IsDivE & div_done & ~MemStall;

    div32 mext_div(
        .clk   (clk),
        .reset (reset),
        .start (div_start),
        .sig   (~funct3E[0]),                           // DIV/REM 有符号，DIVU/REMU 无符号
        .a     (SrcAE),
        .b     (WriteDataE),                            // R 型 ALUSrc=0，即前推后 rs2
        .q     (div_q),
        .r     (div_r),
        .busy  (div_busy),
        .ack   (div_ack),
        .done  (div_done)
    );

    // 乘法：组合逻辑单拍出结果（综合时推断为 DSP48）
    wire signed [63:0] mul_ss = $signed(SrcAE) * $signed(WriteDataE);          // MUL/MULH
    wire        [63:0] mul_uu = SrcAE * WriteDataE;                            // MULHU
    wire signed [63:0] mul_su = $signed(SrcAE) * $signed({1'b0, WriteDataE});  // MULHSU

    wire [31:0] mul_result = (funct3E == 3'b000) ? mul_ss[31:0]   :   // MUL
                             (funct3E == 3'b001) ? mul_ss[63:32]  :   // MULH
                             (funct3E == 3'b010) ? mul_su[63:32]  :   // MULHSU
                                                   mul_uu[63:32];     // MULHU
    // DIV/DIVU funct3[1]=0 取商；REM/REMU funct3[1]=1 取余
    wire [31:0] div_result = funct3E[1] ? div_r : div_q;

    // M 扩展结果 mux：覆盖 ALU 输出（乘除指令的 ALU 运算结果弃用）
    assign ALUResultE = MExtE ? (funct3E[2] ? div_result : mul_result)
                              : ALUOutE;

    // 全流水线冻结 = AXI 总线等待 | 除法等待
    assign StallAll = MemStall | DivStall;

    // ============================================
    // EX/MEM 寄存器（★ 改按名连接，加 PCTarget 通路）
    // ============================================
    E_M e_m(
            .clk        (clk),
            .reset      (reset),
            .en         (~StallAll),
            .RegWriteE  (RegWriteE),
            .ResultSrcE (ResultSrcE),
            .MemWriteE  (MemWriteE),
            .ALUResultE (ALUResultE),
            .WriteDataE (WriteDataE),
            .RdE        (RdE),
            .PCPlus4E   (PCPlus4E),
            .PCTargetE  (PCTargetE),
            .RegWriteM  (RegWriteM),
            .ResultSrcM (ResultSrcM),
            .MemWriteM  (MemWriteM_int),
            .ALUResultM (ALUResultM),
            .WriteDataM (WriteDataM),
            .RdM        (RdM),
            .PCPlus4M   (PCPlus4M),
            .PCTargetM  (PCTargetM),
            .funct3E    (funct3E),
            .funct3M    (funct3M)
            );
            
                // ============ MEM 级：sb/sh 字节使能 + 写数据复制对齐 ============
    always @(*) begin
        case (funct3M)
            3'b000:  ByteEnM = 4'b0001 << ALUResultM[1:0];          // sb
            3'b001:  ByteEnM = 4'b0011 << {ALUResultM[1], 1'b0};    // sh
            default: ByteEnM = 4'b1111;                             // sw
        endcase
    end
    assign WriteDataAlnM = (funct3M == 3'b000) ? {4{WriteDataM[7:0]}}  :
                           (funct3M == 3'b001) ? {2{WriteDataM[15:0]}} :
                                                  WriteDataM;
    assign ByteEn   = MemWriteM ? ByteEnM : 4'b0000;
    // ★ RV32M 门控：除法冻结期间，MEM 级访存指令的请求被屏蔽，
    //   防止 AXI Master 对同一条 load/store 重复发起事务；
    //   除法结束后请求恢复，事务正常发起（见 datapath 内 DivStall 注释）。
    assign MemReadM  = (ResultSrcM == 2'b01) & ~DivStall;
    assign MemWriteM = MemWriteM_int & ~DivStall;
    // 原来的 assign WriteData = WriteDataM; 改成：
    //assign WriteData = WriteDataAlnM;

            
    // ============================================
    // MEM/WB 寄存器（★ 改按名连接，加 PCTarget 通路）
    // ============================================
    M_W m_w(
            .clk        (clk),
            .reset      (reset),
            .en         (~StallAll),
            .RegWriteM  (RegWriteM),
            .ResultSrcM (ResultSrcM),
            .ALUResultM (ALUResultM),
            .ReadDataM  (ReadData),
            .RdM        (RdM),
            .PCPlus4M   (PCPlus4M),
            .PCTargetM  (PCTargetM),
            .RegWriteW  (RegWriteW),
            .ResultSrcW (ResultSrcW),
            .ALUResultW (ALUResultW),
            .ReadDataW  (ReadDataW),
            .RdW        (RdW),
            .PCPlus4W   (PCPlus4W),
            .PCTargetW  (PCTargetW),
            .funct3M    (funct3M),
            .funct3W    (funct3W)
            );

    // ============================================
    // WB 阶段（★ auipc：ResultSrcW==11 时写回 PCTargetW）
    // ============================================
        load_ext le(ReadDataW, ALUResultW[1:0], funct3W, ReadDataExtW);
    mux3 resultmux(ALUResultW, ReadDataExtW, PCPlus4W,   // ★ d1 由 ReadDataW 改 ReadDataExtW
                   ResultSrcW, ResultW_pre);

    
    //mux3 resultmux(ALUResultW, ReadDataW, PCPlus4W,
     //              ResultSrcW, ResultW_pre);
    mux2 auipcmux(ResultW_pre, PCTargetW, (ResultSrcW == 2'b11), ResultW);

endmodule
