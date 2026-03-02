module montgomery_cios_flat #(
    parameter WORD_WIDTH = 32,
    parameter NWORDS     = 64
)(
    input  wire clk,
    input  wire rst,
    input  wire start,

    input  wire [WORD_WIDTH*NWORDS-1:0] A_flat,
    input  wire [WORD_WIDTH*NWORDS-1:0] B_flat,
    input  wire [WORD_WIDTH*NWORDS-1:0] N_flat,
    input  wire [WORD_WIDTH-1:0]        Nprime,

    output reg  [WORD_WIDTH*NWORDS-1:0] result_flat,
    output reg  done
);

    // ----------------------------------------
    // Internal storage
    // ----------------------------------------

    reg [WORD_WIDTH-1:0] T [0:NWORDS];  // n+1 words
    reg [WORD_WIDTH-1:0] m;

    reg [WORD_WIDTH:0] carry;
    reg [WORD_WIDTH:0] sum;

    reg [$clog2(NWORDS):0] i;
    reg [$clog2(NWORDS):0] j;
    reg [$clog2(NWORDS):0] shift_cnt;
    reg [$clog2(NWORDS):0] cmp_cnt;
    reg [$clog2(NWORDS):0] sub_cnt;

    reg ge_flag;

    localparam IDLE  = 0,
               MUL1  = 1,
               MUL2  = 2,
               SHIFT = 3,
               COMP  = 4,
               SUB   = 5,
               DONE  = 6;

    reg [2:0] state;

    // ----------------------------------------
    // Word extraction
    // ----------------------------------------

    function [WORD_WIDTH-1:0] get_word;
        input [WORD_WIDTH*NWORDS-1:0] bus;
        input integer index;
        begin
            get_word = bus[index*WORD_WIDTH +: WORD_WIDTH];
        end
    endfunction

    // ----------------------------------------
    // FSM
    // ----------------------------------------

    always @(posedge clk or posedge rst)
    begin
        if (rst)
        begin
            state <= IDLE;
            done  <= 0;
        end
        else
        begin
            case (state)

            // --------------------------------
            //IDLE
            // --------------------------------
            IDLE:
            begin
                done <= 0;
                if (start)
                begin
                    i <= 0;
                    j <= 0;
                    carry <= 0;
                    state <= MUL1;
                end
            end

            // --------------------------------
            // T = T + A[i]*B
            // --------------------------------
            MUL1:
            begin
                if (j < NWORDS)
                begin
                    sum = T[j] +
                          (get_word(A_flat,i) * get_word(B_flat,j)) +
                          carry;

                    T[j] <= sum[WORD_WIDTH-1:0];
                    carry <= sum >> WORD_WIDTH;
                    j <= j + 1;
                end
                else
                begin
                    T[NWORDS] <= carry;
                    carry <= 0;
                    j <= 0;
                    m <= T[0] * Nprime;
                    state <= MUL2;
                end
            end

            // --------------------------------
            // T = T + m*N
            // --------------------------------
            MUL2:
            begin
                if (j < NWORDS)
                begin
                    sum = T[j] +
                          (m * get_word(N_flat,j)) +
                          carry;

                    T[j] <= sum[WORD_WIDTH-1:0];
                    carry <= sum >> WORD_WIDTH;
                    j <= j + 1;
                end
                else
                begin
                    T[NWORDS] <= T[NWORDS] + carry;
                    carry <= 0;
                    shift_cnt <= 0;
                    state <= SHIFT;
                end
            end

            // --------------------------------
            // Shift right 1 word (1 per cycle)
            // --------------------------------
            SHIFT:
            begin
                if (shift_cnt < NWORDS)
                begin
                    T[shift_cnt] <= T[shift_cnt+1];
                    shift_cnt <= shift_cnt + 1;
                end
                else
                begin
                    T[NWORDS] <= 0;

                    if (i == NWORDS-1)
                    begin
                        cmp_cnt <= NWORDS-1;
                        ge_flag <= 0;
                        state <= COMP;
                    end
                    else
                    begin
                        i <= i + 1;
                        j <= 0;
                        state <= MUL1;
                    end
                end
            end

            // --------------------------------
            // Sequential compare T >= N
            // --------------------------------
            COMP:
begin
    if (!cmp_done)
    begin
        if (T[cmp_cnt] > get_word(N_flat,cmp_cnt))
        begin
            ge_flag <= 1;
            cmp_done <= 1;
        end
        else if (T[cmp_cnt] < get_word(N_flat,cmp_cnt))
        begin
            ge_flag <= 0;
            cmp_done <= 1;
        end
        else
        begin
            if (cmp_cnt == 0)
            begin
                // numbers equal → T >= N is true
                ge_flag <= 1;
                cmp_done <= 1;
            end
            else
                cmp_cnt <= cmp_cnt - 1;
        end
    end
    else
    begin
        if (ge_flag)
        begin
            sub_cnt <= 0;
            carry <= 0;
            state <= SUB;
        end
        else
            state <= DONE;
    end
end
            // --------------------------------
            // Sequential subtraction
            // --------------------------------
            SUB:
            begin
                if (sub_cnt < NWORDS)
                begin
                    sum = T[sub_cnt] -
                          get_word(N_flat,sub_cnt) -
                          carry;

                    result_flat[sub_cnt*WORD_WIDTH +: WORD_WIDTH]
                        <= sum[WORD_WIDTH-1:0];

                    carry <= sum[WORD_WIDTH];
                    sub_cnt <= sub_cnt + 1;
                end
                else
                    state <= DONE;
            end

            // --------------------------------
            //DONE
            // --------------------------------
            DONE:
            begin
                if (!ge_flag)
                begin
                    result_flat <= {T[NWORDS-1:0]};
                end

                done  <= 1;
                state <= IDLE;
            end

            endcase
        end
    end

endmodule
