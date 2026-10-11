`timescale 1ns/1ps
// controller 测试台
// 验证 maindec + aludec 级联后的控制信号，以及 PCSrc 逻辑
module controller_tb;

    reg  [6:0] op;
    reg  [2:0] funct3;
    reg        funct7b5;
    reg        Zero;

    wire [1:0] ResultSrc;
    wire       MemWrite;
    wire       PCSrc, ALUSrc;
    wire       RegWrite, Jump;
    wire [1:0] ImmSrc;
    wire [2:0] ALUControl;

    controller uut (
        .op         (op),
        .funct3     (funct3),
        .funct7b5   (funct7b5),
        .Zero       (Zero),
        .ResultSrc  (ResultSrc),
        .MemWrite   (MemWrite),
        .PCSrc      (PCSrc),
        .ALUSrc     (ALUSrc),
        .RegWrite   (RegWrite),
        .Jump       (Jump),
        .ImmSrc     (ImmSrc),
        .ALUControl (ALUControl)
    );

    integer errs = 0;

    task check(
        input [6:0] o, input [2:0] f3, input f7b5, input z,
        input [1:0] exp_rsrc, input exp_mw, input exp_psrc,
        input exp_asrc, input exp_rw, input exp_jump,
        input [1:0] exp_imm, input [2:0] exp_aluctl,
        input [255:0] name
    );
        begin
            op = o; funct3 = f3; funct7b5 = f7b5; Zero = z;
            #10;
            if (ResultSrc !== exp_rsrc || MemWrite !== exp_mw ||
                PCSrc !== exp_psrc || ALUSrc !== exp_asrc ||
                RegWrite !== exp_rw || Jump !== exp_jump ||
                ImmSrc !== exp_imm || ALUControl !== exp_aluctl) begin
                $display("FAIL [%0s] op=%b f3=%b f7b5=%b Zero=%b",
                         name, o, f3, f7b5, z);
                $display("       got  : rsrc=%b mw=%b pcsrc=%b asrc=%b rw=%b jump=%b imm=%b aluctl=%b",
                         ResultSrc, MemWrite, PCSrc, ALUSrc, RegWrite, Jump, ImmSrc, ALUControl);
                errs = errs + 1;
            end else begin
                $display("PASS [%0s]", name);
            end
        end
    endtask

    initial begin
        $dumpfile("controller_tb.vcd");
        $dumpvars(0, controller_tb);

        //            op          f3  f7b5 Zero  rsrc mw  pcsrc asrc rw  jump imm aluctl
        // lw  x1, 0(x2)
        check(7'b0000011, 3'b010, 1'b0, 1'b0, 2'b01, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 2'b00, 3'b000, "lw");

        // sw  x1, 0(x2)
        check(7'b0100011, 3'b010, 1'b0, 1'b0, 2'b00, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 2'b01, 3'b000, "sw");

        // add x1, x2, x3   (funct7=0000000)
        check(7'b0110011, 3'b000, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 3'b000, "add");

        // sub x1, x2, x3   (funct7=0100000, 第5位=1)
        check(7'b0110011, 3'b000, 1'b1, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 3'b001, "sub");

        // slt x1, x2, x3
        check(7'b0110011, 3'b010, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 3'b101, "slt");

        // or  x1, x2, x3
        check(7'b0110011, 3'b110, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 3'b011, "or");

        // and x1, x2, x3
        check(7'b0110011, 3'b111, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 3'b010, "and");

        // addi x1, x2, 100
        check(7'b0010011, 3'b000, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 2'b00, 3'b000, "addi");

        // beq x1, x2, offset  (Zero=1 时跳转)
        check(7'b1100011, 3'b000, 1'b0, 1'b1, 2'b00, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 2'b10, 3'b001, "beq taken");
        // beq Zero=0 不跳
        check(7'b1100011, 3'b000, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b10, 3'b001, "beq not-taken");

        // jal x1, offset  (无条件跳转)
        check(7'b1101111, 3'b000, 1'b0, 1'b0, 2'b10, 1'b0, 1'b1, 1'b0, 1'b1, 1'b1, 2'b11, 3'b000, "jal");

        if (errs == 0)
            $display("\nALL TESTS PASSED");
        else
            $display("\n%d TEST(S) FAILED", errs);

        $finish;
    end

endmodule
