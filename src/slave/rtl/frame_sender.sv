`timescale 1ns / 1ps

module ycocg_frame_sender (
    input logic clk,
    input logic reset,
    input logic abort,

    // Slave_Decoder 쪽
    input  logic start,  // 1클럭 펄스 : 프레임 전송 시작
    output logic busy,
    output logic done,   // 1클럭 펄스 : 9540바이트 전부 push 완료

    // Cam_frameBuffer 읽기
    output logic [13:0] rAddr,
    input  logic [11:0] rData,

    // tx_fifo push
    output logic       push,
    output logic [7:0] push_data,
    input  logic       full
);

    typedef enum logic [3:0] {
        IDLE,
        A0,    // 주소 = P0
        A1,    // 주소 = P1, P0 잡기
        A2,    // 주소 = P2, P1 잡기
        A3,    // 주소 = P3, P2 잡기
        CAP3,  // rData = P3 -> 인코더 입력
        ENC,   // 인코더 출력 잡기
        B0,    // {Y3,Y2} push
        B1,    // {Y1,Y0} push
        B2,    // {Co,Cg} push
        NEXT   // 다음 블록으로
    } state_e;

    state_e        state;

    logic   [13:0] base;  // 현재 블록의 P0 주소
    logic   [13:0] row_base;  // 현재 블록 줄의 첫 P0 주소
    logic   [ 5:0] bx;  // 0 ~ 52
    logic   [ 5:0] by;  // 0 ~ 59
    logic [11:0] p0, p1, p2;
    logic [23:0] code_q;

    // ---- YCoCg 인코더 ----
    logic        enc_valid;
    logic [47:0] enc_block;
    logic [23:0] enc_code;

    assign enc_valid = (state == CAP3);
    assign enc_block = {rData, p2, p1, p0};  // {P3, P2, P1, P0}

    ycocg_encoder U_YCOCG_ENCODER (
        .clk    (clk),
        .reset  (reset),
        .i_valid(enc_valid),
        .i_block(enc_block),
        .o_valid(),
        .o_code (enc_code)    // {Cg, Co, Y3, Y2, Y1, Y0}
    );

    // ---- 읽기 주소 ----
    always_comb begin
        case (state)
            A0:      rAddr = base;
            A1:      rAddr = base + 1;
            A2:      rAddr = base + 106;
            A3:      rAddr = base + 107;
            default: rAddr = base;
        endcase
    end

    // ---- 바이트 push ----
    always_comb begin
        push      = 1'b0;
        push_data = 8'h00;
        case (state)
            B0: begin
                push_data = code_q[15:8];  // {Y3, Y2}
                push      = !full;
            end
            B1: begin
                push_data = code_q[7:0];  // {Y1, Y0}
                push      = !full;
            end
            B2: begin
                push_data = {code_q[19:16], code_q[23:20]};  // {Co, Cg}
                push      = !full;
            end
            default: ;
        endcase
    end

    assign busy = (state != IDLE);

    // ---- FSM ----
    always_ff @(posedge clk) begin
        if (reset) begin
            state    <= IDLE;
            base     <= 14'd0;
            row_base <= 14'd0;
            bx       <= 6'd0;
            by       <= 6'd0;
            p0       <= 12'd0;
            p1       <= 12'd0;
            p2       <= 12'd0;
            code_q   <= 24'd0;
            done     <= 1'b0;
        end else if (abort) begin
            state <= IDLE;
            done  <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        base     <= 14'd0;
                        row_base <= 14'd0;
                        bx       <= 6'd0;
                        by       <= 6'd0;
                        state    <= A0;
                    end
                end
                A0: state <= A1;
                A1: begin
                    p0 <= rData;
                    state <= A2;
                end
                A2: begin
                    p1 <= rData;
                    state <= A3;
                end
                A3: begin
                    p2 <= rData;
                    state <= CAP3;
                end
                CAP3:
                state <= ENC;            // 인코더가 여기서 계산 결과를 레지스터에 넣음
                ENC: begin
                    code_q <= enc_code;
                    state  <= B0;
                end
                B0: if (!full) state <= B1;
                B1: if (!full) state <= B2;
                B2: if (!full) state <= NEXT;
                NEXT: begin
                    if (bx == 6'd52) begin
                        // 한 줄 끝 -> 다음 블록 줄 (픽셀 두 줄 = 212 아래)
                        bx       <= 6'd0;
                        base     <= row_base + 212;
                        row_base <= row_base + 212;
                        if (by == 6'd59) begin
                            done  <= 1'b1;  // 마지막 블록까지 완료
                            state <= IDLE;
                        end else begin
                            by    <= by + 1;
                            state <= A0;
                        end
                    end else begin
                        bx    <= bx + 1;
                        base  <= base + 2;
                        state <= A0;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
