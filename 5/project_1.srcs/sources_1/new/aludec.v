module aludec(
    input opb5,
    input [2:0] funct3,
    input funct7b5,
    input [1:0] ALUOp,
    output reg [3:0] ALUControl
    );
    wire RtypeSub;
    assign RtypeSub = funct7b5 & opb5;   // 只有 R 型且 funct7[5]=1 才是 sub
    always@(*)
        case(ALUOp)
        2'b00:  ALUControl = 4'b0000;    // lw/sw：地址加法
        2'b01:  ALUControl = 4'b0001;    // beq：减法判零
        2'b11:  ALUControl = 4'b1010;
        default: case(funct3)
            // sra/srl 由 funct7b5 区分，R 型 I 型通用（不用看 opb5）
            3'b000:  ALUControl = RtypeSub ? 4'b0001 : 4'b0000; // sub/add (addi)
            3'b001:  ALUControl = 4'b0111;   // sll / slli
            3'b010:  ALUControl = 4'b0101;   // slt / slti
            3'b011:  ALUControl = 4'b0110;   // sltu / sltiu
            3'b100:  ALUControl = 4'b0100;   // xor / xori
            3'b101:  ALUControl = funct7b5 ? 4'b1001 : 4'b1000; // sra/srl (srai/srli)
            3'b110:  ALUControl = 4'b0011;   // or / ori
            3'b111:  ALUControl = 4'b0010;   // and / andi
            default: ALUControl = 4'b0000;
        endcase
        endcase
endmodule
