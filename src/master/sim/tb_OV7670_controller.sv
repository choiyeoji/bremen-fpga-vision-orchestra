`timescale 1ns / 1ps

module tb_OV7670_controller;

    // ==========================================
    // 1. 신호 선언
    // ==========================================
    logic clk;
    logic reset;
    logic start;
    wire  scl;
    wire  sda;

    // I2C/SCCB 버스 하드웨어 풀업 (필수)
    pullup (sda);

    // 가상 슬레이브 제어 신호
    logic slave_en;
    logic sda_out;
    
    // Open-Drain 구동
    assign sda = (slave_en && (sda_out == 1'b0)) ? 1'b0 : 1'bz;

    // ==========================================
    // 2. DUT (Device Under Test) 인스턴스화
    // ==========================================
    OV7670_controller uut (
        .clk  (clk),
        .reset(reset),
        .start(start),
        .scl  (scl),
        .sda  (sda)
    );

    // ==========================================
    // 3. 클럭 생성 (100MHz 기준, 10ns 주기)
    // ==========================================
    always #5 clk = ~clk;

    // ==========================================
    // 4. 메인 테스트 시퀀스 (Stimulus)
    // ==========================================
    initial begin
        // 초기화
        clk      = 0;
        reset    = 1;
        start    = 0;
        slave_en = 0;
        sda_out  = 1;

        // 리셋 해제 (초기화 안정화 대기)
        #100;
        reset = 0;
        #100;

        // 컨트롤러 동작 시작 버튼(start) 펄스 인가
        $display("[TB] 📷 OV7670 Controller Test Started...");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // ROM의 모든 초기화 시퀀스가 끝날 때까지 충분히 대기
        // (실제 ROM 크기와 I2C 속도에 따라 이 시간은 유동적으로 늘려야 할 수 있습니다)
        #500000; 
        
        $display("[TB] 🏁 Simulation Finished.");
        $finish;
    end

    // ==========================================
    // 5. 스마트 가상 슬레이브 (Auto-Responding Mock Slave)
    // ==========================================
    initial begin : VIRTUAL_SLAVE
        logic [7:0] mock_read_data = 8'hA5; // 컨트롤러가 읽어갈 가상 데이터

        forever begin
            // 이전 트러블슈팅의 핵심: DUT 내부의 FSM 상태를 직접 모니터링!
            // 1) 상태가 STOP (3'b101) 이고
            // 2) 현재 동작이 Read 모드 (!write_reg) 일 때까지 무한 대기
            wait(uut.U_SCCB.U_SCCB_FSM.state == 3'b101 && uut.U_SCCB.U_SCCB_FSM.write_reg == 1'b0);

            // Read 동작 감지됨! 데이터 전송 시작 (첫 비트 미리 띄우기)
            slave_en = 1;
            sda_out  = mock_read_data[7]; 
            
            // 나머지 7비트 전송 (SCL 하강 에지 동기화)
            for (int i = 6; i >= 0; i--) begin
                @(negedge scl);
                sda_out = mock_read_data[i];
            end
            
            // 8비트 전송 완료 후 버스 릴리즈
            @(negedge scl);
            slave_en = 0;
            sda_out  = 1;

            // FSM이 STOP 상태를 빠져나갈 때까지 대기 (중복 실행 방지)
            wait(uut.U_SCCB.U_SCCB_FSM.state != 3'b101);
        end
    end

    // ==========================================
    // 6. I2C 통신 모니터 (디버깅용 자동 로그 출력)
    // ==========================================
    // FSM이 하나의 명령을 끝내고 IDLE로 돌아갈 때마다 어떤 주소/데이터를 다루었는지 출력합니다.
    always @(posedge clk) begin
        if (uut.U_SCCB.U_SCCB_FSM.state == 3'b110) begin // GOTO_IDLE 상태 진입 시
            if (uut.U_SCCB.U_SCCB_FSM.write_reg)
                $display("[%0t] SCCB WRITE -> Reg: 8'h%h, Data: 8'h%h", $time, uut.U_SCCB.fsm_addr, uut.U_SCCB.fsm_wdata);
            else
                $display("[%0t] SCCB READ  <- Reg: 8'h%h, Data: 8'h%h", $time, uut.U_SCCB.fsm_addr, uut.U_SCCB.fsm_rdata);
        end
    end

endmodule