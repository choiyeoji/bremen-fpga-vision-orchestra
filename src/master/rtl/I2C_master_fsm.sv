`timescale 1ns / 1ps

module I2C_master_fsm (
    input logic clk,
    input logic rst,
    input logic start_i2c_fsm,  // [추가] 외부 시작 틱 신호
    input logic [1:0] m_note,  // [추가] 외부 입력 데이터
    output logic [11:0] note,
    output logic dbg_ack_slv1,
    output logic scl,  // [수정] 표준 I2C를 위해 inout으로 선언
    inout wire sda,
    output logic done
);
    typedef enum logic [2:0] {
        IDLE,
        SLV1,
        SLV2,
        SLV3,
        SLV4,
        SLV5
    } i2c_master_e;

    localparam SLA_R1 = {7'h01, 1'b1};
    localparam SLA_R2 = {7'h02, 1'b1};
    localparam SLA_R3 = {7'h04, 1'b1};
    localparam SLA_R4 = {7'h08, 1'b1};
    localparam SLA_R5 = {7'h10, 1'b1};

    i2c_master_e state;
    logic [7:0] w_addr, w_rdata;
    logic w_start_t, done_top;
    logic [11:0] reg_note;

    assign dbg_ack = o_ack_out;

    i2c_read_top U_I2C_READ_TOP (
        .clk       (clk),
        .reset     (rst),
        .addr      (w_addr),
        .start_tick(w_start_t),
        .rdata     (w_rdata),
        .o_done    (done_top),
        .o_ack_out (o_ack_out),
        .scl       (scl),
        .sda       (sda)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= IDLE;
            note         <= 0;
            w_addr       <= 0;
            w_start_t    <= 0;
            reg_note     <= 0;
            done         <= 0;
            dbg_ack_slv1 <= 1'b1;
        end else begin
            done <= 0;
            w_start_t <= 1'b0; // 하위 모듈이 오작동하지 않게 항상 펄스(1클럭) 형태로 제어

            case (state)
                IDLE: begin
                    // note <= reg_note; // [수정] 다중 할당 제거, 한 사이클 완료 후 최종 데이터만 출력 래치

                    if (start_i2c_fsm) begin // [수정] 외부 틱 신호로 시작
                        state <= SLV1;
                        w_start_t <= 1'b1;
                        w_addr <= SLA_R1;
                        reg_note[3:2] <= m_note; // [수정] 시작과 동시에 외부 데이터 래치
                        note <= {reg_note[11:4], m_note, reg_note[1:0]};
                    end
                end
                SLV1: begin
                    if (done_top) begin
                        dbg_ack_slv1  <= o_ack_out;
                        state         <= SLV2;
                        w_start_t     <= 1'b1;
                        w_addr        <= SLA_R2;
                        reg_note[1:0] <= w_rdata[1:0];
                    end
                end
                SLV2: begin
                    if (done_top) begin
                        state         <= SLV3;
                        w_start_t     <= 1'b1;
                        w_addr        <= SLA_R3;
                        reg_note[5:4] <= w_rdata[1:0];
                    end
                end
                SLV3: begin
                    if (done_top) begin
                        state         <= SLV4;
                        w_start_t     <= 1'b1;
                        w_addr        <= SLA_R4;
                        reg_note[7:6] <= w_rdata[1:0];
                    end
                end
                SLV4: begin
                    if (done_top) begin
                        state         <= SLV5;
                        w_start_t     <= 1'b1;
                        w_addr        <= SLA_R5;
                        reg_note[9:8] <= w_rdata[1:0];
                    end
                end
                SLV5: begin
                    if (done_top) begin
                        state <= IDLE;
                        done <= 1;
                        note <= {
                            w_rdata[1:0],  // [11:10] SLV5
                            reg_note[9:8],  // SLV4
                            reg_note[7:6],  // SLV3
                            reg_note[5:4],  // SLV2
                            reg_note[3:2],  // m_note (마스터)
                            reg_note[1:0]
                        };  // SLV1
                        reg_note[11:10] <= w_rdata[1:0];
                    end
                end
            endcase
        end
    end
endmodule


module i2c_read_top (
    input  logic       clk,
    input  logic       reset,
    input  logic [7:0] addr,
    input  logic       start_tick,
    output logic [7:0] rdata,
    output logic       o_done,
    output logic       o_ack_out,
    inout  wire        scl,         // [수정]
    inout  wire        sda
);
    // [수정] 하위 FSM과의 핸드쉐이킹 1-Delay 타이밍 꼬임을 막기 위해 명령(CMD)과 대기(WAIT) 상태를 분리
    typedef enum logic [3:0] {
        IDLE       = 0,
        START_CMD,
        START_WAIT,
        ADDR_CMD,
        ADDR_WAIT,
        READ_CMD,
        READ_WAIT,
        STOP_CMD,
        STOP_WAIT
    } i2c_state_e;

    i2c_state_e       state;
    logic             cmd_start;
    logic             cmd_write;
    logic             cmd_read;
    logic             cmd_stop;
    logic       [7:0] tx_data;

    logic             ack_in;
    assign ack_in = 1'b1;

    logic [7:0] rx_data;
    logic       done;
    logic       ack_out;
    logic       busy;
    logic [7:0] reg_addr;

    assign o_ack_out = ack_out;

    I2C_Master_d U_I2C_Master (
        .clk      (clk),
        .reset    (reset),
        .cmd_start(cmd_start),
        .cmd_write(cmd_write),
        .cmd_read (cmd_read),
        .cmd_stop (cmd_stop),
        .tx_data  (tx_data),
        .ack_in   (ack_in),
        .rx_data  (rx_data),
        .done     (done),
        .ack_out  (ack_out),
        .busy     (busy),
        .scl      (scl),
        .sda      (sda)
    );

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state     <= IDLE;
            cmd_start <= 1'b0;
            cmd_write <= 1'b0;
            cmd_read  <= 1'b0;
            cmd_stop  <= 1'b0;
            reg_addr  <= 0;
            rdata     <= 0;
            o_done    <= 0;
        end else begin
            o_done <= 1'b0;

            case (state)
                IDLE: begin
                    cmd_start <= 1'b0;
                    cmd_write <= 1'b0;
                    cmd_read  <= 1'b0;
                    cmd_stop  <= 1'b0;
                    if (start_tick) begin
                        state    <= START_CMD;
                        reg_addr <= addr;
                        rdata    <= 8'h00;
                    end
                end

                START_CMD: begin
                    cmd_start <= 1'b1;
                    state     <= START_WAIT;
                end
                START_WAIT: begin
                    cmd_start <= 1'b0;
                    if (done) state <= ADDR_CMD;
                end

                ADDR_CMD: begin
                    cmd_write <= 1'b1;
                    tx_data   <= reg_addr;
                    state     <= ADDR_WAIT;
                end
                ADDR_WAIT: begin
                    cmd_write <= 1'b0;
                    if (done) begin
                        if (ack_out == 1'b0) begin
                            state <= READ_CMD;
                        end else begin
                            state <= STOP_CMD;
                        end
                    end
                end

                READ_CMD: begin
                    cmd_read <= 1'b1;
                    state    <= READ_WAIT;
                end
                READ_WAIT: begin
                    cmd_read <= 1'b0;
                    if (done) begin
                        state <= STOP_CMD;
                        rdata <= rx_data;
                    end
                end

                STOP_CMD: begin
                    cmd_stop <= 1'b1;
                    state    <= STOP_WAIT;
                end
                STOP_WAIT: begin
                    cmd_stop <= 1'b0;
                    if (done) begin
                        state  <= IDLE;
                        o_done <= 1'b1;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule


module I2C_Master_d (
    input  logic       clk,
    input  logic       reset,
    input  logic       cmd_start,
    input  logic       cmd_write,
    input  logic       cmd_read,
    input  logic       cmd_stop,
    input  logic [7:0] tx_data,
    input  logic       ack_in,
    output logic [7:0] rx_data,
    output logic       done,
    output logic       ack_out,
    output logic       busy,
    inout  wire        scl,        // [수정]
    inout  logic       sda
);
    logic scl_o, sda_o, sda_i;

    assign sda_i = sda;
    assign sda   = sda_o ? 1'bz : 1'b0;
    assign scl   = scl_o;
    // assign scl   = scl_o ? 1'bz : 1'b0; // [수정] SCL Open-Drain 구성

    i2c_master_d u_i2c_master_d (
        .*,
        .scl_o(scl_o),
        .sda_o(sda_o),
        .sda_i(sda_i)
    );
endmodule

module i2c_master_d (
    input  logic       clk,
    input  logic       reset,
    input  logic       cmd_start,
    input  logic       cmd_write,
    input  logic       cmd_read,
    input  logic       cmd_stop,
    input  logic [7:0] tx_data,
    input  logic       ack_in,
    output logic [7:0] rx_data,
    output logic       done,
    output logic       ack_out,
    output logic       busy,
    output logic       scl_o,      // [수정]
    output logic       sda_o,
    input  logic       sda_i
);

    typedef enum logic [2:0] {
        IDLE = 3'b000,
        START,
        WAIT_CMD,
        DATA,
        DATA_ACK,
        STOP
    } i2c_state_e;
    i2c_state_e state;
    logic [7:0] div_cnt;
    logic qtr_tick;
    logic scl_r, sda_r;
    logic [1:0] step;
    logic [7:0] tx_shift_reg, rx_shift_reg;
    logic [2:0] bit_cnt;
    logic is_read, ack_in_r;

    assign scl_o = scl_r;
    assign sda_o = sda_r;
    assign busy  = (state != IDLE);

    logic sda_i_sync0, sda_i_sync;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            sda_i_sync0 <= 1'b1;
            sda_i_sync  <= 1'b1;
        end else begin
            sda_i_sync0 <= sda_i;
            sda_i_sync  <= sda_i_sync0;
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            div_cnt  <= 0;
            qtr_tick <= 1'b0;
        end else begin
            if (div_cnt == 250 - 1) begin  // scl : 100khz
                div_cnt  <= 0;
                qtr_tick <= 1'b1;
            end else begin
                div_cnt  <= div_cnt + 1;
                qtr_tick <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state        <= IDLE;
            scl_r        <= 1'b1;
            sda_r        <= 1'b1;
            step         <= 0;
            done         <= 1'b0;
            tx_shift_reg <= 0;
            rx_shift_reg <= 0;
            is_read      <= 1'b0;
            bit_cnt      <= 0;
            ack_in_r     <= 1'b1;
            ack_out      <= 1'b1;
        end else begin
            done <= 1'b0;  // 매 클럭 초기화하여 펄스 신호 보장

            case (state)
                IDLE: begin
                    scl_r <= 1'b1;
                    sda_r <= 1'b1;
                    busy  <= 1'b0;
                    if (cmd_start) begin
                        state <= START;
                        step  <= 0;
                    end
                end

                START: begin
                    if (qtr_tick) begin
                        case (step)
                            2'd0: begin
                                sda_r <= 1'b1;
                                scl_r <= 1'b1;
                                step  <= 2'd1;
                            end
                            2'd1: begin
                                sda_r <= 1'b0;
                                step  <= 2'd2;
                            end
                            2'd2: begin
                                step <= 2'd3;
                            end
                            2'd3: begin
                                scl_r <= 1'b0;
                                step  <= 2'd0;
                                done  <= 1'b1;
                                state <= WAIT_CMD;
                            end
                        endcase
                    end
                end

                WAIT_CMD: begin
                    step <= 0;
                    if (cmd_write) begin
                        tx_shift_reg <= tx_data;
                        bit_cnt <= 0;
                        is_read <= 1'b0;
                        state <= DATA;
                    end else if (cmd_read) begin
                        rx_shift_reg <= 0;
                        bit_cnt <= 0;
                        is_read <= 1'b1;
                        ack_in_r <= ack_in;
                        state <= DATA;
                    end else if (cmd_stop) begin
                        state <= STOP;
                    end else if (cmd_start) begin
                        state <= START;
                    end
                end

                DATA: begin
                    if (qtr_tick) begin
                        case (step)
                            2'd0: begin
                                scl_r <= 1'b0;
                                sda_r <= is_read ? 1'b1 : tx_shift_reg[7];
                                step  <= 2'd1;
                            end
                            2'd1: begin
                                scl_r <= 1'b1;
                                step  <= 2'd2;
                            end
                            2'd2: begin
                                scl_r <= 1'b1;
                                if (is_read) begin
                                    rx_shift_reg <= {
                                        rx_shift_reg[6:0], sda_i_sync
                                    };
                                end
                                step <= 2'd3;
                            end
                            2'd3: begin
                                scl_r <= 1'b0;
                                if (!is_read) begin
                                    tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                                end
                                step <= 2'd0;
                                if (bit_cnt == 7) begin
                                    state <= DATA_ACK;
                                end else begin
                                    bit_cnt <= bit_cnt + 1;
                                end
                            end
                        endcase
                    end
                end

                DATA_ACK: begin
                    if (qtr_tick) begin
                        case (step)
                            2'd0: begin
                                scl_r <= 1'b0;
                                if (is_read) begin
                                    sda_r <= ack_in_r;
                                end else begin
                                    sda_r <= 1'b1;
                                end
                                step <= 2'd1;
                            end
                            2'd1: begin
                                scl_r <= 1'b1;
                                step  <= 2'd2;
                            end
                            2'd2: begin
                                scl_r <= 1'b1;
                                if (!is_read) begin
                                    ack_out <= sda_i_sync;
                                end
                                if (is_read) begin
                                    rx_data <= rx_shift_reg;
                                end
                                step <= 2'd3;
                            end
                            2'd3: begin
                                scl_r <= 1'b0;
                                done  <= 1'b1;
                                step  <= 2'd0;
                                state <= WAIT_CMD;
                            end
                        endcase
                    end
                end

                STOP: begin
                    if (qtr_tick) begin
                        case (step)
                            2'd0: begin
                                sda_r <= 1'b0;
                                scl_r <= 1'b0;
                                step  <= 2'd1;
                            end
                            2'd1: begin
                                scl_r <= 1'b1;
                                step  <= 2'd2;
                            end
                            2'd2: begin
                                sda_r <= 1'b1;
                                step  <= 2'd3;
                            end
                            2'd3: begin
                                step  <= 2'd0;
                                done  <= 1'b1;
                                state <= IDLE;
                            end
                        endcase
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
