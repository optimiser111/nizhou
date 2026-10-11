module regfile(
    input clk,
    input we3,
    input [4:0] a1, a2, a3,
    input [31:0] wd3,
    output [31:0] rd1, rd2
    );
    reg [31:0] x[31:0];

    
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            x[i] = 32'b0;
    end

    always @(negedge clk)
        if(we3) x[a3] <= wd3;
        
    assign rd1 = (a1!= 0) ? x[a1] : 0;
    assign rd2 = (a2!= 0) ? x[a2] : 0;
    
    
endmodule
