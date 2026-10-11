module flopr(
    input clk,
    input reset,
    input [31:0] d,
    output reg [31:0] q
    );
    always@(posedge clk or posedge reset)
        if(reset) q <= 0;
        else q <= d;
endmodule
