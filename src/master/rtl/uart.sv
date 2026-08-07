`timescale 1 ns / 1 ps

module uart_top #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
) (
    input  wire       clk,        // 100MHz 마스터 시스템 클럭
    input  wire       rst,        // Active High 비동기 리셋 (posedge)
    
    // 외부 제어 인터페이스 (FSM / 시퀀서 연동용)
    input  wire [7:0] tx_data,    // 전송할 8비트 데이터
    input  wire       tx_valid,   // 전송 시작 명령 틱 (1클럭 High)
    output wire       tx_done,    // 전송 완료 응답 틱 (1클럭 High)
    output wire       tx_ready,   // 송신기 가용 상태 (Ready)
    
    // UART 물리 핀 인터페이스
    output wire       tx,         // FPGA -> PC (TXD 핀)
    input  wire       rx          // PC -> FPGA (RXD 핀)
);

    // 최상위 포트에서 제외된 수신 신호들을 내부 wire로 처리하여 컴파일 에러 방지
    wire [7:0] rx_data;
    wire       rx_valid;

    // ====================================================
    // 하위 IP 모듈 인스턴스화
    // ====================================================
    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_tx (
        .clk    (clk),
        .rst    (rst),
        .data_in(tx_data),
        .valid  (tx_valid),
        .ready  (tx_ready),
        .done   (tx_done),        // 송신 완료 틱 신호 연결
        .tx     (tx)
    );

    uart_rx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_rx (
        .clk     (clk),
        .rst     (rst),
        .rx      (rx),
        .data_out(rx_data),
        .valid   (rx_valid)
    );

endmodule



module uart_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data_in,  
    input  wire       valid,    
    output reg        ready,    
    output reg        done,       // 송신 완료 1클럭 틱 출력 포트
    output reg        tx        
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    
    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [                   1:0] state;
    reg [$clog2(CLKS_PER_BIT):0] clk_cnt;
    reg [                   2:0] bit_idx;
    reg [                   7:0] shift_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= S_IDLE;
            clk_cnt   <= 0;
            bit_idx   <= 0;
            shift_reg <= 8'h00;
            tx        <= 1'b1;  
            ready     <= 1'b1;
            done      <= 1'b0;
        end else begin
            done <= 1'b0; // 기본적으로 무조건 De-assert (1tick 유지를 위한 로직)

            case (state)
                S_IDLE: begin
                    tx    <= 1'b1;
                    ready <= 1'b1;
                    if (valid) begin
                        shift_reg <= data_in;
                        clk_cnt   <= 0;
                        ready     <= 1'b0;
                        state     <= S_START;
                    end
                end

                S_START: begin
                    tx <= 1'b0; 
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        bit_idx <= 0;
                        state   <= S_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_DATA: begin
                    tx <= shift_reg[bit_idx]; 
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_STOP: begin
                    tx <= 1'b1; 
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        ready   <= 1'b1;
                        done    <= 1'b1;  // TX 물리 전송이 완전히 완료된 클럭 순간 1틱 발생
                        state   <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule



module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,        
    output reg  [7:0] data_out,  
    output reg        valid      
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam HALF_BIT     = CLKS_PER_BIT / 2;

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [                   1:0] state;
    reg [$clog2(CLKS_PER_BIT):0] clk_cnt;
    reg [                   2:0] bit_idx;
    reg [                   7:0] shift_reg;
    reg rx_sync0, rx_sync;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sync0 <= 1'b1;
            rx_sync  <= 1'b1;
        end else begin
            rx_sync0 <= rx;
            rx_sync  <= rx_sync0;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= S_IDLE;
            clk_cnt   <= 0;
            bit_idx   <= 0;
            shift_reg <= 8'h00;
            data_out  <= 8'h00;
            valid     <= 1'b0;
        end else begin
            valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (rx_sync == 1'b0)
                        state <= S_START;
                end

                S_START: begin
                    if (clk_cnt == HALF_BIT - 1) begin
                        clk_cnt <= 0;
                        if (rx_sync == 1'b0)
                            state <= S_DATA;
                        else 
                            state <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt            <= 0;
                        shift_reg[bit_idx] <= rx_sync;
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt  <= 0;
                        data_out <= shift_reg;
                        valid    <= 1'b1;
                        state    <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule