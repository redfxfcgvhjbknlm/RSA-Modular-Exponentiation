module montgomery_ladder #(
    parameter WORD_WIDTH = 32,
    parameter NWORDS     = 64,
    parameter EXP_BITS   = WORD_WIDTH * NWORDS
)(
    input  wire clk,
    input  wire rst,
    input  wire start,

    input  wire [WORD_WIDTH*NWORDS-1:0] base_mont,
    input  wire [WORD_WIDTH*NWORDS-1:0] R_modN,
    input  wire [WORD_WIDTH*NWORDS-1:0] N_flat,
    input  wire [WORD_WIDTH-1:0]        Nprime,
    input  wire [EXP_BITS-1:0]          exponent,

    output reg  [WORD_WIDTH*NWORDS-1:0] result,
    output reg  done
);

    // ------------------------------------------------
    // Internal Registers
    // ------------------------------------------------

    reg [WORD_WIDTH*NWORDS-1:0] R0;
    reg [WORD_WIDTH*NWORDS-1:0] R1;

    reg [WORD_WIDTH*NWORDS-1:0] mult_A;
    reg [WORD_WIDTH*NWORDS-1:0] mult_B;
    reg mult_start;

    wire [WORD_WIDTH*NWORDS-1:0] mult_result;
    wire mult_done;

    reg [$clog2(EXP_BITS):0] bit_index;
    reg bit_value;

    reg busy;
    reg start_d;
    wire start_edge;

    // ------------------------------------------------
    // Rising Edge Detect for start
    // ------------------------------------------------
    always @(posedge clk)
        start_d <= start;

    assign start_edge = start & ~start_d;

    // ------------------------------------------------
    // Montgomery CIOS Multiplier Instance
    // ------------------------------------------------
    montgomery_cios_flat #(
        .WORD_WIDTH(WORD_WIDTH),
        .NWORDS(NWORDS)
    ) mont_mul (
        .clk(clk),
        .rst(rst),
        .start(mult_start),
        .A_flat(mult_A),
        .B_flat(mult_B),
        .N_flat(N_flat),
        .Nprime(Nprime),
        .result_flat(mult_result),
        .done(mult_done)
    );

    // ------------------------------------------------
    // FSM
    // ------------------------------------------------
    localparam IDLE        = 0,
               LOADBIT     = 1,
               MUL1        = 2,
               WAIT1       = 3,
               MUL2        = 4,
               WAIT2       = 5,
               START_CONV  = 6,
               WAIT_CONV   = 7,
               DONE_ST     = 8;

    reg [3:0] state;

    always @(posedge clk or posedge rst)
    begin
        if (rst)
        begin
            state <= IDLE;
            done  <= 0;
            busy  <= 0;
            mult_start <= 0;
        end
        else
        begin
            case (state)

            // ----------------------------------------
            // IDLE
            // ----------------------------------------
            IDLE:
            begin
                done <= 0;

                if (start_edge && !busy)
                begin
                    busy <= 1;
                    R0 <= R_modN;       // represents 1 in Montgomery
                    R1 <= base_mont;    // represents A in Montgomery
                    bit_index <= EXP_BITS - 1;
                    state <= LOADBIT;
                end
            end

            // ----------------------------------------
            // LOAD CURRENT BIT
            // ----------------------------------------
            LOADBIT:
            begin
                bit_value <= exponent[bit_index];
                state <= MUL1;
            end

            // ----------------------------------------
            // FIRST MULTIPLY (R0 * R1)
            // ----------------------------------------
            MUL1:
            begin
                mult_A <= R0;
                mult_B <= R1;
                mult_start <= 1;
                state <= WAIT1;
            end

            WAIT1:
            begin
                mult_start <= 0;

                if (mult_done)
                begin
                    if (bit_value == 0)
                        R1 <= mult_result;
                    else
                        R0 <= mult_result;

                    state <= MUL2;
                end
            end

            // ----------------------------------------
            // SECOND MULTIPLY
            // ----------------------------------------
            MUL2:
            begin
                if (bit_value == 0)
                begin
                    mult_A <= R0;
                    mult_B <= R0;
                end
                else
                begin
                    mult_A <= R1;
                    mult_B <= R1;
                end

                mult_start <= 1;
                state <= WAIT2;
            end

            WAIT2:
            begin
                mult_start <= 0;

                if (mult_done)
                begin
                    if (bit_value == 0)
                        R0 <= mult_result;
                    else
                        R1 <= mult_result;

                    if (bit_index == 0)
                        state <= START_CONV;
                    else
                    begin
                        bit_index <= bit_index - 1;
                        state <= LOADBIT;
                    end
                end
            end

            // ----------------------------------------
            // FINAL CONVERSION: MontMul(R0, 1)
            // ----------------------------------------
            START_CONV:
            begin
                mult_A <= R0;

                // Constant 1 (LSB word = 1, others 0)
                mult_B <= { {(WORD_WIDTH*NWORDS-1){1'b0}}, 1'b1 };

                mult_start <= 1;
                state <= WAIT_CONV;
            end

            WAIT_CONV:
            begin
                mult_start <= 0;

                if (mult_done)
                begin
                    result <= mult_result;  // now normal domain
                    done   <= 1;
                    busy   <= 0;
                    state  <= DONE_ST;
                end
            end

            // ----------------------------------------
            // DONE
            // ----------------------------------------
            DONE_ST:
            begin
                if (!start)
                    state <= IDLE;
            end

            endcase
        end
    end

endmodule
