// ============================================================
// axi_lite_master -- CPU 访存接口 <-> AXI4-Lite 主机适配器
//
// CPU 侧是"请求/等待"简单接口：
//   req_read/req_write 拉高表示 MEM 级有访存（由 ResultSrcM/MemWriteM 产生）
//   stall 拉高期间，CPU 冻结整条流水线（MemStall）
// 总线侧是标准 AXI4-Lite 五通道：
//   写：AW + W + B    读：AR + R
//
// 时序（从机 READY 常 1 时）：
//   写：周期0 发 AWVALID+WVALID -> 周期1 被接受 -> 周期2 BVALID，完成（2 拍等待）
//   读：周期0 发 ARVALID        -> 周期1 被接受 -> 周期2 RVALID，完成（2 拍等待）
// 注意：VALID 均为寄存器输出，且不依赖 READY，符合 AXI 协议。
// ============================================================
module axi_lite_master(
    input  wire        clk,
    input  wire        reset,
    // ---------- CPU 侧 ----------
    input  wire        req_read,    // load（MemReadM）
    input  wire        req_write,   // store（MemWriteM）
    input  wire [31:0] addr,        // ALUResultM
    input  wire [31:0] wdata,       // WriteDataAlnM
    input  wire [3:0]  wstrb,       // ByteEn -> WSTRB（天然对应）
    output wire [31:0] rdata,       // -> CPU ReadData
    output wire        stall,       // -> CPU MemStall
    // ---------- AXI4-Lite 写地址通道 ----------
    output reg  [31:0] AWADDR,
    output reg         AWVALID,
    input  wire        AWREADY,
    // ---------- AXI4-Lite 写数据通道 ----------
    output reg  [31:0] WDATA,
    output reg  [3:0]  WSTRB,
    output reg         WVALID,
    input  wire        WREADY,
    // ---------- AXI4-Lite 写响应通道 ----------
    input  wire        BVALID,
    input  wire [1:0]  BRESP,
    output wire        BREADY,
    // ---------- AXI4-Lite 读地址通道 ----------
    output reg  [31:0] ARADDR,
    output reg         ARVALID,
    input  wire        ARREADY,
    // ---------- AXI4-Lite 读数据通道 ----------
    input  wire [31:0] RDATA,
    input  wire [1:0]  RRESP,
    input  wire        RVALID,
    output wire        RREADY
);
    localparam IDLE  = 2'd0,
               WRITE = 2'd1,
               READ  = 2'd2;

    reg [1:0] state;
    reg       aw_done, w_done;      // AW / W 各自握手完成标志（允许不同时被接受）

    // 简单主机：响应通道常 ready（从机不会反压 B/R）
    assign BREADY = 1'b1;
    assign RREADY = 1'b1;
    assign rdata  = RDATA;          // RVALID 当拍数据有效，CPU 同拍解锁并锁存

    // 事务完成的当拍就撤 stall：该时钟沿 M_W 锁存正确数据、流水线恢复
    assign stall = (state == IDLE)  ? (req_read | req_write)            :
                   (state == WRITE) ? ~(aw_done & w_done & BVALID)      :
                   /* READ */        ~RVALID;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state   <= IDLE;
            aw_done <= 1'b0;
            w_done  <= 1'b0;
            AWADDR  <= 32'b0;
            AWVALID <= 1'b0;
            WDATA   <= 32'b0;
            WSTRB   <= 4'b0;
            WVALID  <= 1'b0;
            ARADDR  <= 32'b0;
            ARVALID <= 1'b0;
        end else begin
            case (state)
                // ----------------------------------------
                IDLE: begin
                    aw_done <= 1'b0;
                    w_done  <= 1'b0;
                    if (req_write) begin
                        AWADDR  <= addr;
                        AWVALID <= 1'b1;
                        WDATA   <= wdata;
                        WSTRB   <= wstrb;
                        WVALID  <= 1'b1;
                        state   <= WRITE;
                    end else if (req_read) begin
                        ARADDR  <= addr;
                        ARVALID <= 1'b1;
                        state   <= READ;
                    end
                end
                // ----------------------------------------
                WRITE: begin
                    if (AWREADY) begin      // AW 被接受后撤 VALID
                        AWVALID <= 1'b0;
                        aw_done <= 1'b1;
                    end
                    if (WREADY) begin       // W 被接受后撤 VALID
                        WVALID <= 1'b0;
                        w_done <= 1'b1;
                    end
                    if (aw_done & w_done & BVALID)
                        state <= IDLE;      // 收到写响应，事务结束
                end
                // ----------------------------------------
                READ: begin
                    if (ARREADY)            // AR 被接受后撤 VALID
                        ARVALID <= 1'b0;
                    if (RVALID)
                        state <= IDLE;      // 收到读数据，事务结束
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
