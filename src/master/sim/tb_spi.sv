`timescale 1ns / 1ps

module tb_SPI_Integration();

    // ==========================================
    // 1. 시스템 클럭 및 리셋
    // ==========================================
    logic clk;
    logic reset;

    // ==========================================
    // 2. Master (SPI_sender) 연결 와이어
    // ==========================================
    logic        decoder_start;
    logic        fsm_done;
    logic [ 4:0] SPI_error;
    logic        sclk;
    logic        mosi;
    logic [ 4:0] miso;
    logic [ 4:0] cs_n;
    logic [ 4:0] we;
    logic [11:0] waddr;
    logic [119:0] wdata;

    // ==========================================
    // 3. Slave (SPI_Slave) 연결 와이어
    // ==========================================
    logic [4:0] push;
    logic [7:0] push_data [0:4];
    logic [4:0] full;
    logic [4:0] frame_ready;
    logic [4:0] sender_busy;
    logic [4:0] send_start;
    logic [4:0] sending;
    logic [4:0] send_done;

    // ==========================================
    // 4. 모듈 인스턴스화
    // ==========================================
    
    // Master 인스턴스
    SPI_sender U_MASTER (
        .clk(clk),
        .reset(reset),
        .decoder_start(decoder_start),
        .fsm_done(fsm_done),
        .SPI_error(SPI_error),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .cs_n(cs_n),
        .we(we),
        .waddr(waddr),
        .wdata(wdata)
    );

    // 5개의 Slave 인스턴스화 및 카메라 데이터 가짜 주입기
    genvar i;
    generate
        for (i = 0; i < 5; i++) begin : SLAVE_INST
            SPI_Slave U_SLAVE (
                .clk(clk),
                .reset(reset),
                .sclk(sclk),
                .mosi(mosi),
                .cs_n(cs_n[i]),
                .miso(miso[i]),
                .push(push[i]),
                .push_data(push_data[i]),
                .full(full[i]),
                .frame_ready(frame_ready[i]),
                .sender_busy(sender_busy[i]),
                .send_start(send_start[i]),
                .sending(sending[i]),
                .send_done(send_done[i])
            );

            // 가상 카메라 로직: FIFO가 꽉 차지 않았다면 계속해서 가짜 데이터를 밀어넣음
            // 슬레이브 0번은 0x01, 0x02.. 슬레이브 1번은 0x11, 0x12.. 로 들어감 (구분용)
            always_ff @(posedge clk) begin
                if (reset) begin
                    push[i]      <= 1'b0;
                    push_data[i] <= {i[3:0], 4'h0}; // 초기값 세팅 (예: 0x00, 0x10, 0x20...)
                end else begin
                    if (!full[i]) begin
                        push[i]      <= 1'b1;
                        push_data[i] <= push_data[i] + 1; // 1씩 증가하는 패턴 주입
                    end else begin
                        push[i]      <= 1'b0;
                    end
                end
            end
        end
    endgenerate

    // ==========================================
    // 5. 클럭 생성 (100MHz = 10ns 주기)
    // ==========================================
    always #5 clk = ~clk;

    // ==========================================
    // 6. 테스트 시나리오
    // ==========================================
    initial begin
        // 초기화
        clk = 0;
        reset = 1;
        decoder_start = 0;
        frame_ready = 5'b11111; // 5개 슬레이브 모두 준비 완료 상태
        sender_busy = 5'b00000;
        
        #100;
        reset = 0;
        #200;

        // ----------------------------------------------------
        // [시나리오 1] 정상 동작: 5개 슬레이브 모두 0x18 응답
        // ----------------------------------------------------
        $display("--- Scenario 1: All 5 Slaves Ready ---");
        decoder_start = 1;
        #10;
        decoder_start = 0;

        // Master가 10개의 픽셀 블록(주소 0~9)을 성공적으로 쓸 때까지 대기
        wait (waddr == 12'd9 && we == 5'b11111);
        #500;
        
        // ----------------------------------------------------
        // [시나리오 2] 에러 동작: 2번 슬레이브 준비 안됨 (에러 핸들링 검증)
        // ----------------------------------------------------
        $display("--- Scenario 2: Slave 2 Not Ready (Error Handling) ---");
        // 강제로 통신을 끊고 리셋
        reset = 1;
        #100;
        reset = 0;
        #100;
        
        // 2번 슬레이브(가운데)의 준비 상태를 '0'으로 만듦
        frame_ready = 5'b11011; 
        
        // 다시 통신 시작
        decoder_start = 1;
        #10;
        decoder_start = 0;

        // 에러 상태를 감지하여 2번 슬레이브 메모리 공간에만 'we'가 꺼지는지 확인
        // we가 5'b11011 로 출력되어야 정상
        wait (waddr == 12'd2);
        #500;
        
        $display("Simulation Complete! Check the Waveforms.");
        $finish;
    end

endmodule