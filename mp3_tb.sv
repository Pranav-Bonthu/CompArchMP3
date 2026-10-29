`timescale 1ns / 1ps

module mp3_tb;

    logic clk = 0;
    logic load = 0;
    logic [63:0] seed = 0;
    logic step = 0;
    logic [63:0] board;

    life u_life (
        .clk(clk),
        .load(load),
        .seed(seed),
        .step(step),
        .board(board)
    );

    always #41.667 clk = ~clk;

    integer passed = 0;
    integer failed = 0;

    task load_board(input logic [63:0] board_val);
    begin
        @(negedge clk);
        seed = board_val;
        load = 1;
        @(negedge clk);
        load = 0;
    end
    endtask

    task step_once();
    begin
        @(negedge clk);
        step = 1;
        @(negedge clk);
        step = 0;
    end
    endtask

    task print_board(input logic [63:0] b);
        string line;
        integer bit_idx;
    begin
        for (int r = 0; r < 8; r++) begin
            line = "";
            for (int c = 0; c < 8; c++) begin
                // Column c is bit 7 - c of that row's byte
                bit_idx = (r * 8) + (7 - c);
                if (b[bit_idx])
                    line = {line, "# "};
                else
                    line = {line, ". "};
            end
            $display("%s", line);
        end
    end
    endtask

    task check(input string test_name, input logic [63:0] initial_val, input logic [63:0] expected_val);
    begin
        if (board === expected_val) begin
            $display("PASS: %s", test_name);
            $display("Initial Board:");
            print_board(initial_val);
            $display("Resulting Board:");
            print_board(board);
            passed++;
        end else begin
            $display("FAIL: %s", test_name);
            $display("Initial Board:");
            print_board(initial_val);
            $display("Expected:");
            print_board(expected_val);
            $display("Got:");
            print_board(board);
            failed++;
        end
    end
    endtask


    function automatic logic [63:0] set_cell(input logic [63:0] b, input integer r, input integer c);
        return b | (64'd1 << (r * 8 + (7 - c)));
    endfunction

    logic [63:0] s;
    logic [63:0] exp;

    // Tests
    initial begin

        $dumpfile("mp3_tb.fst");
        $dumpvars(0, mp3_tb);

        repeat (2) @(negedge clk);

        // living cell, 1 neighbor -> dies
        s = 0;
        s = set_cell(s, 3, 3); s = set_cell(s, 3, 4);
        exp = 0;
        load_board(s);
        step_once();
        check("living cell, 1 neighbor -> dies", s, exp);

        //living cell, 2 neighbors -> lives
        s = 0;
        s = set_cell(s, 3, 3); s = set_cell(s, 3, 4); s = set_cell(s, 4, 3);
        exp = 0;
        exp = set_cell(exp, 3, 3); exp = set_cell(exp, 3, 4); exp = set_cell(exp, 4, 3); exp = set_cell(exp, 4, 4);
        load_board(s);
        step_once();
        check("living cell, 2 neighbors -> lives", s, exp);

        // living cell, 4 neighbors -> dies
        s = 0;
        s = set_cell(s, 3, 3); s = set_cell(s, 2, 3); s = set_cell(s, 4, 3); s = set_cell(s, 3, 2); s = set_cell(s, 3, 4);
        exp = 0;
        exp = set_cell(exp, 2, 2); exp = set_cell(exp, 2, 3); exp = set_cell(exp, 2, 4);
        exp = set_cell(exp, 3, 2); /* 3,3 is dead */ exp = set_cell(exp, 3, 4);
        exp = set_cell(exp, 4, 2); exp = set_cell(exp, 4, 3); exp = set_cell(exp, 4, 4);
        load_board(s);
        step_once();
        check("living cell, 4 neighbors -> dies", s, exp);

        //dead cell, 3 neighbors -> born
        s = 0;
        s = set_cell(s, 3, 2); s = set_cell(s, 3, 3); s = set_cell(s, 3, 4);
        exp = 0;
        exp = set_cell(exp, 2, 3); exp = set_cell(exp, 3, 3); exp = set_cell(exp, 4, 3);
        load_board(s);
        step_once();
        check("dead cell, 3 neighbors -> born", s, exp);

        // vertical blink wraparound in row 7, 0, 1
        s = 0;
        s = set_cell(s, 7, 3); s = set_cell(s, 0, 3); s = set_cell(s, 1, 3);
        exp = 0;
        exp = set_cell(exp, 0, 2); exp = set_cell(exp, 0, 3); exp = set_cell(exp, 0, 4);
        load_board(s);
        step_once();
        check("vertical blink wraparound in row 7, 0, 1", s, exp);

        // horizontal blink wraparound column 7, 0, 1
        s = 0;
        s = set_cell(s, 3, 7); s = set_cell(s, 3, 0); s = set_cell(s, 3, 1);
        exp = 0;
        exp = set_cell(exp, 2, 0); exp = set_cell(exp, 3, 0); exp = set_cell(exp, 4, 0);
        load_board(s);
        step_once();
        check("horizontal blink wraparound column 7, 0, 1", s, exp);

        // diagonal/corner wraparound test
        s = 0;
        s = set_cell(s, 0, 0); s = set_cell(s, 0, 7); s = set_cell(s, 7, 0); s = set_cell(s, 7, 7);
        exp = s; // The 4 corners wrap around to form a stable 2x2 block
        load_board(s);
        step_once();
        check("diagonal/corner wraparound test", s, exp);

        // load a new board -> board equals the seed
        s = 64'h0F0F_0F0F_0F0F_0F0F;
        load_board(s);
        check("Load a new board -> board equals the seed", exp, s);

        // load and step on the same clock -> load (restarting) should dominate
        @(negedge clk);
        seed = 64'hAAAA_AAAA_AAAA_AAAA;
        load = 1;
        step = 1;
        @(negedge clk);
        load = 0;
        step = 0;
        check("load and step on same clock -> load (restarting) should dominate", s, 64'hAAAA_AAAA_AAAA_AAAA);

        $display("Tests Passed: %0d, Failed: %0d", passed, failed);

        $finish;
    end

endmodule