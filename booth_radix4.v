module booth_radix4 #(
    parameter WIDTH = 32
)(
    input  wire signed [WIDTH-1:0] a,
    input  wire signed [WIDTH-1:0] b,
    output reg  signed [2*WIDTH-1:0] product
);

integer i;

reg signed [2*WIDTH-1:0] acc;
reg signed [2*WIDTH-1:0] pp;
reg [WIDTH:0] multiplier;

always @(*) begin

    acc = 0;
    multiplier = {b,1'b0};   // append LSB zero

    for (i = 0; i < WIDTH/2; i = i + 1) begin

        case (multiplier[2*i +: 3])

            3'b000,
            3'b111: pp = 0;

            3'b001,
            3'b010: pp = {{WIDTH{a[WIDTH-1]}},a};           // +A

            3'b011: pp = {{WIDTH{a[WIDTH-1]}},a} <<< 1;     // +2A

            3'b100: pp = -({{WIDTH{a[WIDTH-1]}},a} <<< 1);  // -2A

            3'b101,
            3'b110: pp = -{{WIDTH{a[WIDTH-1]}},a};          // -A

        endcase

        acc = acc + (pp <<< (2*i));

    end

    product = acc;

end

endmodule
