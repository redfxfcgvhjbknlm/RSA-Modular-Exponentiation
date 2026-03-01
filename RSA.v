`timescale 1ns / 1ps

// =============================================================================
// MODULE 1: Radix-2 Booth Multiplier
// Description: Computes P = A * B sequentially.
// =============================================================================
module booth_multiplier #(
    parameter W = 32
)(
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 start,
    input  wire signed [W-1:0]  A,      // Multiplicand
    input  wire signed [W-1:0]  B,      // Multiplier
    output reg                  done,
    output reg  signed [2*W-1:0] P
);

    localparam [1:0]
        ST_IDLE = 2'd0,
        ST_MULT = 2'd1,
        ST_DONE = 2'd2;

    reg [1:0]       state_q;
    reg [W:0]       count_q;
    reg signed [2*W:0] acc_q; 

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state_q <= ST_IDLE;
            done    <= 1'b0;
            P       <= {(2*W){1'b0}};
            count_q <= {(W+1){1'b0}};
            acc_q   <= {(2*W+1){1'b0}};
        end else begin
            case (state_q)
                ST_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        // Init accumulator: {zeros, B, appended_zero}
                        acc_q   <= { {W{1'b0}}, B, 1'b0 };
                        count_q <= 0;
                        state_q <= ST_MULT;
                    end
                end
                
                ST_MULT: begin
                    if (count_q < W) begin
                        case (acc_q[1:0])
                            2'b01: acc_q[2*W:W+1] <= acc_q[2*W:W+1] + A;
                            2'b10: acc_q[2*W:W+1] <= acc_q[2*W:W+1] - A;
                            default: ; // 00 or 11 do nothing
                        endcase
                        // Arithmetic right shift
                        acc_q   <= $signed(acc_q) >>> 1;
                        count_q <= count_q + 1;
                    end else begin
                        state_q <= ST_DONE;
                    end
                end
                
                ST_DONE: begin
                    P    <= acc_q[2*W:1];
                    done <= 1'b1;
                    if (!start) begin
                        state_q <= ST_IDLE; // Wait for handshake release
                    end
                end
                
                default: state_q <= ST_IDLE;
            endcase
        end
    end
endmodule


// =============================================================================
// MODULE 2: Montgomery REDC Multiplier
// Description: Computes res = (A * B * R^-1) mod M using a shared Booth FSM.
// =============================================================================
module montgomery_redc #(
    parameter W = 32
)(
    input  wire           clk,
    input  wire           rst,
    input  wire           start,
    
    input  wire [W-1:0]   A,
    input  wire [W-1:0]   B,
    input  wire [W-1:0]   M,
    input  wire [W-1:0]   M_prime, // -M^-1 mod R
    
    output reg            done,
    output reg  [W-1:0]   res
);

    localparam [2:0] 
        ST_IDLE     = 3'd0,
        ST_WAIT_AB  = 3'd1,
        ST_WAIT_MP  = 3'd2,
        ST_WAIT_MM  = 3'd3,
        ST_REDUCE   = 3'd4;

    reg [2:0] state_q;

    // Shared multiplier interface
    reg            mult_start;
    reg  [W-1:0]   mult_a;
    reg  [W-1:0]   mult_b;
    wire           mult_done;
    wire [2*W-1:0] mult_p;

    // Internal registers
    reg [2*W-1:0] T_q;
    reg [W-1:0]   m_q;
    reg [2*W:0]   t_sum_q; // Extra bit for overflow

    booth_multiplier #(.W(W)) u_booth_mult (
        .clk(clk), .rst(rst), .start(mult_start),
        .A(mult_a), .B(mult_b), .done(mult_done), .P(mult_p)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state_q    <= ST_IDLE;
            done       <= 1'b0;
            res        <= {W{1'b0}};
            mult_start <= 1'b0;
            mult_a     <= {W{1'b0}};
            mult_b     <= {W{1'b0}};
            T_q        <= {(2*W){1'b0}};
            m_q        <= {W{1'b0}};
            t_sum_q    <= {(2*W+1){1'b0}};
        end else begin
            mult_start <= 1'b0; // Default pulse drop

            case (state_q)
                ST_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        mult_a     <= A; 
                        mult_b     <= B;
                        mult_start <= 1'b1;
                        state_q    <= ST_WAIT_AB;
                    end
                end
                
                ST_WAIT_AB: begin
                    if (mult_done) begin
                        T_q <= mult_p; 
                        
                        mult_a     <= mult_p[W-1:0];
                        mult_b     <= M_prime;
                        mult_start <= 1'b1;
                        state_q    <= ST_WAIT_MP;
                    end
                end

                ST_WAIT_MP: begin
                    if (mult_done) begin
                        m_q <= mult_p[W-1:0]; 
                        
                        mult_a     <= mult_p[W-1:0];
                        mult_b     <= M;
                        mult_start <= 1'b1;
                        state_q    <= ST_WAIT_MM;
                    end
                end

                ST_WAIT_MM: begin
                    if (mult_done) begin
                        t_sum_q <= T_q + mult_p;
                        state_q <= ST_REDUCE;
                    end
                end

                ST_REDUCE: begin
                    if (t_sum_q[2*W:W] >= M) begin
                        res <= t_sum_q[2*W:W] - M;
                    end else begin
                        res <= t_sum_q[2*W:W];
                    end
                    
                    done <= 1'b1;
                    if (!start) state_q <= ST_IDLE;
                end
                
                default: state_q <= ST_IDLE;
            endcase
        end
    end
endmodule


// =============================================================================
// MODULE 3: Montgomery Ladder (Modular Exponentiation)
// Description: Computes (base ^ exp) mod M in constant time.
// Note: Instantiates two REDC multipliers for side-channel attack resistance.
// =============================================================================
module montgomery_ladder #(
    parameter W = 32
)(
    input  wire           clk,
    input  wire           rst,
    input  wire           start,
    
    input  wire [W-1:0]   base,
    input  wire [W-1:0]   exp,
    input  wire [W-1:0]   M,
    input  wire [W-1:0]   M_prime,
    input  wire [W-1:0]   R_mod_M,  // R mod M
    input  wire [W-1:0]   R2_mod_M, // R^2 mod M
    
    output reg            done,
    output reg  [W-1:0]   result
);

    localparam [2:0]
        ST_INIT       = 3'd0,
        ST_LOAD_R1    = 3'd1,
        ST_LOOP       = 3'd2,
        ST_WAIT_REDC  = 3'd3,
        ST_FINAL_REDC = 3'd4,
        ST_DONE       = 3'd5;

    reg [2:0]   state_q;
    reg [W-1:0] R0_q, R1_q;
    reg [W-1:0] exp_q;
    reg [7:0]   bit_idx_q; // Adjust width if W > 256

    // Dual REDC Interfaces
    reg          redc_start;
    reg  [W-1:0] redc_a0, redc_b0, redc_a1, redc_b1;
    wire         redc_done0, redc_done1;
    wire [W-1:0] redc_res0, redc_res1;

    montgomery_redc #(.W(W)) u_redc0 (
        .clk(clk), .rst(rst), .start(redc_start),
        .A(redc_a0), .B(redc_b0), .M(M), .M_prime(M_prime),
        .done(redc_done0), .res(redc_res0)
    );

    montgomery_redc #(.W(W)) u_redc1 (
        .clk(clk), .rst(rst), .start(redc_start),
        .A(redc_a1), .B(redc_b1), .M(M), .M_prime(M_prime),
        .done(redc_done1), .res(redc_res1)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state_q    <= ST_INIT;
            done       <= 1'b0;
            result     <= {W{1'b0}};
            redc_start <= 1'b0;
            R0_q       <= {W{1'b0}};
            R1_q       <= {W{1'b0}};
            exp_q      <= {W{1'b0}};
            bit_idx_q  <= 8'd0;
            redc_a0    <= {W{1'b0}}; redc_b0 <= {W{1'b0}};
            redc_a1    <= {W{1'b0}}; redc_b1 <= {W{1'b0}};
        end else begin
            redc_start <= 1'b0; // Default pulse drop

            case (state_q)
                ST_INIT: begin
                    done <= 1'b0;
                    if (start) begin
                        R0_q      <= R_mod_M;   // Mont. domain 1
                        exp_q     <= exp;
                        bit_idx_q <= W - 1;
                        
                        // Start calculating R1 = base * R mod M
                        redc_a0    <= base;
                        redc_b0    <= R2_mod_M;
                        redc_start <= 1'b1;
                        state_q    <= ST_LOAD_R1;
                    end
                end
                
                ST_LOAD_R1: begin
                    if (redc_done0) begin
                        R1_q    <= redc_res0;
                        state_q <= ST_LOOP;
                    end
                end
                
                ST_LOOP: begin
                    // Side-channel resistant parallel branches
                    if (exp_q[bit_idx_q] == 1'b0) begin
                        redc_a0 <= R0_q; redc_b0 <= R0_q; // R0 = REDC(R0, R0)
                        redc_a1 <= R0_q; redc_b1 <= R1_q; // R1 = REDC(R0, R1)
                    end else begin
                        redc_a0 <= R0_q; redc_b0 <= R1_q; // R0 = REDC(R0, R1)
                        redc_a1 <= R1_q; redc_b1 <= R1_q; // R1 = REDC(R1, R1)
                    end
                    redc_start <= 1'b1;
                    state_q    <= ST_WAIT_REDC;
                end
                
                ST_WAIT_REDC: begin
                    if (redc_done0 && redc_done1) begin
                        R0_q <= redc_res0;
                        R1_q <= redc_res1;
                        
                        if (bit_idx_q == 0) begin
                            // Exit loop, remove from Montgomery domain
                            redc_a0    <= redc_res0;
                            redc_b0    <= { {(W-1){1'b0}}, 1'b1 }; // The value 1
                            redc_start <= 1'b1;
                            state_q    <= ST_FINAL_REDC;
                        end else begin
                            bit_idx_q <= bit_idx_q - 1;
                            state_q   <= ST_LOOP;
                        end
                    end
                end
                
                ST_FINAL_REDC: begin
                    if (redc_done0) begin
                        result  <= redc_res0;
                        state_q <= ST_DONE;
                    end
                end
                
                ST_DONE: begin
                    done <= 1'b1;
                    if (!start) state_q <= ST_INIT;
                end
                
                default: state_q <= ST_INIT;
            endcase
        end
    end
endmodule