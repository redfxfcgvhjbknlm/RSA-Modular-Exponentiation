`timescale 1ns / 1ps

module tb();

    // Parameters matches the source code
    parameter WORD_WIDTH = 32;
    parameter NWORDS     = 64;
    parameter FULL_WIDTH = WORD_WIDTH * NWORDS;

    // Common Signals
    reg clk;
    reg rst;
    reg start;
    
    // Montgomery CIOS Signals
    reg  [FULL_WIDTH-1:0] A_flat, B_flat, N_flat;
    reg  [WORD_WIDTH-1:0] Nprime;
    wire [FULL_WIDTH-1:0] m_cios_result;
    wire cios_done;

    // Booth Radix-4 Signals (assuming it's a sub-component or standalone)
    // Note: Adjust ports based on booth_radix4.v specific implementation
    reg  [WORD_WIDTH-1:0] booth_a, booth_b;
    wire [2*WORD_WIDTH-1:0] booth_prod;

    // 1. Instantiate Montgomery CIOS
    montgomery_cios_flat #(WORD_WIDTH, NWORDS) uut_cios (
        .clk(clk),
        .rst(rst),
        .start(start),
        .A_flat(A_flat),
        .B_flat(B_flat),
        .N_flat(N_flat),
        .Nprime(Nprime),
        .result_flat(m_cios_result),
        .done(cios_done)
    );

    // 2. Instantiate Montgomery Ladder (Modular Exponentiation)
    // Assuming standard ladder ports: result = base^exp mod n
    wire [FULL_WIDTH-1:0] ladder_result;
    wire ladder_done;
    montgomery_ladder #(WORD_WIDTH, NWORDS) uut_ladder (
        .clk(clk),
        .rst(rst),
        .start(start),
        .base(A_flat), 
        .exp(B_flat),
        .mod(N_flat),
        .result(ladder_result),
        .done(ladder_done)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end

    // Test Procedure
    initial begin
        // Initialize
        rst = 1;
        start = 0;
        A_flat = 0;
        B_flat = 0;
        N_flat = 0;
        Nprime = 0;

        #100;
        rst = 0;
        #20;

        // --- Test Case 1: Montgomery Multiplication ---
        // Simple example values (In a real scenario, use 2048-bit hex)
        A_flat = {{(FULL_WIDTH-4){1'b0}}, 4'hA}; 
        B_flat = {{(FULL_WIDTH-4){1'b0}}, 4'hB};
        N_flat = {{(FULL_WIDTH-8){1'b0}}, 8'hF1}; // Arbitrary prime-ish mod
        Nprime = 32'h00000001; // Should be calculated: -N^-1 mod 2^w

        start = 1;
        #10 start = 0;

        // Wait for CIOS
        wait(cios_done);
        $display("Time: %0t | CIOS Result: %h", $time, m_cios_result);

        // --- Test Case 2: Montgomery Ladder ---
        #100;
        start = 1;
        #10 start = 0;
        
        wait(ladder_done);
        $display("Time: %0t | Ladder Result: %h", $time, ladder_result);

        #1000;
        $finish;
    end

endmodule
