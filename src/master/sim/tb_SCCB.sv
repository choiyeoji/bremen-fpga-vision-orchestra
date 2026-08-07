`timescale 1ns / 1ps

module tb_SCCB;

    // 신호 선언
    logic       clk;
    logic       reset;
    logic       start;
    logic       write;
    logic [7:0] fsm_addr;
    logic [7:0] fsm_wdata;
    logic [7:0] fsm_rdata;
    logic       ready;
    logic       scl;
    wire        sda;

    // 🌟 핵심 해결책: I2C/SCCB 버스 하드웨어 풀업 유지
    pullup (sda);

    // 가상 슬레이브 드라이버 신호
    logic sda_out;
    logic slave_en;
    
    // Open-Drain 방식으로 슬레이브 구동 (0일 때만 밀고, 1일 때는 놔주기)
    assign sda = (slave_en && (sda_out == 1'b0)) ? 1'b0 : 1'bz;

    // DUT 인스턴스화
    SCCB uut (
        .clk      (clk),
        .reset    (reset),
        .start    (start),
        .write    (write),
        .fsm_addr (fsm_addr),
        .fsm_wdata(fsm_wdata),
        .fsm_rdata(fsm_rdata),
        .ready    (ready),
        .scl      (scl),
        .sda      (sda)
    );

    // 100MHz 클럭 생성 (10ns 주기)
    always #5 clk = ~clk;

    initial begin
        // 초기화
        clk       = 0;
        reset     = 1;
        start     = 0;
        write     = 0;
        fsm_addr  = 8'h00;
        fsm_wdata = 8'h00;
        slave_en  = 0;
        sda_out   = 1;

        // 리셋 해제
        #40;
        reset = 0;
        #20;

        // ==========================================
        // 1. TX TEST (Write 동작: Reg 0x07에 0x55 쓰기)
        // ==========================================
        $display("[TB] Start TX (Write) Test...");
        @(posedge clk);
        while (!ready) @(posedge clk); 

        start     = 1;
        write     = 1;         
        fsm_addr  = 8'h07;     
        fsm_wdata = 8'h55;     
        
        @(posedge clk);
        start     = 0;         

        // FSM 완료 대기
        @(posedge clk);
        while (!ready) @(posedge clk);
        $display("[TB] TX Test Completed.\n");
        #200;

        // ==========================================
        // 2. RX TEST (Read 동작: Reg 0x07 읽기 시도)
        // ==========================================
        $display("[TB] Start RX (Read) Test...");
        
        fork
            // [마스터 구동 블록]
            begin
                start     = 1;
                write     = 0;         // Read Mode
                fsm_addr  = 8'h07;     
                @(posedge clk);
                start     = 0;
            end
            
// [가상 슬레이브 응답 블록 - 상태 트리거 완벽 보정 버전]
            begin
                logic [7:0] mock_data = 8'hA5;
                
                // 1. 핵심 수정: 마스터가 실제로 Read SCL 클럭을 생성하는 'STOP' 상태(3'b101)까지 대기
                wait(uut.U_SCCB_FSM.state == 3'b101); 
                
                // 2. STOP 상태 진입 직후, 마스터가 첫 클럭(High)을 읽기 전에 미리 MSB를 띄워둠
                slave_en = 1;
                sda_out  = mock_data[7]; 
                
                // 3. 나머지 7개 비트는 SCL 하강 에지(Low 구간)에 맞춰 순차적 변경
                for (int i = 6; i >= 0; i--) begin
                    @(negedge scl);      
                    sda_out = mock_data[i]; 
                end
                
                // 4. 전송 완료 후 마스터가 마무리할 수 있도록 버스 릴리즈
                @(negedge scl);
                slave_en = 0;              
                sda_out  = 1;
            end
        join

        // 완료 대기
        @(posedge clk);
        while (!ready) @(posedge clk);
        
        $display("[TB] RX Test Completed. Read Data = 8'h%h", fsm_rdata);
        
        #200;
        $finish;
    end

endmodule