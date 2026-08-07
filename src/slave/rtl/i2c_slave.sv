// `timescale 1ns / 1ps

// module i2c_slave #(
//     parameter SLA_ADDR = 7'h01
// ) (
//     input logic clk,
//     input logic reset,

//     // peripheral
//     input  logic [7:0] tx_data,
//     output logic [7:0] rx_data,
//     output logic       done,

//     // Bus
//     input logic scl,
//     inout logic sda
// );

//     logic sda_o, sda_i;

//     assign sda_i = sda;
//     assign sda   = sda_o ? 1'bz : 1'b0;

//     typedef enum logic [2:0] {
//         IDLE = 3'b000,
//         ADDR,
//         ACK_ADDR,
//         DATA_RX,  // Master Write, Slave Read
//         DATA_TX,  // Master Read, Slave Write
//         DATA_ACK
//     } i2c_state_e;

//     i2c_state_e state;
//     logic scl_posedge, scl_negedge;
//     logic sda_posedge, sda_negedge;
//     logic [7:0] tx_shift_reg, rx_shift_reg;
//     logic read_write_r;
//     logic stop_detected;
//     logic start_detected;
//     logic [3:0] bit_cnt;

//     logic [7:0] reg_tx_data;

//     logic sda_o_r;
//     assign sda_o = sda_o_r;

//     // =====================================================================
//     // [②] 글리치 필터 (연속 4샘플 확정 방식)
//     //   - 4샘플(40ns) 연속으로 같은 값일 때만 필터 출력을 갱신
//     //   - open-drain 상승 구간의 임계값 근처 진동/노이즈를 제거
//     //   - 100kHz SCL(비트당 10us)에서 40ns 지연은 타이밍에 영향 없음
//     // =====================================================================
//     logic [3:0] scl_sr, sda_sr;
//     logic       scl_f, sda_f;      // 필터링된 현재 값
//     logic       scl_f_d, sda_f_d;  // 1클럭 지연 (에지 검출용)

//     always_ff @(posedge clk or posedge reset) begin
//         if (reset) begin
//             scl_sr  <= 4'hF;
//             sda_sr  <= 4'hF;
//             scl_f   <= 1'b1;
//             sda_f   <= 1'b1;
//             scl_f_d <= 1'b1;
//             sda_f_d <= 1'b1;
//         end else begin
//             scl_sr <= {scl_sr[2:0], scl};
//             sda_sr <= {sda_sr[2:0], sda_i};

//             if      (scl_sr == 4'hF) scl_f <= 1'b1;  // 40ns 연속 1
//             else if (scl_sr == 4'h0) scl_f <= 1'b0;  // 40ns 연속 0
//             // 그 외(진동 중)에는 이전 값 유지

//             if      (sda_sr == 4'hF) sda_f <= 1'b1;
//             else if (sda_sr == 4'h0) sda_f <= 1'b0;

//             scl_f_d <= scl_f;
//             sda_f_d <= sda_f;
//         end
//     end

//     // 필터링된 신호 기준으로 에지 / START / STOP 판정
//     assign scl_posedge = ({scl_f_d, scl_f} == 2'b01);
//     assign scl_negedge = ({scl_f_d, scl_f} == 2'b10);

//     assign sda_posedge = ({sda_f_d, sda_f} == 2'b01);
//     assign sda_negedge = ({sda_f_d, sda_f} == 2'b10);

//     assign start_detected = scl_f && sda_negedge;  // SCL high 중 SDA 하강
//     assign stop_detected  = scl_f && sda_posedge;  // SCL high 중 SDA 상승

//     // =====================================================================
//     // [③] 버스 워치독 (고착 상태 자동 복구)
//     //   - IDLE이 아닌데 SCL 활동이 일정 시간 없으면 강제로 IDLE 복귀
//     //   - 가짜 START로 어긋난 슬레이브가 다음 폴링 전에 스스로 풀려남
//     // =====================================================================
//     logic [12:0] idle_cnt;
//     logic        bus_timeout;

//     always_ff @(posedge clk or posedge reset) begin
//         if (reset)
//             idle_cnt <= '0;
//         else if (scl_posedge || scl_negedge)
//             idle_cnt <= '0;                  // SCL 활동 중엔 리셋
//         else if (state != IDLE)
//             idle_cnt <= idle_cnt + 1;        // IDLE 밖에서 정적이면 누적
//         else
//             idle_cnt <= '0;
//     end

//     assign bus_timeout = (idle_cnt == 13'h1FFF);  // 100MHz 기준 약 82us

//     // =====================================================================
//     // 메인 FSM
//     // =====================================================================
//     always_ff @(posedge clk or posedge reset) begin
//         if (reset) begin
//             state        <= IDLE;
//             tx_shift_reg <= 0;
//             rx_shift_reg <= 0;
//             bit_cnt      <= 0;
//             done         <= 1'b0;
//             sda_o_r      <= 1'b1;
//             read_write_r <= 1'b0;
//             rx_data      <= 0;
//             reg_tx_data  <= 0;
//         end else begin
//             done <= 1'b0;

//             // [③] STOP 또는 워치독 타임아웃 → 강제 IDLE + SDA 해제
//             if (stop_detected || bus_timeout) begin
//                 state   <= IDLE;
//                 sda_o_r <= 1'b1;
//                 bit_cnt <= 0;
//             end else if (start_detected) begin
//                 state   <= ADDR;
//                 sda_o_r <= 1'b1;
//                 bit_cnt <= 0;
//             end else begin
//                 case (state)
//                     IDLE: begin
//                         sda_o_r <= 1'b1;
//                     end
//                     ADDR: begin
//                         if (scl_posedge) begin
//                             rx_shift_reg <= {rx_shift_reg[6:0], sda_f};
//                             bit_cnt <= bit_cnt + 1;
//                         end
//                         if (scl_negedge) begin
//                             if (bit_cnt == 8) begin
//                                 read_write_r <= rx_shift_reg[0];
//                                 state        <= ACK_ADDR;

//                                 // 8번째 SCL 하강 에지에서 바로 ACK/NACK 결정
//                                 if (rx_shift_reg[7:1] == SLA_ADDR) begin
//                                     sda_o_r     <= 1'b0;  // ACK 전송
//                                     reg_tx_data <= tx_data;
//                                 end else begin
//                                     sda_o_r <= 1'b1;  // NACK (addr unmatching)
//                                 end
//                             end
//                         end
//                     end
//                     ACK_ADDR: begin
//                         if (scl_negedge) begin  // 9번째 클럭이 끝나는 시점
//                             bit_cnt <= 0;
//                             if (rx_shift_reg[7:1] == SLA_ADDR) begin
//                                 if (read_write_r == 1'b0) begin
//                                     state   <= DATA_RX;  // 수신 모드
//                                     sda_o_r <= 1'b1;     // SDA 놓아줌 (받을 준비)
//                                 end else begin
//                                     state        <= DATA_TX;
//                                     sda_o_r      <= reg_tx_data[7];  // MSB 미리 출력
//                                     tx_shift_reg <= {reg_tx_data[6:0], 1'b0};
//                                 end
//                             end else begin
//                                 state <= IDLE;
//                             end
//                         end
//                     end
//                     // slave receive mode (Master Write)
//                     DATA_RX: begin
//                         if (scl_posedge) begin
//                             rx_shift_reg <= {rx_shift_reg[6:0], sda_f};
//                             bit_cnt      <= bit_cnt + 1;
//                         end
//                         if (scl_negedge) begin
//                             if (bit_cnt == 8) begin
//                                 state   <= DATA_ACK;
//                                 sda_o_r <= 1'b0;  // 데이터 다 받았으니 ACK(0) 준비
//                                 rx_data <= rx_shift_reg;
//                                 done    <= 1'b1;
//                             end
//                         end
//                     end
//                     // Slave transceive mode (Master Read)
//                     DATA_TX: begin
//                         if (scl_negedge) begin
//                             if (bit_cnt == 7) begin
//                                 state   <= DATA_ACK;
//                                 sda_o_r <= 1'b1;  // 8bit 다 보냈으니 마스터 ACK 듣기 위해 해제
//                             end else begin
//                                 sda_o_r      <= tx_shift_reg[7];
//                                 tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
//                                 bit_cnt      <= bit_cnt + 1;
//                             end
//                         end
//                     end
//                     DATA_ACK: begin
//                         if (scl_negedge) begin
//                             bit_cnt <= 0;
//                             if (read_write_r == 1'b0) begin
//                                 state   <= DATA_RX;
//                                 sda_o_r <= 1'b1;
//                             end else begin
//                                 if (sda_f == 1'b0) begin  // 마스터 ACK
//                                     state        <= DATA_TX;
//                                     sda_o_r      <= reg_tx_data[7];
//                                     tx_shift_reg <= {reg_tx_data[6:0], 1'b0};
//                                     reg_tx_data  <= tx_data;
//                                 end else begin            // 마스터 NACK
//                                     state   <= IDLE;
//                                     sda_o_r <= 1'b1;
//                                 end
//                             end
//                         end
//                     end
//                     default: begin
//                         state   <= IDLE;
//                         sda_o_r <= 1'b1;
//                     end
//                 endcase
//             end
//         end
//     end
// endmodule

`timescale 1ns / 1ps

module i2c_slave #(
    parameter SLA_ADDR = 7'h10
) (
    input logic clk,
    input logic reset,

    // peripheral
    input logic [7:0] tx_data,
    output logic [7:0] rx_data,
    output logic done,

    // Bus
    input logic scl,
    inout logic sda
);

    logic sda_o, sda_i;

    assign sda_i = sda;
    assign sda   = sda_o ? 1'bz : 1'b0;

    typedef enum logic [2:0] {
        IDLE = 3'b000,
        ADDR,
        ACK_ADDR,
        DATA_RX,  // Master Write, Slave Read
        DATA_TX,  // Master Read, Slave Write
        DATA_ACK
    } i2c_state_e;

    i2c_state_e state;
    logic scl_posedge, scl_negedge;
    logic sda_posedge, sda_negedge;
    logic [7:0] tx_shift_reg, rx_shift_reg;
    logic read_write_r;
    logic stop_detected;
    logic start_detected;
    logic [3:0] bit_cnt;

    logic [2:0] scl_sync;
    logic [2:0] sda_sync;
    logic [7:0] reg_tx_data;

    logic sda_o_r;
    assign sda_o = sda_o_r;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            scl_sync <= 3'b111;
            sda_sync <= 3'b111;
        end else begin
            scl_sync <= {scl_sync[1:0], scl};
            sda_sync <= {sda_sync[1:0], sda_i};
        end
    end

    assign scl_posedge = (scl_sync[2:1] == 2'b01);
    assign scl_negedge = (scl_sync[2:1] == 2'b10);

    assign sda_posedge = (sda_sync[2:1] == 2'b01);
    assign sda_negedge = (sda_sync[2:1] == 2'b10);

    assign start_detected = (scl_sync[1] == 1'b1) && sda_negedge;
    assign stop_detected = (scl_sync[1] == 1'b1) && sda_posedge;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state        <= IDLE;
            tx_shift_reg <= 0;
            rx_shift_reg <= 0;
            bit_cnt      <= 0;
            done         <= 1'b0;
            sda_o_r      <= 1'b1;
            read_write_r <= 1'b0;
            rx_data      <= 0;
            reg_tx_data  <= 0;
        end else begin
            done <= 1'b0;

            if (stop_detected) begin
                state   <= IDLE;
                sda_o_r <= 1'b1;
                bit_cnt <= 0;
            end else if (start_detected) begin
                state   <= ADDR;
                sda_o_r <= 1'b1;
                bit_cnt <= 0;
            end else begin
                case (state)
                    IDLE: begin
                        sda_o_r <= 1'b1;
                    end
                    ADDR: begin
                        if (scl_posedge) begin
                            rx_shift_reg <= {rx_shift_reg[6:0], sda_i};
                            bit_cnt <= bit_cnt + 1;
                        end
                        if (scl_negedge) begin
                            if (bit_cnt == 8) begin
                                read_write_r <= rx_shift_reg[0];
                                state        <= ACK_ADDR;

                                // 8번째 SCL 하강 에지에서 바로 ACK/NACK 결정
                                if (rx_shift_reg[7:1] == SLA_ADDR) begin
                                    sda_o_r <= 1'b0;  // ACK 전송 
                                    reg_tx_data <= tx_data;
                                end else begin
                                    sda_o_r <= 1'b1;  // NACK (addr unmatching)
                                end
                            end
                        end
                    end
                    ACK_ADDR: begin
                        if (scl_negedge) begin // 9번째 클럭이 끝나는 시점 
                            bit_cnt <= 0;
                            if (rx_shift_reg[7:1] == SLA_ADDR) begin
                                if (read_write_r == 1'b0) begin
                                    state <= DATA_RX;  // 수신 모드
                                    sda_o_r <= 1'b1; // SDA 놓아줌 (받을 준비)
                                end else begin
                                    state <= DATA_TX;
                                    sda_o_r <= reg_tx_data[7];  // MSB 미리 출력
                                    tx_shift_reg <= {reg_tx_data[6:0], 1'b0};
                                end
                            end else begin
                                state <= IDLE;
                            end
                        end
                    end
                    // slave receive mdoe (Master Write)
                    DATA_RX: begin
                        if (scl_posedge) begin
                            rx_shift_reg <= {rx_shift_reg[6:0], sda_i};
                            bit_cnt      <= bit_cnt + 1;
                        end
                        if (scl_negedge) begin
                            if (bit_cnt == 8) begin
                                state <= DATA_ACK;
                                sda_o_r <= 1'b0; // 데이터 다 받았으니 내가 ACK(0) 보낼 준비
                                rx_data <= rx_shift_reg;
                                done <= 1'b1;
                            end
                        end
                    end
                    // Slave tranceive mode (Master Read)
                    DATA_TX: begin
                        if (scl_negedge) begin
                            if (bit_cnt == 7) begin
                                state <= DATA_ACK;
                                sda_o_r <= 1'b1; // 8bit 다 보냈으니 마스터의 ACK를 듣기 위해 선을 놓음
                            end else begin
                                sda_o_r      <= tx_shift_reg[7];
                                tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                                bit_cnt      <= bit_cnt + 1;
                            end
                        end
                        // else if (bit_cnt == 0 && scl_sync[1] == 1'b0) begin
                        //     sda_o_r <= tx_data[7];
                        //     tx_shift_reg <= {tx_data[6:0], 1'b0};
                        // end
                    end
                    DATA_ACK: begin
                        if (scl_negedge) begin
                            bit_cnt <= 0;
                            if (read_write_r == 1'b0) begin
                                state   <= DATA_RX;
                                sda_o_r <= 1'b1;
                            end else begin
                                if (sda_i == 1'b0) begin
                                    state <= DATA_TX;
                                    sda_o_r <= reg_tx_data[7];
                                    tx_shift_reg <= {reg_tx_data[6:0], 1'b0};
                                    reg_tx_data <= tx_data;
                                end else begin
                                    state   <= IDLE;
                                    sda_o_r <= 1'b1;
                                end
                            end
                        end
                    end
                endcase
            end
        end
    end
endmodule
