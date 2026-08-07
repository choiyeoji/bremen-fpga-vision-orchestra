`timescale 1ns / 1ps

module SPI_controller (
    input  logic                   clk,
    input  logic                   reset,
    // VGA_decoder side
    input  logic [$clog2(800)-1:0] x_pixel,      // h_count 전체를 받음
    input  logic [$clog2(525)-1:0] y_pixel,      // v_count 전체를 받음
    // SPI side
    output logic [           13:0] spi_tx_data,
    output logic                   start,
    input  logic                   done,
    input  logic                   busy,
    output logic [            2:0] slv_select,
    // Mem write side
    output logic                   wline,
    output logic [            6:0] wAddr,
    output logic we
);

    // --- FSM 상태 정의 ---
    typedef enum logic [3:0] {
        READY = 0,
        CHECK_SLAVES,
        SEND_SYNC,
        WAIT_SYNC_DONE,
        WAIT_5CLK,
        READ_PIXEL,
        WAIT_READ_DONE,
        NEXT_SLAVE
    } state_e;

    state_e state;

    // --- 내부 레지스터 ---
    logic [7:0] next_y;
    logic [7:0] local_y;     // 슬레이브에게 보낼 0~119 라인 번호
    logic [2:0] current_slv; // 현재 통신 중인 슬레이브 인덱스
    logic [2:0] wait_cnt;    // 5 클럭 대기 카운터
    logic [6:0] pixel_cnt;   // 106 픽셀 카운터 (0~105)


    assign wAddr = pixel_cnt;
    assign we = (state == WAIT_READ_DONE) && done;

    // --- 메인 상태 머신 ---
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state       <= READY;
            start       <= 1'b0;
            spi_tx_data <= 13'h00;
            slv_select  <= 3'b000;
            wait_cnt    <= 0;
            pixel_cnt   <= 0;
            current_slv <= 0;
            next_y      <= 0;
            local_y     <= 0;
            wline       <= 0;
        end else begin
            case (state)
                READY: begin
                    start <= 1'b0;
                    // 디스플레이 영역(x=319)이 끝날 때 다음 라인(y+1) 프리페치 시작
                    if (x_pixel == 319 && y_pixel < 239) begin
                        next_y <= y_pixel + 1;
                        state  <= CHECK_SLAVES;
                    end
                end
                CHECK_SLAVES: begin
                    // 다음 Y 라인에 따라 통신할 첫 번째 슬레이브 결정
                    if (next_y < 120) begin
                        current_slv <= 3'd0; // 상단 라인: SLV0 부터 시작
                        local_y <= next_y;
                    end else begin
                        current_slv <= 3'd3; // 하단 라인: SLV3 부터 시작
                        local_y <= next_y - 120;  // 0~119로 정규화
                    end
                    state <= SEND_SYNC;
                end
                SEND_SYNC: begin
                    if (!busy) begin
                        slv_select  <= current_slv;
                        // 앞 4비트는 0, 뒤 8비트는 라인 번호 (총 12비트 전송)
                        spi_tx_data <= {6'h0, local_y};
                        start       <= 1'b1;
                        state       <= WAIT_SYNC_DONE;
                    end
                end
                WAIT_SYNC_DONE: begin
                    start <= 1'b0;  // 트리거 신호 끄기
                    if (done) begin
                        wait_cnt <= 0;
                        state    <= WAIT_5CLK; // 싱크 전송 완료 후 5클럭 턴어라운드 진입
                    end
                end
                WAIT_5CLK: begin
                    // 슬레이브가 데이터를 준비할 5 clock 대기
                    if (wait_cnt == 4) begin
                        pixel_cnt <= 0;
                        state     <= READ_PIXEL;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end
                READ_PIXEL: begin
                    if (!busy) begin
                        spi_tx_data <= 13'h00;  // 읽기용 더미 데이터
                        start       <= 1'b1;
                        state       <= WAIT_READ_DONE;
                    end
                end
                WAIT_READ_DONE: begin
                    start <= 1'b0;
                    if (done) begin
                        if (pixel_cnt == 105) begin // 106 픽셀 모두 읽음
                            state <= NEXT_SLAVE;
                        end else begin
                            pixel_cnt <= pixel_cnt + 1;
                            state     <= READ_PIXEL;  // 다음 픽셀 읽기
                        end
                    end
                end
                NEXT_SLAVE: begin
                    // 해당 라인의 다음 슬레이브 지정 (SLV1은 내부 이미지라 건너뜀)
                    if (current_slv == 0) begin
                        current_slv <= 3'd2;  // SLV0 끝 -> SLV2 시작
                        state       <= SEND_SYNC;
                    end else if (current_slv == 3) begin
                        current_slv <= 3'd4;  // SLV3 끝 -> SLV4 시작
                        state       <= SEND_SYNC;
                    end else if (current_slv == 4) begin
                        current_slv <= 3'd5;  // SLV4 끝 -> SLV5 시작
                        state       <= SEND_SYNC;
                    end else begin
                        // 현재 라인에 필요한 외부 슬레이브 데이터 수신 완료
                        state <= READY;
                        wline <= wline + 1;
                    end
                end
                default: state <= READY;
            endcase
        end
    end

endmodule
