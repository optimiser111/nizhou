// ============================================================
// axi_lite_slave_mem -- AXI4-Lite 从机：4KB RAM + LED 寄存器映射
//
// 地址映射：
//   0x0000_0000 ~ 0x0000_0FFF : 4KB 数据 RAM（WSTRB 字节写使能，支持 sb/sh/sw）
//   0xFFFF_F000 页            : LED 寄存器（写低 3 位点亮，读回当前值）
//
// READY 全部常 1（最简从机）：写 1 拍接收、B 响应次拍给出；
// 读 1 拍接收、R 数据次拍给出（同步读，利于推断 BRAM）。
// ============================================================
module axi_lite_slave_mem(
    input  wire        clk,
    input  wire        reset,
    // ---------- 写地址通道 ----------
    input  wire [31:0] AWADDR,
    input  wire        AWVALID,
    output wire        AWREADY,
    // ---------- 写数据通道 ----------
    input  wire [31:0] WDATA,
    input  wire [3:0]  WSTRB,
    input  wire        WVALID,
    output wire        WREADY,
    // ---------- 写响应通道 ----------
    output reg  [1:0]  BRESP,
    output reg         BVALID,
    input  wire        BREADY,
    // ---------- 读地址通道 ----------
    input  wire [31:0] ARADDR,
    input  wire        ARVALID,
    output wire        ARREADY,
    // ---------- 读数据通道 ----------
    output reg  [31:0] RDATA,
    output reg  [1:0]  RRESP,
    output reg         RVALID,
    input  wire        RREADY,
    // ---------- 板级外设 ----------
    output reg  [2:0]  led
);
    localparam RESP_OKAY = 2'b00;

    reg [31:0] RAM [0:1023];                    // 4KB

    assign AWREADY = 1'b1;
    assign WREADY  = 1'b1;
    assign ARREADY = 1'b1;

    wire wr_fire   = AWVALID & WVALID;          // 两通道同拍接收
    wire led_sel_w = (AWADDR[31:12] == 20'hFFFFF);
    wire led_sel_r = (ARADDR[31:12] == 20'hFFFFF);

    integer i;
    initial begin                               // FPGA 上电初值，综合可用
        led = 3'b000;
        for (i = 0; i < 1024; i = i + 1)
            RAM[i] = 32'b0;
    end

    // ---------------- 写通道 ----------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            BVALID <= 1'b0;
            BRESP  <= RESP_OKAY;
            led    <= 3'b000;
        end else begin
            if (wr_fire) begin
                if (led_sel_w) begin
                    led <= WDATA[2:0];
                end else begin
                    if (WSTRB[0]) RAM[AWADDR[11:2]][7:0]   <= WDATA[7:0];
                    if (WSTRB[1]) RAM[AWADDR[11:2]][15:8]  <= WDATA[15:8];
                    if (WSTRB[2]) RAM[AWADDR[11:2]][23:16] <= WDATA[23:16];
                    if (WSTRB[3]) RAM[AWADDR[11:2]][31:24] <= WDATA[31:24];
                end
                BVALID <= 1'b1;
                BRESP  <= RESP_OKAY;
            end else if (BVALID & BREADY) begin
                BVALID <= 1'b0;
            end
        end
    end

    // ---------------- 读通道 ----------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            RVALID <= 1'b0;
            RDATA  <= 32'b0;
            RRESP  <= RESP_OKAY;
        end else begin
            if (ARVALID) begin
                RDATA  <= led_sel_r ? {29'b0, led} : RAM[ARADDR[11:2]];
                RRESP  <= RESP_OKAY;
                RVALID <= 1'b1;
            end else if (RVALID & RREADY) begin
                RVALID <= 1'b0;
            end
        end
    end
endmodule
