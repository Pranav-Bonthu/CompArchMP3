// Game 1 is drawn in red, 2 in green, 3 in blue.
// A cell in multiple games will be a combination of the colors.

module top #(
    parameter SEED_FILE = "seed.memh",
    parameter BRIGHTNESS = 8'd32, // value sent for living cell
    parameter SERPENTINE = 0,
    parameter FRAMES_PER_GEN = 50 // 2 generations per second
)(
    input logic clk,
    input logic SW,
    output logic _48b
);

    logic [7:0] seed_rows [0:23];
    initial $readmemh(SEED_FILE, seed_rows);

    logic [63:0] seed_r, seed_g, seed_b;

    always_comb begin
        for (int r = 0; r < 8; r++) begin
            seed_r[r*8 +: 8] = seed_rows[r]; // 8 bits starting from r x 8
            seed_g[r*8 +: 8] = seed_rows[8 + r];
            seed_b[r*8 +: 8] = seed_rows[16 + r];
        end
    end

    //restart button
    logic [1:0] sw_sync = 2'b11;
    logic restart;

    always_ff @(posedge clk)
        sw_sync <= { sw_sync[0], SW };

    assign restart = ~sw_sync[1];

    //load signal
    logic loaded = 1'b0;
    logic load;

    always_ff @(posedge clk)
        loaded <= 1'b1;

    assign load = !loaded || restart;

    //generation timer
    logic frame_done;
    logic step;
    logic [$clog2(FRAMES_PER_GEN) - 1:0] frame_count = 0;

    always_ff @(posedge clk) begin
        if (frame_done) begin
            if (frame_count == FRAMES_PER_GEN - 1)
                frame_count <= 0;
            else
                frame_count <= frame_count + 1;
        end
    end

    assign step = frame_done && (frame_count == FRAMES_PER_GEN - 1);

    //3 games at once
    logic [63:0] board_r, board_g, board_b;

    life u_life_r (.clk(clk), .load(load), .seed(seed_r), .step(step), .board(board_r));
    life u_life_g (.clk(clk), .load(load), .seed(seed_g), .step(step), .board(board_g));
    life u_life_b (.clk(clk), .load(load), .seed(seed_b), .step(step), .board(board_b));

    // determining individual pixel colors
    logic [5:0] pixel;
    logic [2:0] row, col;
    logic [5:0] cell_idx;
    logic [23:0] pixel_grb;

    always_comb begin
        row = pixel[5:3];
        col = pixel[2:0];
        if (SERPENTINE && row[0])
            col = 3'd7 - col;
        cell_idx = { row, 3'd7 - col }; // = row*8 + (7 - col)

        // green first, then red, then blue
        pixel_grb = 24'd0;
        if (board_g[cell_idx])
            pixel_grb[23:16] = BRIGHTNESS;
        if (board_r[cell_idx])
            pixel_grb[15:8] = BRIGHTNESS;
        if (board_b[cell_idx])
            pixel_grb[7:0] = BRIGHTNESS;
    end

    display u_display (
        .clk (clk),
        .pixel_grb (pixel_grb),
        .pixel (pixel),
        .frame_done (frame_done),
        .ws2812b_out(_48b)
    );

endmodule

//one game of life board
module life (
    input logic clk,
    input logic load, // copy seed into board
    input logic [63:0] seed,
    input logic step, // advance one generation
    output logic [63:0] board
);

    logic [63:0] next_board;

    initial board = 64'd0;

    //wrapping
    function automatic logic next_cell(
        input logic [63:0] b,
        input logic [2:0] r,
        input logic [2:0] c
    );
        logic [2:0] nr, nc;
        logic [3:0] n;
        n = 4'd0;
        for (int dr = -1; dr <= 1; dr++) begin
            for (int dc = -1; dc <= 1; dc++) begin
                if (dr != 0 || dc != 0) begin
                    nr = r + 3'(dr);
                    nc = c + 3'(dc);
                    n = n + b[{ nr, nc }];
                end
            end
        end
        next_cell = (n == 4'd3) || (b[{ r, c }] && n == 4'd2);
    endfunction

    // Next-generation logic: purely combinational, 64 copies in parallel
    always_comb begin
        for (int r = 0; r < 8; r++)
            for (int c = 0; c < 8; c++)
                next_board[r*8 + c] = next_cell(board, 3'(r), 3'(c));
    end

    // Board register
    always_ff @(posedge clk) begin
        if (load)
            board <= seed;
        else if (step)
            board <= next_board;
    end

endmodule


module display #(
    parameter FRAME_CYCLES = 120000
)(
    input logic clk,
    input logic [23:0] pixel_grb, //pixel color
    output logic [5:0] pixel, // which pixel is next
    output logic frame_done,
    output logic ws2812b_out
);

    localparam PIXEL_CYCLES = 360; // 24 bits x 15 clocks per bit
    localparam GAP_CYCLES = FRAME_CYCLES - 64 * (PIXEL_CYCLES + 1);

    // States
    localparam [1:0] LOAD = 2'd0; // copy the pixel color into shift_reg
    localparam [1:0] SEND = 2'd1; // shift the 24 bits out
    localparam [1:0] GAP = 2'd2; // latch

    logic [1:0] state = GAP;
    logic [1:0] next_state;
    logic [5:0] pixel_count = 6'd0;
    logic [8:0] send_count = 9'd0;
    logic [$clog2(GAP_CYCLES) - 1:0] gap_count = '0;
    logic [23:0] shift_reg = 24'd0;
    logic send_done, gap_done, shift;

    assign send_done = (send_count == PIXEL_CYCLES - 1);
    assign gap_done = (gap_count == GAP_CYCLES - 1);

    // next state logic
    always_comb begin
        next_state = state;
        case (state)
            LOAD: next_state = SEND;
            SEND:
                if (send_done) begin
                    if (pixel_count == 6'd63)
                        next_state = GAP;
                    else
                        next_state = LOAD;
                end
            GAP: if (gap_done) next_state = LOAD;
            default: next_state = LOAD;
        endcase
    end

    // state register/counters
    always_ff @(posedge clk) begin
        state <= next_state;

        if (state == SEND)
            send_count <= send_count + 1;
        else
            send_count <= 9'd0;

        if (state == GAP)
            gap_count <= gap_count + 1;
        else
            gap_count <= '0;

        if (state == SEND && send_done)
            pixel_count <= pixel_count + 1; //63 to 0
    end

    // Shift register holding the 24 bits of the current pixel, MSB first
    always_ff @(posedge clk) begin
        if (state == LOAD)
            shift_reg <= pixel_grb;
        else if (shift)
            shift_reg <= {shift_reg[22:0], 1'b0 };
    end

    assign pixel = pixel_count;
    assign frame_done = (state == SEND) && send_done && (pixel_count == 6'd63);

    ws2812b u_ws2812b (
        .clk (clk),
        .serial_in (shift_reg[23]),
        .transmit (state == SEND),
        .ws2812b_out(ws2812b_out),
        .shift (shift)
    );

endmodule

module ws2812b(
    input logic clk,
    input logic serial_in,
    input logic transmit,
    output logic ws2812b_out,
    output logic shift
);

    localparam IDLE = 1'b0;
    localparam TRANSMITTING = 1'b1;

    localparam T0_CYCLE_COUNT = 4'd5;
    localparam T1_CYCLE_COUNT = 4'd10;
    localparam MAX_CYCLE_COUNT = 4'd15;

    logic state = IDLE;
    logic [3:0] cycle_count = 4'd0;
    logic bit_being_sent = 1'b0;

    always_ff @(posedge clk) begin
        unique case (state)
            IDLE:
                if (transmit == 1'b1) begin
                    state <= TRANSMITTING;
                    cycle_count <= 4'd0;
                    bit_being_sent <= serial_in;
                end
            TRANSMITTING:
                if (transmit == 1'b0) begin
                    state <= IDLE;
                end
                else if (cycle_count == MAX_CYCLE_COUNT - 1) begin
                    cycle_count <= 4'd0;
                    bit_being_sent <= serial_in;
                end
                else begin
                    cycle_count <= cycle_count + 1;
                end
        endcase
    end

    always_comb begin
        if (state == TRANSMITTING)
            if (bit_being_sent == 1'b0)
                ws2812b_out = (cycle_count < T0_CYCLE_COUNT);
            else
                ws2812b_out = (cycle_count < T1_CYCLE_COUNT);
        else
            ws2812b_out = 1'b0;
    end

    assign shift = (state == TRANSMITTING) && (cycle_count == 4'd0);

endmodule
