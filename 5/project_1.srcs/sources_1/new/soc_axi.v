// ============================================================
// soc_axi -- SoC 顶层：riscvpipe + AXI4-Lite Master + AXI4-Lite Slave
//
// 结构：
//   riscvpipe ──(MemRead/MemWrite/ALUResult/WriteData/ByteEn)──> axi_lite_master
//   riscvpipe <─(ReadData/MemStall)──────────────────────────── axi_lite_master
//   axi_lite_master <── AXI4-Lite 五通道 ──> axi_lite_slave_mem（RAM + LED）
//
// 指令存储器外置（仿真由 TB 提供，上板由 ROM 包装层提供），
// 只有数据口走总线——这是本次 AXI 化的范围。
// ============================================================
module soc_axi(
    input  wire        clk,
    input  wire        reset,
    // 指令口（外置 imem）
    output wire [31:0] PC,
    input  wire [31:0] Instr,
    input  wire [31:0] InstrN,   // ★ RVC：imem[PC[31:2]+1]
    // 板级外设
    output wire [2:0]  led,
    // 调试观测口（TB / ILA 用）
    output wire        MemWrite,
    output wire [31:0] ALUResult,
    output wire [31:0] WriteData,
    output wire [31:0] ReadData
);
    // ---- CPU <-> Master ----
    wire        MemRead;
    wire        MemStall;
    wire [3:0]  ByteEn;
    // ---- Master <-> Slave（AXI4-Lite）----
    wire [31:0] AWADDR, WDATA, ARADDR, RDATA;
    wire [3:0]  WSTRB;
    wire        AWVALID, AWREADY;
    wire        WVALID,  WREADY;
    wire [1:0]  BRESP;
    wire        BVALID,  BREADY;
    wire        ARVALID, ARREADY;
    wire [1:0]  RRESP;
    wire        RVALID,  RREADY;

    // ---------------- CPU ----------------
    riscvpipe cpu(
        .clk       (clk),
        .reset     (reset),
        .PC        (PC),
        .Instr     (Instr),
        .InstrN    (InstrN),
        .MemWrite  (MemWrite),
        .ALUResult (ALUResult),
        .WriteData (WriteData),
        .ReadData  (ReadData),
        .ByteEn    (ByteEn),
        .MemRead   (MemRead),
        .MemStall  (MemStall)
    );

    // ---------------- AXI4-Lite 主机 ----------------
    axi_lite_master bus_master(
        .clk       (clk),
        .reset     (reset),
        .req_read  (MemRead),
        .req_write (MemWrite),
        .addr      (ALUResult),
        .wdata     (WriteData),
        .wstrb     (ByteEn),
        .rdata     (ReadData),
        .stall     (MemStall),
        .AWADDR    (AWADDR),
        .AWVALID   (AWVALID),
        .AWREADY   (AWREADY),
        .WDATA     (WDATA),
        .WSTRB     (WSTRB),
        .WVALID    (WVALID),
        .WREADY    (WREADY),
        .BVALID    (BVALID),
        .BRESP     (BRESP),
        .BREADY    (BREADY),
        .ARADDR    (ARADDR),
        .ARVALID   (ARVALID),
        .ARREADY   (ARREADY),
        .RDATA     (RDATA),
        .RRESP     (RRESP),
        .RVALID    (RVALID),
        .RREADY    (RREADY)
    );

    // ---------------- AXI4-Lite 从机（RAM + LED）----------------
    axi_lite_slave_mem bus_slave(
        .clk       (clk),
        .reset     (reset),
        .AWADDR    (AWADDR),
        .AWVALID   (AWVALID),
        .AWREADY   (AWREADY),
        .WDATA     (WDATA),
        .WSTRB     (WSTRB),
        .WVALID    (WVALID),
        .WREADY    (WREADY),
        .BRESP     (BRESP),
        .BVALID    (BVALID),
        .BREADY    (BREADY),
        .ARADDR    (ARADDR),
        .ARVALID   (ARVALID),
        .ARREADY   (ARREADY),
        .RDATA     (RDATA),
        .RRESP     (RRESP),
        .RVALID    (RVALID),
        .RREADY    (RREADY),
        .led       (led)
    );
endmodule
