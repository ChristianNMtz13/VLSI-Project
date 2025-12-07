`timescale 1ns / 1ps

module ALU_8bit_pipeline (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  A,
    input  wire [7:0]  B,
    input  wire        carry_in,
    input  wire [4:0]  alu_ctrl,

    output reg  [7:0]  result,
    output reg         flag_carry,
    output reg         flag_zero,
    output reg         flag_overflow,
    output reg         flag_negative
);

    wire [7:0] comb_result;
    wire c, z, o, n;

    ALU_8bit comb (
        .A(A), .B(B), .carry_in(carry_in),
        .alu_ctrl(alu_ctrl),
        .result(comb_result),
        .flag_carry(c),
        .flag_zero(z),
        .flag_overflow(o),
        .flag_negative(n)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result        <= 0;
            flag_carry    <= 0;
            flag_zero     <= 0;
            flag_overflow <= 0;
            flag_negative <= 0;
        end else begin
            result        <= comb_result;
            flag_carry    <= c;
            flag_zero     <= z;
            flag_overflow <= o;
            flag_negative <= n;
        end
    end
endmodule


module ALU_8bit (
    input  wire [7:0] A,
    input  wire [7:0] B,
    input  wire       carry_in,
    input  wire [4:0] alu_ctrl,    // up to 32 possible operations

    output reg  [7:0] result,
    output reg        flag_carry,
    output reg        flag_zero,
    output reg        flag_overflow,
    output reg        flag_negative
);

    // Wider temp registers for intermediate arithmetic
    reg [15:0] wide_tmp;   // for multiplication / MAC
    reg [8:0]  temp9;      // for add/sub with carry

    always @(*) begin
        // Defaults
        result        = 8'd0;
        flag_carry    = 1'b0;
        flag_zero     = 1'b0;
        flag_overflow = 1'b0;
        flag_negative = 1'b0;
        temp9         = 9'd0;
        wide_tmp      = 16'd0;

        case (alu_ctrl)

            //---------------------------------------
            // ARITHMETIC (opcodes 00000 - 01111)
            //---------------------------------------
            5'b00000: begin // ADD: A + B + carry_in
                temp9   = A + B + carry_in;
                result  = temp9[7:0];
                flag_carry    = temp9[8];
                // signed overflow detection
                flag_overflow = (~A[7] & ~B[7] & result[7]) |
                                ( A[7] &  B[7] & ~result[7]);
            end

            5'b00001: begin // SUB: A - B
                temp9   = {1'b0, A} - {1'b0, B};
                result  = temp9[7:0];
                flag_carry    = ~temp9[8]; // borrow indicator (conventional)
                flag_overflow = ( A[7] & ~B[7] & ~result[7]) |
                                (~A[7] &  B[7] &  result[7]);
            end

            5'b00010: begin // MUL (lower 8 bits)
                wide_tmp = A * B;
                result   = wide_tmp[7:0];
                flag_carry = |wide_tmp[15:8];
            end

            5'b00011: begin // DIV (simple)
                if (B != 0) begin
                    result = A / B;
                    flag_overflow = 1'b0;
                end else begin
                    result = 8'd0;
                    flag_overflow = 1'b1; // indicate divide-by-zero
                end
            end

            5'b00100: begin // INCR
                temp9 = A + 1;
                result = temp9[7:0];
                flag_carry = temp9[8];
            end

            5'b00101: begin // DECR
                temp9 = {1'b0, A} - 1;
                result = temp9[7:0];
                flag_carry = ~temp9[8];
            end

            //---------------------------------------
            // COMPARISONS (01000 - 01011)
            //---------------------------------------
            5'b00110: result = (A >  B) ? 8'd1 : 8'd0; // A > B
            5'b00111: result = (A >= B) ? 8'd1 : 8'd0; // A >= B
            5'b01000: result = (A <  B) ? 8'd1 : 8'd0; // A < B
            5'b01001: result = (A <= B) ? 8'd1 : 8'd0; // A <= B
            5'b01010: result = (A == B) ? 8'd1 : 8'd0; // A == B
            5'b01011: result = (A != B) ? 8'd1 : 8'd0; // A != B

            5'b01100: begin // MAC: (A * B) + carry_in  (stores lower 8 bits)
                wide_tmp = (A * B) + carry_in;
                result   = wide_tmp[7:0];
                flag_carry = |wide_tmp[15:8];
            end

            //---------------------------------------
            // LOGICAL (10000 - 10011)
            //---------------------------------------
            5'b10000: result = A & B;       // AND
            5'b10001: result = A | B;       // OR
            5'b10010: result = ~(A ^ B);    // XNOR (bitwise)
            5'b10011: result = ~A;          // NOT (unary, ignores B)

            //---------------------------------------
            // SHIFT / ROTATE (10100 - 10111)
            // Note: carry captures the bit shifted out
            //---------------------------------------
            5'b10100: begin // SHR logical by 1
                flag_carry = A[0];         // bit shifted out
                result = A >> 1;
            end

            5'b10101: begin // SHL logical by 1
                flag_carry = A[7];         // bit shifted out
                result = A << 1;
            end

            5'b10110: begin // ROR rotate right by 1
                flag_carry = A[0];         // (optional: capture LSB)
                result = {A[0], A[7:1]};
            end

            5'b10111: begin // ROL rotate left by 1
                flag_carry = A[7];         // (optional: capture MSB)
                result = {A[6:0], A[7]};
            end

            //---------------------------------------
            // PASS-THROUGH (default region)
            //---------------------------------------
            default: begin
                result = A;
            end
        endcase

        // Common flags
        flag_zero     = (result == 8'd0);
        flag_negative = result[7];

        // If an operation explicitly set overflow earlier, keep it;
        // otherwise ensure it's 0 (we already defaulted to 0 at start).
    end

endmodule