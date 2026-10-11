// ============================================================
// bpu.v — 分支方向预测器（Branch Prediction Unit）
//   结构：2 位饱和计数器 BHT，PC 半字粒度索引（兼容 RVC）。
//   IF 级组合读：给出方向预测；EX 级分支定向后更新。
//   预测失败的恢复由 datapath 的 MispredictE 逻辑完成，
//   与原有分支重定向共用 FlushD/FlushE 冲刷路径。
//
//   计数初值 2'b01（弱不跳）：循环分支首次迭代预测不跳、
//   退出时预测跳，稳态下每个循环分支仅 2 次预测失败。
//
//   更新门控 upd_en = BranchE & ~StallAll：
//   AXI 等待/除法冻结期间 EX 级分支保持不动，门控保证
//   每条分支恰好更新一次（与 div_ack 同一类陷阱）。
// ============================================================
module bpu #(
    parameter IDX_BITS = 10              // 1024 项 x 2bit，半字索引覆盖 2KB 指令空间
)(
    input  wire        clk,
    input  wire        reset,
    // ---- IF 级查表（组合读，当拍有效）----
    input  wire [31:0] pc_f,
    output wire        pred_taken_f,
    // ---- EX 级更新 ----
    input  wire        upd_en,           // BranchE & ~StallAll
    input  wire [31:0] upd_pc,           // 分支自身 PC（PCE）
    input  wire        upd_taken,        // 实际方向（BranchTakenE）
    input  wire        upd_pred,         // 当时的预测（PredTakenE），统计用
    // ---- 统计计数（TB 分层引用读取）----
    output reg  [31:0] stat_pred,        // 分支解析总数
    output reg  [31:0] stat_miss         // 其中预测失败数
);
    reg [1:0] bht [0:(1<<IDX_BITS)-1];
    integer i;
    initial begin
        for (i = 0; i < (1<<IDX_BITS); i = i + 1)
            bht[i] = 2'b01;              // 弱不跳
    end

    // MSB=1（10/11）预测跳；半字粒度索引：bit0 恒 0 弃用
    assign pred_taken_f = bht[pc_f[IDX_BITS:1]][1];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            stat_pred <= 32'd0;
            stat_miss <= 32'd0;
        end else if (upd_en) begin
            // 2 位饱和计数：跳 +1（封顶 11），不跳 -1（封底 00）
            if (upd_taken)
                bht[upd_pc[IDX_BITS:1]] <= (bht[upd_pc[IDX_BITS:1]] == 2'b11) ?
                                           2'b11 : bht[upd_pc[IDX_BITS:1]] + 2'b01;
            else
                bht[upd_pc[IDX_BITS:1]] <= (bht[upd_pc[IDX_BITS:1]] == 2'b00) ?
                                           2'b00 : bht[upd_pc[IDX_BITS:1]] - 2'b01;
            stat_pred <= stat_pred + 1'b1;
            if (upd_taken ^ upd_pred)
                stat_miss <= stat_miss + 1'b1;
        end
    end
endmodule
