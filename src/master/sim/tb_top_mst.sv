`timescale 1ns / 1ps

module tb_top_master();

    // ==========================================
    // 1. 신호 선언 (Signals Declaration)
    // ==========================================
    // Inputs (reg 또는 logic으로 선언하여 값을 할당)
    logic clk;
    logic reset;
    
    // 사용하지 않는 입력들도 X 상태 방지를 위해 선언
    logic pclk;
    logic href;
    logic vsync;
    logic [7:0] pdata;
    logic miso;

    // Inouts (wire로 선언해야 함)
    wire sda;

    // Outputs (출력값을 확인하기 위한 wire/logic 선언)
    logic scl;
    logic xclk;
    logic h_sync;
    logic v_sync;
    logic [3:0] port_red;
    logic [3:0] port_green;
    logic [3:0] port_blue;
    logic sclk;
    logic mosi;
    logic [4:0] cs_n;

    // ==========================================
    // 2. 모듈 인스턴스화 (DUT 연결)
    // ==========================================
    top_master uut (
        .clk        (clk),
        .reset      (reset),
        
        .scl        (scl),
        .sda        (sda),
        
        .xclk       (xclk),
        .pclk       (pclk),
        .href       (href),
        .vsync      (vsync),
        .pdata      (pdata),
        
        .h_sync     (h_sync),
        .v_sync     (v_sync),
        .port_red   (port_red),
        .port_green (port_green),
        .port_blue  (port_blue),
        
        .sclk       (sclk),
        .miso       (miso),
        .mosi       (mosi),
        .cs_n       (cs_n)
    );

    // ==========================================
    // 3. 클럭 생성 (Clock Generation)
    // ==========================================
    // 10ns 주기 (100MHz 클럭 가정). 5ns마다 반전.
    always #5 clk = ~clk;

    // ==========================================
    // 4. 시나리오 초기화 및 실행 (Initial Block)
    // ==========================================
    initial begin
        // 초기값 설정 (X 상태 방지)
        clk   = 0;
        reset = 1; // [주의] Active High 리셋 가정. (Active Low면 0으로 시작)
        
        // 안 쓰는 입력 핀들 0으로 고정
        pclk  = 0;
        href  = 0;
        vsync = 0;
        pdata = 8'h00;
        miso  = 0;

        // 20ns 대기 후 리셋 해제 (시스템 동작 시작)
        #20;
        reset = 0; 
        
        // 2000ns(2us) 동안 시뮬레이션 진행 후 종료
        #2000;
        $display("Simulation Finished.");
        $finish;
    end

endmodule