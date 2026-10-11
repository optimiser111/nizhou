// ============================================================
// div32 -- 32 位多周期除法器（恢复余数法，32 拍迭代）
// 支持 RV32M：DIV / DIVU / REM / REMU（sig 区分有/无符号）
// 特殊情况按 RISC-V 规范：
//   除数为零：q = 0xFFFFFFFF，r = 被除数（直接给出，不等 32 拍）
//   有符号溢出（-2^31 / -1）：q = -2^31，r = 0（绝对值法天然得到）
// 握手：
//   空闲时 start 有效即启动（锁存操作数与符号）；
//   busy 期间每拍做一次"左移-试减-恢复"迭代，共 32 拍；
//   done 拉高表示 q/r 有效，由 ack（指令离开 EX 级）清除后才接受下一条。
// ============================================================
module div32(
    input  wire        clk,
    input  wire        reset,
    input  wire        start,      // 启动脉冲（除法指令进入 EX 且空闲时）
    input  wire        sig,        // 1=有符号(DIV/REM)  0=无符号(DIVU/REMU)
    input  wire [31:0] a,          // 被除数（EX 级前推后的 SrcA）
    input  wire [31:0] b,          // 除数  （EX 级前推后的 rs2）
    output reg  [31:0] q,          // 商
    output reg  [31:0] r,          // 余数
    output reg         busy,       // 迭代中
    input  wire        ack,        // 结果已被取走（指令离开 EX），清 done
    output reg         done        // 结果有效
);
    reg [31:0] divisor;
    reg [32:0] rem;                 // 部分余数（33 位，最高位用于试减判断）
    reg [31:0] quot;
    reg [5:0]  cnt;
    reg        q_neg, r_neg;        // 结果符号（商异或、余数同被除数）
    reg        div0;                // 除数为零
    reg [31:0] a_save;              // 除零时 REM 要还原被除数

    // 恢复余数法单拍迭代：{rem,quot} 左移一位 -> 试减 -> 够减商 1 否则恢复
    wire [32:0] rem_shift = {rem[31:0], quot[31]};
    wire [32:0] rem_sub   = rem_shift - {1'b0, divisor};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            busy    <= 1'b0;   done <= 1'b0;
            q       <= 32'b0;  r    <= 32'b0;
            quot    <= 32'b0;  rem  <= 33'b0;
            divisor <= 32'b0;  cnt  <= 6'b0;
            q_neg   <= 1'b0;   r_neg <= 1'b0;
            div0    <= 1'b0;   a_save <= 32'b0;
        end else if (start) begin
            busy    <= 1'b1;   done <= 1'b0;
            cnt     <= 6'b0;   rem  <= 33'b0;
            quot    <= (sig & a[31]) ? ~a + 1'b1 : a;   // |a|
            divisor <= (sig & b[31]) ? ~b + 1'b1 : b;   // |b|
            q_neg   <= sig & (a[31] ^ b[31]);
            r_neg   <= sig & a[31];
            div0    <= (b == 32'b0);
            a_save  <= a;
        end else if (busy) begin
            if (div0 | (cnt == 6'd32)) begin
                // 结束：除零走规范值，否则按符号还原商/余数
                busy <= 1'b0;
                done <= 1'b1;
                if (div0) begin
                    q <= 32'hFFFFFFFF;              // 规范：除零商全 1
                    r <= a_save;                    //      除零余数 = 被除数
                end else begin
                    q <= q_neg ? ~quot + 1'b1 : quot;
                    r <= r_neg ? ~rem[31:0] + 1'b1 : rem[31:0];
                end
            end else begin
                cnt  <= cnt + 1'b1;
                quot <= {quot[30:0], ~rem_sub[32]}; // 试商位填入最低位
                rem  <= rem_sub[32] ? rem_shift : rem_sub;
            end
        end else if (ack) begin
            done <= 1'b0;                           // 结果已取走，允许下一条除法
        end
    end
endmodule
