`timescale 1ns / 1ps

module mem_controller (
    input  logic       clk,
    input  logic       reset,
    // Decoder
    input  logic [9:0] x_pixel,
    input  logic [9:0] y_pixel,
    input  logic       de,
    // SPI side
    output logic       SPI_start,
    input  logic [4:0] SPI_error,
    input  logic       SPI_fsm_done,
    // Mem write side
    output logic [4:0] w_sel,
    // Mem read side
    output logic [4:0] r_sel
);

    logic [4:0] r_sel_reg, w_sel_reg;
    logic       fsm_done_reg;
    logic [4:0] SPI_error_reg;
    logic       switch_done_in_frame;
    logic       switch_window;

    assign r_sel = r_sel_reg;
    assign w_sel = w_sel_reg;
    assign switch_window = (x_pixel > 10'd640) &&
                           (y_pixel >= 10'd480) && !de;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            r_sel_reg     <= 5'b00000;
            // VGA는 A(0)를 읽고 SPI는 B(1)에 써서 처음부터 충돌을 방지한다.
            w_sel_reg     <= 5'b11111;
            fsm_done_reg  <= 1'b0;
            SPI_error_reg <= 5'b00000;
            SPI_start     <= 1'b0;
            switch_done_in_frame <= 1'b0;
        end else begin
            
            // [핵심 수정] 매 클럭마다 기본적으로 SPI_start를 0으로 낮춥니다.
            // 아래 조건문에서 1을 주더라도, 다음 클럭이 되면 이 구문에 의해 다시 0으로 돌아갑니다 (1클럭 펄스 생성).
            SPI_start <= 1'b0; 

            // SPI 완료 결과는 버퍼 교체 시점까지 보관한다.
            if (SPI_fsm_done) begin
                fsm_done_reg  <= 1'b1;
                SPI_error_reg <= SPI_error;
            end

            // 다음 VGA 프레임에서 다시 한 번 버퍼를 교체할 수 있도록 arm 한다.
            if (y_pixel == 0 && x_pixel == 0) begin
                switch_done_in_frame <= 1'b0;
            end

            // x>640, y>=480인 vertical blank 구간의 첫 cycle에만 실행한다.
            // r_sel/w_sel을 같은 mask로 동시에 토글하면 항상 서로 반대 버퍼를 가리킨다.
            if (switch_window && !switch_done_in_frame) begin
                switch_done_in_frame <= 1'b1;
                SPI_start            <= 1'b1;
                if (fsm_done_reg) begin
                    r_sel_reg    <= r_sel_reg ^ (~SPI_error_reg);
                    w_sel_reg    <= w_sel_reg ^ (~SPI_error_reg);
                    fsm_done_reg <= 1'b0;
                end
            end
        end
    end
endmodule
