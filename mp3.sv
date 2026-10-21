// Game of Life on an 8x8 WS2812B matrix (iceBlinkPico)

module top (
    input  logic clk,     // 12 MHz
    output logic din      // WS2812B data line
);

    // TODO: grid state, initialized from seed.mem with $readmemh
    // TODO: next-generation logic (8 neighbors, cyclic wrap)
    // TODO: color variant
    // TODO: WS2812B driver

endmodule
