// load_ext -- WB 级：从读出的字中按地址低 2 位抽取字节/半字并扩展
module load_ext(
    input  [31:0] data,     // ReadDataW（整字）
    input  [1:0]  addr,     // ALUResultW[1:0]（字节偏移）
    input  [2:0]  funct3,   // funct3W
    output reg [31:0] out
    );
    reg [7:0]  b;
    reg [15:0] h;
    always @(*) begin
        case (addr)
            2'b00: b = data[7:0];
            2'b01: b = data[15:8];
            2'b10: b = data[23:16];
            2'b11: b = data[31:24];
        endcase
        h = addr[1] ? data[31:16] : data[15:0];

        case (funct3)
            3'b000:  out = {{24{b[7]}},  b};   // lb  符号扩展
            3'b001:  out = {{16{h[15]}}, h};   // lh  符号扩展
            3'b100:  out = {24'b0, b};         // lbu 零扩展
            3'b101:  out = {16'b0, h};         // lhu 零扩展
            default: out = data;               // lw 及其他：直通
        endcase
    end
endmodule
