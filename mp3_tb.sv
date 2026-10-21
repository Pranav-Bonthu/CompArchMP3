`timescale 1ns / 1ps

module mp3_tb;

    logic clk = 1'b0;
    logic din;

    always #41.667 clk = ~clk;

    top dut (
        .clk (clk),
        .din (din)
    );

    initial begin
        $dumpfile("mp3_tb.fst");
        $dumpvars(0, mp3_tb);
        // TODO: check successive generations against the Game of Life rules
        #1_000_000;
        $finish;
    end

endmodule
