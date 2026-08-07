`timescale 1ns / 1ps

module ycocg_encoder (
    input  logic        clk,
    input  logic        reset,
    input  logic        i_valid,
    input  logic [47:0] i_block,  // {P3, P2, P1, P0}
    output logic        o_valid,
    output logic [23:0] o_code    // {Cg, Co, Y3, Y2, Y1, Y0}
);
    // ---- 픽셀 분해 ----
    logic [3:0] r0, g0, b0, r1, g1, b1, r2, g2, b2, r3, g3, b3;
    assign {r0, g0, b0} = i_block[11:0];
    assign {r1, g1, b1} = i_block[23:12];
    assign {r2, g2, b2} = i_block[35:24];
    assign {r3, g3, b3} = i_block[47:36];

    // ---- 픽셀별 변환 ----
    logic [3:0] y0, y1, y2, y3;
    logic signed [6:0] co0, co1, co2, co3;
    logic signed [7:0] cg0, cg1, cg2, cg3;

    ycocg_fwd_px u_f0 (
        .i_r(r0),
        .i_g(g0),
        .i_b(b0),
        .o_y(y0),
        .o_co_hp(co0),
        .o_cg_hp(cg0)
    );
    ycocg_fwd_px u_f1 (
        .i_r(r1),
        .i_g(g1),
        .i_b(b1),
        .o_y(y1),
        .o_co_hp(co1),
        .o_cg_hp(cg1)
    );
    ycocg_fwd_px u_f2 (
        .i_r(r2),
        .i_g(g2),
        .i_b(b2),
        .o_y(y2),
        .o_co_hp(co2),
        .o_cg_hp(cg2)
    );
    ycocg_fwd_px u_f3 (
        .i_r(r3),
        .i_g(g3),
        .i_b(b3),
        .o_y(y3),
        .o_co_hp(co3),
        .o_cg_hp(cg3)
    );

    // ---- 색차 다운샘플 : 4픽셀 합을 낸 뒤 마지막에 한 번만 나눔 ----
    //   Co = sum(R-B)    / 8      sum_co :  -60 ..  +60
    //   Cg = sum(2G-R-B) / 16     sum_cg : -120 .. +120
    //   반올림 때문에 +8이 나올 수 있어 위쪽만 +7로 포화시킨다.
    //   (아래쪽 최소는 -7이라 클램프 불필요)
    logic signed [8:0] sum_co;
    logic signed [9:0] sum_cg;
    logic signed [5:0] co_rnd, cg_rnd;
    logic signed [3:0] co_q, cg_q;

    assign sum_co = 9'(co0) + 9'(co1) + 9'(co2) + 9'(co3);
    assign sum_cg = 10'(cg0) + 10'(cg1) + 10'(cg2) + 10'(cg3);

    assign co_rnd = 6'((sum_co + 9'sd4) >>> 3);  // -7 .. +8
    assign cg_rnd = 6'((sum_cg + 10'sd8) >>> 4);  // -7 .. +8

    assign co_q   = (co_rnd > 6'sd7) ? 4'sd7 : co_rnd[3:0];
    assign cg_q   = (cg_rnd > 6'sd7) ? 4'sd7 : cg_rnd[3:0];

    // ---- 출력 레지스터 ----
    always_ff @(posedge clk) begin
        if (reset) begin
            o_code  <= 24'h0;
            o_valid <= 1'b0;
        end else begin
            o_code <= {
                {~cg_q[3], cg_q[2:0]}, {~co_q[3], co_q[2:0]}, y3, y2, y1, y0
            };
            o_valid <= i_valid;
        end
    end

endmodule

//------------------------------------------------------------
// ycocg_fwd_px : 픽셀 하나 -> Y(4b) + 고정밀 Co/Cg (아직 안 나눈 값)
//   색차를 여기서 나누지 않고 합산 후 한 번만 나눠야
//   하위 비트가 살아남는다 (픽셀마다 나누면 4번 버려짐).
//------------------------------------------------------------
module ycocg_fwd_px (
    input  logic        [3:0] i_r,
    input  logic        [3:0] i_g,
    input  logic        [3:0] i_b,
    output logic        [3:0] o_y,      // 0 .. 15
    output logic signed [6:0] o_co_hp,  //  R - B      : -15 .. +15
    output logic signed [7:0] o_cg_hp   //  2G - R - B : -30 .. +30
);
    logic [5:0] y_sum;  // R + 2G + B : 0 .. 60

    // 반올림. 최대 (60+2)>>2 = 15 -> 4비트를 넘지 않음
    assign y_sum = {2'b0, i_r} + {1'b0, i_g, 1'b0} + {2'b0, i_b};
    assign o_y = (y_sum + 6'd2) >> 2;

    assign o_co_hp = $signed({3'b0, i_r}) - $signed({3'b0, i_b});
    assign o_cg_hp = $signed(
        {3'b0, i_g, 1'b0}
    ) - $signed(
        {4'b0, i_r}
    ) - $signed(
        {4'b0, i_b}
    );

endmodule
