`timescale 1ns / 1ps

// ==========================================
// 1. 최상위 래퍼 모듈 (SPI_sender)
// ==========================================
module SPI_sender (
    input  logic         clk,
    input  logic         reset,
    // Decoder 제어 포트
    input  logic         decoder_start,
    output logic         fsm_done,
    output logic [  4:0] SPI_error,
    // 외부 SPI 물리 핀
    output logic         sclk,
    output logic         mosi,
    input  logic [  4:0] miso,
    output logic [  4:0] cs_n,
    // BRAM (MMU) 쓰기 포트
    output logic [  4:0] we,
    output logic [ 11:0] waddr,
    output logic [119:0] wdata,
    //디버깅
    output logic [  7:0] slv0_rx_data
);
    // 내부 연결 와이어
    logic [ 7:0] spi_tx_data;
    logic        spi_start;
    logic        spi_done;
    logic        spi_busy;
    logic [39:0] spi_rx_data;  // 5개 x 8비트 = 40비트 통합 수신
    logic        master_cs_n;  // 마스터에서 나오는 기본 cs_n
    logic [ 4:0] ss_n;  // FSM에서 제어하는 전체 ss_n

    //debug
    assign slv0_rx_data = spi_rx_data[7:0];

    // 실제 외부 칩셀렉트(CS)는 FSM과 Master의 조건이 모두 만족(Low)될 때 떨어짐
    assign cs_n[0] = master_cs_n | ss_n[0];
    assign cs_n[1] = master_cs_n | ss_n[1];
    assign cs_n[2] = master_cs_n | ss_n[2];
    assign cs_n[3] = master_cs_n | ss_n[3];
    assign cs_n[4] = master_cs_n | ss_n[4];

    // ==========================================
    // 헤더 및 상태 체크 기능 탑재 FSM
    // ==========================================
    SPI_FSM U_SPI_FSM (
        .clk          (clk),
        .reset        (reset),
        .decoder_start(decoder_start),
        .fsm_done     (fsm_done),
        .spi_error    (SPI_error),
        .tx_data      (spi_tx_data),
        .start        (spi_start),
        .rx_data      (spi_rx_data),
        .done         (spi_done),
        .busy         (spi_busy),
        .ss_n         (ss_n),
        .we           (we),
        .waddr        (waddr),
        .wdata        (wdata)
    );

    // ==========================================
    // 5채널 동시 수신용 1-Master
    // ==========================================
    spi_master_5ch U_spi_master (
        .clk    (clk),
        .reset  (reset),
        .cpol   (1'b0),
        .cpha   (1'b0),
        .clk_div(8'h4),
        .tx_data(spi_tx_data),
        .start  (spi_start),
        .rx_data(spi_rx_data),
        .done   (spi_done),
        .busy   (spi_busy),
        .sclk   (sclk),
        .mosi   (mosi),
        .miso   (miso),
        .cs_n   (master_cs_n)
    );
endmodule


// ==========================================
// 2. 헤더(0xA9) 전송 및 상태(0x18) 확인 기능 탑재 FSM
// ==========================================
module SPI_FSM (
    input logic clk,
    input logic reset,
    input logic decoder_start,
    output logic fsm_done,
    output logic [4:0] spi_error,  // 각 슬레이브별 에러 플래그 (1: 에러/미준비)
    output logic [7:0] tx_data,
    output logic start,
    input logic [39:0] rx_data,
    input logic done,
    input logic busy,
    output logic [4:0] ss_n,
    output logic [4:0] we,
    output logic [11:0] waddr,
    output logic [119:0] wdata
);


    localparam logic [7:0] GAP_CYCLES = 8'd12;

    // FSM 상태 정의 (헤더 전송 및 상태 확인 상태 복구)
    typedef enum logic [3:0] {
        FRAME_START,
        SEND_HEADER,       // 헤더(0xA9) 전송 명령
        WAIT_HEADER_DONE,  // 헤더 완료 대기
        GAP,
        READ_STATUS,       // 상태값 수신 명령
        WAIT_STATUS,       // 상태값 수신 대기 (0x18 확인)
        READ_B1,
        WAIT_B1,           // 데이터 바이트 1 수집
        READ_B2,
        WAIT_B2,           // 데이터 바이트 2 수집
        READ_B3,
        WAIT_B3,           // 데이터 바이트 3 수집
        WRITE_MEM,         // 메모리 쓰기 펄스 발생
        CHECK_LOOP,        // 루프 조건 판별
        FRAME_DONE         // 한 프레임 수신 완료
    } state_e;

    state_e state;
    state_e gap_next;  // [추가] GAP 이후 복귀할 상태
    logic [7:0] gap_cnt;  // [추가] GAP 카운터 (폭 넉넉하게 8비트 고정)

    logic [11:0] loop_cnt;
    logic [23:0] data_buf0, data_buf1, data_buf2, data_buf3, data_buf4;

    assign waddr    = loop_cnt;
    assign fsm_done = (state == FRAME_DONE);

    // 각 슬레이브가 정상적으로 0x18을 보냈는지 확인하는 조합 논리 회로
    logic [4:0] status_ready;
    always_comb begin
        status_ready[0] = (rx_data[7:0] == 8'h18);
        status_ready[1] = (rx_data[15:8] == 8'h18);
        status_ready[2] = (rx_data[23:16] == 8'h18);
        status_ready[3] = (rx_data[31:24] == 8'h18);
        status_ready[4] = (rx_data[39:32] == 8'h18);

        we = 5'b00000;
        wdata = {data_buf4, data_buf3, data_buf2, data_buf1, data_buf0};

        // 메모리에 쓸 때는 준비 완료(spi_error가 0)된 채널만 활성화하여 씀
        if (state == WRITE_MEM) begin
            we = ~spi_error;
        end
    end

    // 고속 상태 제어 블록
    always_ff @(posedge clk) begin
        if (reset) begin
            state     <= FRAME_START;
            gap_next  <= FRAME_START;
            gap_cnt   <= '0;
            tx_data   <= 8'h00;
            start     <= 1'b0;
            ss_n      <= 5'b11111;
            loop_cnt  <= 0;
            spi_error <= 5'b00000;
            data_buf0 <= 24'd0;
            data_buf1 <= 24'd0;
            data_buf2 <= 24'd0;
            data_buf3 <= 24'd0;
            data_buf4 <= 24'd0;
        end else begin
            case (state)
                // 1. 트리거 대기
                FRAME_START: begin
                    start     <= 1'b0;
                    spi_error <= 5'b00000;
                    if (decoder_start) begin
                        loop_cnt <= 0;
                        state    <= SEND_HEADER;
                    end
                end
                // 2. 헤더(0xA9) 전송 트리거
                SEND_HEADER: begin
                    if (!busy) begin
                        ss_n <= 5'b00000;  // 슬레이브 5개 전체 선택
                        tx_data <= 8'hA9;  // 헤더 값 탑재
                        start <= 1'b1;
                        state <= WAIT_HEADER_DONE;
                    end
                end
                WAIT_HEADER_DONE: begin
                    start <= 1'b0;
                    if (done) begin
                        gap_cnt  <= '0;
                        gap_next <= READ_STATUS;
                        state    <= GAP;
                    end
                end


                GAP: begin
                    start <= 1'b0;
                    if (gap_cnt == GAP_CYCLES) begin
                        state <= gap_next;
                    end else begin
                        gap_cnt <= gap_cnt + 1'b1;
                    end
                end

                // 3. 1바이트 상태값 읽기 트리거
                READ_STATUS: begin
                    if (!busy) begin
                        tx_data <= 8'h00;  // 더미 데이터 송신
                        start   <= 1'b1;
                        state   <= WAIT_STATUS;
                    end
                end
                // 🌟 핵심: 수신된 상태가 0x18인지 판단하는 지점
                WAIT_STATUS: begin
                    start <= 1'b0;
                    if (done) begin
                        // 0x18을 보내지 못한 슬레이브는 에러(1) 처리
                        spi_error <= ~status_ready;

                        // 최소 하나의 슬레이브라도 준비가 되었다면 수신 진행
                        if (status_ready != 5'b00000) begin
                            gap_cnt  <= '0;
                            gap_next <= READ_B1;
                            state    <= GAP;
                        end else begin
                            // 아무도 준비되지 않았다면 통신 중단(Abort) 후 프레임 강제 종료
                            ss_n  <= 5'b11111;
                            state <= FRAME_DONE;
                        end
                    end
                end

                // 4. 데이터 바이트 1 수집
                READ_B1: begin
                    if (!busy) begin
                        tx_data <= 8'h00;
                        start   <= 1'b1;
                        state   <= WAIT_B1;
                    end
                end
                WAIT_B1: begin
                    start <= 1'b0;
                    if (done) begin
                        data_buf0[23:16] <= rx_data[7:0];
                        data_buf1[23:16] <= rx_data[15:8];
                        data_buf2[23:16] <= rx_data[23:16];
                        data_buf3[23:16] <= rx_data[31:24];
                        data_buf4[23:16] <= rx_data[39:32];
                        gap_cnt          <= '0;
                        gap_next         <= READ_B2;
                        state            <= GAP;
                    end
                end

                // 5. 데이터 바이트 2 수집
                READ_B2: begin
                    if (!busy) begin
                        tx_data <= 8'h00;
                        start   <= 1'b1;
                        state   <= WAIT_B2;
                    end
                end
                WAIT_B2: begin
                    start <= 1'b0;
                    if (done) begin
                        data_buf0[15:8] <= rx_data[7:0];
                        data_buf1[15:8] <= rx_data[15:8];
                        data_buf2[15:8] <= rx_data[23:16];
                        data_buf3[15:8] <= rx_data[31:24];
                        data_buf4[15:8] <= rx_data[39:32];
                        gap_cnt         <= '0;
                        gap_next        <= READ_B3;
                        state           <= GAP;
                    end
                end

                // 6. 데이터 바이트 3 수집
                READ_B3: begin
                    if (!busy) begin
                        tx_data <= 8'h00;
                        start   <= 1'b1;
                        state   <= WAIT_B3;
                    end
                end
                WAIT_B3: begin
                    start <= 1'b0;
                    if (done) begin
                        data_buf0[7:0] <= rx_data[7:0];
                        data_buf1[7:0] <= rx_data[15:8];
                        data_buf2[7:0] <= rx_data[23:16];
                        data_buf3[7:0] <= rx_data[31:24];
                        data_buf4[7:0] <= rx_data[39:32];
                        state          <= WRITE_MEM;
                    end
                end

                // 7. 메모리 쓰기 수행
                WRITE_MEM: begin
                    state <= CHECK_LOOP;
                end

                // 8. 루프 카운트 검사 (106x120/4 = 3180 픽셀 블록)
                CHECK_LOOP: begin
                    if (loop_cnt == 12'd3179) begin
                        ss_n  <= 5'b11111;  // 전체 전송 완료 시 CS 해제
                        state <= FRAME_DONE;
                    end else begin
                        loop_cnt <= loop_cnt + 1;
                        gap_cnt  <= '0;
                        gap_next <= READ_B1;
                        state    <= GAP;
                    end
                end

                // 9. 한 프레임 완료
                FRAME_DONE: begin
                    state <= FRAME_START;
                end

                default: state <= FRAME_START;
            endcase
        end
    end
endmodule

// ==========================================
// 3. 5채널 동시 수신용 spi_master
//    [수정 #3] miso 샘플 시점을 rising 생성(step==0)에서
//              falling 생성(step==1)으로 이동하여 왕복 지연 마진 확보
// ==========================================
module spi_master_5ch (
    input  logic        clk,
    input  logic        reset,
    input  logic        cpol,
    input  logic        cpha,
    input  logic [ 7:0] clk_div,
    input  logic [ 7:0] tx_data,
    input  logic        start,
    output logic [39:0] rx_data,
    output logic        done,
    output logic        busy,
    output logic        sclk,
    output logic        mosi,
    input  logic [ 4:0] miso,
    output logic        cs_n
);
    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11
    } spi_state_e;

    spi_state_e state;
    logic [7:0] div_cnt;
    logic half_tick;
    logic [7:0] tx_shift_reg;
    logic [7:0] rx_sr0, rx_sr1, rx_sr2, rx_sr3, rx_sr4;
    logic [2:0] bit_cnt;
    logic step, sclk_r;

    assign sclk = sclk_r;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            div_cnt   <= 0;
            half_tick <= 1'b0;
        end else begin
            if (state == DATA) begin
                if (div_cnt == clk_div) begin
                    div_cnt   <= 0;
                    half_tick <= 1'b1;
                end else begin
                    div_cnt   <= div_cnt + 1;
                    half_tick <= 1'b0;
                end
            end else begin
                div_cnt   <= 0;
                half_tick <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            mosi <= 1'b1;
            cs_n <= 1'b1;
            busy <= 1'b0;
            done <= 1'b0;
            tx_shift_reg <= 0;
            rx_sr0 <= 0;
            rx_sr1 <= 0;
            rx_sr2 <= 0;
            rx_sr3 <= 0;
            rx_sr4 <= 0;
            bit_cnt <= 0;
            step <= 1'b0;
            rx_data <= 0;
            sclk_r <= cpol;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    mosi   <= 1'b1;
                    cs_n   <= 1'b1;
                    sclk_r <= cpol;
                    if (start) begin
                        tx_shift_reg <= tx_data;
                        bit_cnt <= 0;
                        step <= 1'b0;
                        busy <= 1'b1;
                        cs_n <= 1'b0;
                        state <= START;
                    end
                end
                START: begin
                    if (!cpha) begin
                        mosi <= tx_shift_reg[7];
                        tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                    end
                    state <= DATA;
                end

                DATA: begin
                    if (half_tick) begin
                        sclk_r <= ~sclk_r;
                        if (step == 0) begin
                            step <= 1'b1;
                            if (cpha) begin
                                mosi <= tx_shift_reg[7];
                                tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                            end
                        end else begin
                            step <= 1'b0;
                            if (!cpha) begin
                                rx_sr0 <= {rx_sr0[6:0], miso[0]};
                                rx_sr1 <= {rx_sr1[6:0], miso[1]};
                                rx_sr2 <= {rx_sr2[6:0], miso[2]};
                                rx_sr3 <= {rx_sr3[6:0], miso[3]};
                                rx_sr4 <= {rx_sr4[6:0], miso[4]};
                                if (bit_cnt < 7) begin
                                    mosi <= tx_shift_reg[7];
                                    tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                                end
                            end else begin
                                rx_sr0 <= {rx_sr0[6:0], miso[0]};
                                rx_sr1 <= {rx_sr1[6:0], miso[1]};
                                rx_sr2 <= {rx_sr2[6:0], miso[2]};
                                rx_sr3 <= {rx_sr3[6:0], miso[3]};
                                rx_sr4 <= {rx_sr4[6:0], miso[4]};
                            end

                            if (bit_cnt == 7) begin
                                state <= STOP;
                                rx_data <= {
                                    rx_sr4[6:0],
                                    miso[4],
                                    rx_sr3[6:0],
                                    miso[3],
                                    rx_sr2[6:0],
                                    miso[2],
                                    rx_sr1[6:0],
                                    miso[1],
                                    rx_sr0[6:0],
                                    miso[0]
                                };
                            end else begin
                                bit_cnt <= bit_cnt + 1;
                            end
                        end
                    end
                end
                STOP: begin
                    sclk_r <= cpol;
                    cs_n   <= 1'b1;
                    done   <= 1'b1;
                    busy   <= 1'b0;
                    mosi   <= 1'b1;
                    state  <= IDLE;
                end
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule

// `timescale 1ns / 1ps

// // ==========================================
// // 1. 최상위 래퍼 모듈 (SPI_sender)
// // ==========================================
// module SPI_sender (
//     input  logic         clk,
//     input  logic         reset,
//     // Decoder 제어 포트
//     input  logic         decoder_start,
//     output logic         fsm_done,
//     output logic [  4:0] SPI_error,
//     // 외부 SPI 물리 핀
//     output logic         sclk,
//     output logic         mosi,
//     input  logic [  4:0] miso,
//     output logic [  4:0] cs_n,
//     // BRAM (MMU) 쓰기 포트
//     output logic [  4:0] we,
//     output logic [ 11:0] waddr,
//     output logic [119:0] wdata,
//     //디버깅
//     output logic [  7:0] slv0_rx_data
// );
//     // 내부 연결 와이어
//     logic [ 7:0] spi_tx_data;
//     logic        spi_start;
//     logic        spi_done;
//     logic        spi_busy;
//     logic [39:0] spi_rx_data;  // 5개 x 8비트 = 40비트 통합 수신
//     logic        master_cs_n;  // 마스터에서 나오는 기본 cs_n
//     logic [ 4:0] ss_n;  // FSM에서 제어하는 전체 ss_n

//     //debug
//     assign slv0_rx_data = spi_rx_data[7:0];

//     // 실제 외부 칩셀렉트(CS)는 FSM과 Master의 조건이 모두 만족(Low)될 때 떨어짐
//     assign cs_n[0] = master_cs_n | ss_n[0];
//     assign cs_n[1] = master_cs_n | ss_n[1];
//     assign cs_n[2] = master_cs_n | ss_n[2];
//     assign cs_n[3] = master_cs_n | ss_n[3];
//     assign cs_n[4] = master_cs_n | ss_n[4];

//     // ==========================================
//     // 헤더 및 상태 체크 기능 탑재 FSM
//     // ==========================================
//     SPI_FSM U_SPI_FSM (
//         .clk          (clk),
//         .reset        (reset),
//         .decoder_start(decoder_start),
//         .fsm_done     (fsm_done),
//         .spi_error    (SPI_error),
//         .tx_data      (spi_tx_data),
//         .start        (spi_start),
//         .rx_data      (spi_rx_data),
//         .done         (spi_done),
//         .busy         (spi_busy),
//         .ss_n         (ss_n),
//         .we           (we),
//         .waddr        (waddr),
//         .wdata        (wdata)
//     );

//     // ==========================================
//     // 5채널 동시 수신용 1-Master
//     // ==========================================
//     spi_master_5ch U_spi_master (
//         .clk    (clk),
//         .reset  (reset),
//         .cpol   (1'b0),
//         .cpha   (1'b0),
//         .clk_div(8'h4),
//         .tx_data(spi_tx_data),
//         .start  (spi_start),
//         .rx_data(spi_rx_data),
//         .done   (spi_done),
//         .busy   (spi_busy),
//         .sclk   (sclk),
//         .mosi   (mosi),
//         .miso   (miso),
//         .cs_n   (master_cs_n)
//     );
// endmodule


// // ==========================================
// // 2. 헤더(0xA9) 전송 및 상태(0x18) 확인 기능 탑재 FSM
// // ==========================================
// module SPI_FSM (
//     input logic clk,
//     input logic reset,
//     input logic decoder_start,
//     output logic fsm_done,
//     output logic [4:0] spi_error,  // 각 슬레이브별 에러 플래그 (1: 에러/미준비)
//     output logic [7:0] tx_data,
//     output logic start,
//     input logic [39:0] rx_data,
//     input logic done,
//     input logic busy,
//     output logic [4:0] ss_n,
//     output logic [4:0] we,
//     output logic [11:0] waddr,
//     output logic [119:0] wdata
// );

//     // FSM 상태 정의 (헤더 전송 및 상태 확인 상태 복구)
//     typedef enum logic [3:0] {
//         FRAME_START,
//         SEND_HEADER,       // 헤더(0xA9) 전송 명령
//         WAIT_HEADER_DONE,  // 헤더 완료 대기
//         READ_STATUS,       // 상태값 수신 명령
//         WAIT_STATUS,       // 상태값 수신 대기 (0x18 확인)
//         READ_B1,
//         WAIT_B1,           // 데이터 바이트 1 수집
//         READ_B2,
//         WAIT_B2,           // 데이터 바이트 2 수집
//         READ_B3,
//         WAIT_B3,           // 데이터 바이트 3 수집
//         WRITE_MEM,         // 메모리 쓰기 펄스 발생
//         CHECK_LOOP,        // 루프 조건 판별
//         FRAME_DONE         // 한 프레임 수신 완료
//     } state_e;

//     state_e state;
//     logic [11:0] loop_cnt;
//     logic [23:0] data_buf0, data_buf1, data_buf2, data_buf3, data_buf4;

//     assign waddr    = loop_cnt;
//     assign fsm_done = (state == FRAME_DONE);

//     // 각 슬레이브가 정상적으로 0x18을 보냈는지 확인하는 조합 논리 회로
//     logic [4:0] status_ready;
//     always_comb begin
//         status_ready[0] = (rx_data[7:0] == 8'h18);
//         status_ready[1] = (rx_data[15:8] == 8'h18);
//         status_ready[2] = (rx_data[23:16] == 8'h18);
//         status_ready[3] = (rx_data[31:24] == 8'h18);
//         status_ready[4] = (rx_data[39:32] == 8'h18);

//         we = 5'b00000;
//         wdata = {data_buf4, data_buf3, data_buf2, data_buf1, data_buf0};

//         // 메모리에 쓸 때는 준비 완료(spi_error가 0)된 채널만 활성화하여 씀
//         if (state == WRITE_MEM) begin
//             we = ~spi_error;
//         end
//     end

//     // 고속 상태 제어 블록
//     always_ff @(posedge clk) begin
//         if (reset) begin
//             state     <= FRAME_START;
//             tx_data   <= 8'h00;
//             start     <= 1'b0;
//             ss_n      <= 5'b11111;
//             loop_cnt  <= 0;
//             spi_error <= 5'b00000;
//             data_buf0 <= 24'd0;
//             data_buf1 <= 24'd0;
//             data_buf2 <= 24'd0;
//             data_buf3 <= 24'd0;
//             data_buf4 <= 24'd0;
//         end else begin
//             case (state)
//                 // 1. 트리거 대기
//                 FRAME_START: begin
//                     start     <= 1'b0;
//                     spi_error <= 5'b00000;
//                     if (decoder_start) begin
//                         loop_cnt <= 0;
//                         state    <= SEND_HEADER;
//                     end
//                 end
//                 // 2. 헤더(0xA9) 전송 트리거
//                 SEND_HEADER: begin
//                     if (!busy) begin
//                         ss_n    <= 5'b00000; // 슬레이브 5개 전체 선택
//                         tx_data <= 8'hA9;    // 헤더 값 탑재
//                         start   <= 1'b1;
//                         state   <= WAIT_HEADER_DONE;
//                     end
//                 end
//                 WAIT_HEADER_DONE: begin
//                     start <= 1'b0;
//                     if (done) begin
//                         state <= READ_STATUS;
//                     end
//                 end
//                 // 3. 1바이트 상태값 읽기 트리거
//                 READ_STATUS: begin
//                     if (!busy) begin
//                         tx_data <= 8'h00;  // 더미 데이터 송신
//                         start   <= 1'b1;
//                         state   <= WAIT_STATUS;
//                     end
//                 end
//                 // 🌟 핵심: 수신된 상태가 0x18인지 판단하는 지점
//                 WAIT_STATUS: begin
//                     start <= 1'b0;
//                     if (done) begin
//                         // 0x18을 보내지 못한 슬레이브는 에러(1) 처리
//                         spi_error <= ~status_ready;

//                         // 최소 하나의 슬레이브라도 준비가 되었다면 수신 진행
//                         if (status_ready != 5'b00000) begin
//                             state <= READ_B1;
//                         end else begin
//                             // 아무도 준비되지 않았다면 통신 중단(Abort) 후 프레임 강제 종료
//                             ss_n  <= 5'b11111;
//                             state <= FRAME_DONE;
//                         end
//                     end
//                 end

//                 // 4. 데이터 바이트 1 수집
//                 READ_B1: begin
//                     if (!busy) begin
//                         tx_data <= 8'h00;
//                         start   <= 1'b1;
//                         state   <= WAIT_B1;
//                     end
//                 end
//                 WAIT_B1: begin
//                     start <= 1'b0;
//                     if (done) begin
//                         data_buf0[23:16] <= rx_data[7:0];
//                         data_buf1[23:16] <= rx_data[15:8];
//                         data_buf2[23:16] <= rx_data[23:16];
//                         data_buf3[23:16] <= rx_data[31:24];
//                         data_buf4[23:16] <= rx_data[39:32];
//                         state            <= READ_B2;
//                     end
//                 end

//                 // 5. 데이터 바이트 2 수집
//                 READ_B2: begin
//                     if (!busy) begin
//                         tx_data <= 8'h00;
//                         start   <= 1'b1;
//                         state   <= WAIT_B2;
//                     end
//                 end
//                 WAIT_B2: begin
//                     start <= 1'b0;
//                     if (done) begin
//                         data_buf0[15:8] <= rx_data[7:0];
//                         data_buf1[15:8] <= rx_data[15:8];
//                         data_buf2[15:8] <= rx_data[23:16];
//                         data_buf3[15:8] <= rx_data[31:24];
//                         data_buf4[15:8] <= rx_data[39:32];
//                         state           <= READ_B3;
//                     end
//                 end

//                 // 6. 데이터 바이트 3 수집
//                 READ_B3: begin
//                     if (!busy) begin
//                         tx_data <= 8'h00;
//                         start   <= 1'b1;
//                         state   <= WAIT_B3;
//                     end
//                 end
//                 WAIT_B3: begin
//                     start <= 1'b0;
//                     if (done) begin
//                         data_buf0[7:0] <= rx_data[7:0];
//                         data_buf1[7:0] <= rx_data[15:8];
//                         data_buf2[7:0] <= rx_data[23:16];
//                         data_buf3[7:0] <= rx_data[31:24];
//                         data_buf4[7:0] <= rx_data[39:32];
//                         state          <= WRITE_MEM;
//                     end
//                 end

//                 // 7. 메모리 쓰기 수행
//                 WRITE_MEM: begin
//                     state <= CHECK_LOOP;
//                 end

//                 // 8. 루프 카운트 검사 (106x120/4 = 3180 픽셀 블록)
//                 CHECK_LOOP: begin
//                     if (loop_cnt == 12'd3179) begin
//                         ss_n  <= 5'b11111;  // 전체 전송 완료 시 CS 해제
//                         state <= FRAME_DONE;
//                     end else begin
//                         loop_cnt <= loop_cnt + 1;
//                         state    <= READ_B1; // 다음 픽셀은 헤더 체크 없이 다이렉트로 수신
//                     end
//                 end

//                 // 9. 한 프레임 완료
//                 FRAME_DONE: begin
//                     state <= FRAME_START;
//                 end

//                 default: state <= FRAME_START;
//             endcase
//         end
//     end
// endmodule

// // ==========================================
// // 3. 5채널 동시 수신용 spi_master (이전과 동일)
// // ==========================================
// module spi_master_5ch (
//     input  logic        clk,
//     input  logic        reset,
//     input  logic        cpol,
//     input  logic        cpha,
//     input  logic [ 7:0] clk_div,
//     input  logic [ 7:0] tx_data,
//     input  logic        start,
//     output logic [39:0] rx_data,
//     output logic        done,
//     output logic        busy,
//     output logic        sclk,
//     output logic        mosi,
//     input  logic [ 4:0] miso,
//     output logic        cs_n
// );
//     typedef enum logic [1:0] {
//         IDLE  = 2'b00,
//         START = 2'b01,
//         DATA  = 2'b10,
//         STOP  = 2'b11
//     } spi_state_e;

//     spi_state_e state;
//     logic [7:0] div_cnt;
//     logic half_tick;
//     logic [7:0] tx_shift_reg;
//     logic [7:0] rx_sr0, rx_sr1, rx_sr2, rx_sr3, rx_sr4;
//     logic [2:0] bit_cnt;
//     logic step, sclk_r;

//     assign sclk = sclk_r;

//     always_ff @(posedge clk or posedge reset) begin
//         if (reset) begin
//             div_cnt   <= 0;
//             half_tick <= 1'b0;
//         end else begin
//             if (state == DATA) begin
//                 if (div_cnt == clk_div) begin
//                     div_cnt   <= 0;
//                     half_tick <= 1'b1;
//                 end else begin
//                     div_cnt   <= div_cnt + 1;
//                     half_tick <= 1'b0;
//                 end
//             end else begin
//                 // 이전 전송의 tick이 다음 전송 첫 DATA cycle에 남지 않도록 초기화
//                 div_cnt   <= 0;
//                 half_tick <= 1'b0;
//             end
//         end
//     end

//     always_ff @(posedge clk or posedge reset) begin
//         if (reset) begin
//             state <= IDLE;
//             mosi <= 1'b1;
//             cs_n <= 1'b1;
//             busy <= 1'b0;
//             done <= 1'b0;
//             tx_shift_reg <= 0;
//             rx_sr0 <= 0;
//             rx_sr1 <= 0;
//             rx_sr2 <= 0;
//             rx_sr3 <= 0;
//             rx_sr4 <= 0;
//             bit_cnt <= 0;
//             step <= 1'b0;
//             rx_data <= 0;
//             sclk_r <= cpol;
//         end else begin
//             done <= 1'b0;
//             case (state)
//                 IDLE: begin
//                     mosi   <= 1'b1;
//                     cs_n   <= 1'b1;
//                     sclk_r <= cpol;
//                     if (start) begin
//                         tx_shift_reg <= tx_data;
//                         bit_cnt <= 0;
//                         step <= 1'b0;
//                         busy <= 1'b1;
//                         cs_n <= 1'b0;
//                         state <= START;
//                     end
//                 end
//                 START: begin
//                     if (!cpha) begin
//                         mosi <= tx_shift_reg[7];
//                         tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
//                     end
//                     state <= DATA;
//                 end
//                 DATA: begin
//                     if (half_tick) begin
//                         sclk_r <= ~sclk_r;
//                         if (step == 0) begin
//                             step <= 1'b1;
//                             if (!cpha) begin
//                                 rx_sr0 <= {rx_sr0[6:0], miso[0]};
//                                 rx_sr1 <= {rx_sr1[6:0], miso[1]};
//                                 rx_sr2 <= {rx_sr2[6:0], miso[2]};
//                                 rx_sr3 <= {rx_sr3[6:0], miso[3]};
//                                 rx_sr4 <= {rx_sr4[6:0], miso[4]};
//                             end else begin
//                                 mosi <= tx_shift_reg[7];
//                                 tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
//                             end
//                         end else begin
//                             step <= 1'b0;
//                             if (!cpha) begin
//                                 if (bit_cnt < 7) begin
//                                     mosi <= tx_shift_reg[7];
//                                     tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
//                                 end
//                             end else begin
//                                 rx_sr0 <= {rx_sr0[6:0], miso[0]};
//                                 rx_sr1 <= {rx_sr1[6:0], miso[1]};
//                                 rx_sr2 <= {rx_sr2[6:0], miso[2]};
//                                 rx_sr3 <= {rx_sr3[6:0], miso[3]};
//                                 rx_sr4 <= {rx_sr4[6:0], miso[4]};
//                             end

//                             if (bit_cnt == 7) begin
//                                 state <= STOP;
//                                 if (!cpha) begin
//                                     // 마지막 샘플은 같은 clock edge에서 rx_sr에
//                                     // non-blocking으로 저장되므로 miso를 직접 결합한다.
//                                     rx_data <= {
//                                         rx_sr4[6:0], miso[4],
//                                         rx_sr3[6:0], miso[3],
//                                         rx_sr2[6:0], miso[2],
//                                         rx_sr1[6:0], miso[1],
//                                         rx_sr0[6:0], miso[0]
//                                     };
//                                 end else begin
//                                     rx_data <= {
//                                         rx_sr4[6:0],
//                                         miso[4],
//                                         rx_sr3[6:0],
//                                         miso[3],
//                                         rx_sr2[6:0],
//                                         miso[2],
//                                         rx_sr1[6:0],
//                                         miso[1],
//                                         rx_sr0[6:0],
//                                         miso[0]
//                                     };
//                                 end
//                             end else begin
//                                 bit_cnt <= bit_cnt + 1;
//                             end
//                         end
//                     end
//                 end
//                 STOP: begin
//                     sclk_r <= cpol;
//                     cs_n   <= 1'b1;
//                     done   <= 1'b1;
//                     busy   <= 1'b0;
//                     mosi   <= 1'b1;
//                     state  <= IDLE;
//                 end
//                 default: begin
//                     state <= IDLE;
//                 end
//             endcase
//         end
//     end
// endmodule
