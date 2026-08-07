`timescale 1ns / 1ps


module SCCB (
    input              clk,
    input              reset,
    //fsm side
    input  logic       start,
    input  logic       write,
    input  logic [7:0] fsm_addr,
    input  logic [7:0] fsm_wdata,
    output logic [7:0] fsm_rdata,
    output logic       ready,
    output logic       scl,
    inout  wire        sda
);

    logic [7:0] I2C_rx_data;
    logic       I2C_done;
    logic [7:0] I2C_tx_data;
    logic       I2C_cmd_start;
    logic       I2C_cmd_write;
    logic       I2C_cmd_read;
    logic       I2C_cmd_stop;

    I2C_FSM U_I2C_FSM (
        .clk          (clk),
        .reset        (reset),
        //fsm side
        .start        (start),
        .write        (write),
        .fsm_addr     (fsm_addr),
        .fsm_wdata    (fsm_wdata),
        .fsm_rdata    (fsm_rdata),
        .ready        (ready),
        //SCCB
        .I2C_rx_data  (I2C_rx_data),
        .I2C_done     (I2C_done),
        .I2C_tx_data  (I2C_tx_data),
        .I2C_cmd_start(I2C_cmd_start),
        .I2C_cmd_write(I2C_cmd_write),
        .I2C_cmd_read (I2C_cmd_read),
        .I2C_cmd_stop (I2C_cmd_stop)
    );

    I2C_Master U_I2C (
        .clk      (clk),
        .rst      (reset),
        // command port
        .cmd_start(I2C_cmd_start),
        .cmd_write(I2C_cmd_write),
        .cmd_read (I2C_cmd_read),
        .cmd_stop (I2C_cmd_stop),
        .tx_data  (I2C_tx_data),
        .ack_in   (0),
        // internal output
        .rx_data  (I2C_rx_data),
        .done     (I2C_done),
        .ack_out  (),
        .busy     (),
        // external port
        .scl      (scl),
        .sda      (sda)
    );

endmodule

module I2C_FSM (
    input  logic       clk,
    input  logic       reset,
    //fsm side
    input  logic       start,
    input  logic       write,
    input  logic [7:0] fsm_addr,
    input  logic [7:0] fsm_wdata,
    output logic [7:0] fsm_rdata,
    output logic       ready,
    //SCCB
    input  logic [7:0] I2C_rx_data,
    input  logic       I2C_done,
    output logic [7:0] I2C_tx_data,
    output logic       I2C_cmd_start,
    output logic       I2C_cmd_write,
    output logic       I2C_cmd_read,
    output logic       I2C_cmd_stop
);
    localparam OV7670_ADDR = 8'h42;

    typedef enum logic [2:0] {
        IDLE        = 3'b0,
        START,
        ID_PHASE1,
        ADDR_PHASE2,
        DATA_PHASE3,
        STOP,
        GOTO_IDLE
    } SCCB_state_e;

    SCCB_state_e state, next_state;
    logic write_reg;
    logic [7:0] fsm_wdata_reg, fsm_addr_reg;

    assign ready = (state != IDLE) ? 0 : 1;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            fsm_rdata <= 8'h00;
            write_reg <= 1'b0;
            fsm_addr_reg <= 0;
            fsm_wdata_reg <= 0;
        end else begin
            state <= next_state;

            if (state == STOP && !write_reg && I2C_done) begin
                fsm_rdata <= I2C_rx_data;
            end else if (state == IDLE && start) begin
                write_reg <= write;
                fsm_addr_reg <= fsm_addr;
                fsm_wdata_reg <= fsm_wdata;
            end else if (state == IDLE) begin
                fsm_rdata <= 8'h00;
                write_reg <= 1'b0;
                fsm_addr_reg <= 0;
                fsm_wdata_reg <= 0;
            end
        end
    end

    always_comb begin
        next_state    = state;
        I2C_cmd_start = 0;
        I2C_cmd_write = 0;
        I2C_cmd_read  = 0;
        I2C_cmd_stop  = 0;
        I2C_tx_data   = 0;
        case (state)
            IDLE: begin
                if (start) begin
                    next_state    = ID_PHASE1;
                    I2C_cmd_start = 1;
                end
            end
            ID_PHASE1: begin
                if (write_reg) I2C_tx_data = OV7670_ADDR;
                else I2C_tx_data = OV7670_ADDR + 1;
                if (I2C_done) begin
                    next_state    = ADDR_PHASE2;
                    I2C_cmd_write = 1;
                end
            end
            ADDR_PHASE2: begin
                I2C_tx_data = fsm_addr_reg;
                if (I2C_done) begin
                    next_state    = DATA_PHASE3;
                    I2C_cmd_write = 1;
                end
            end
            DATA_PHASE3: begin
                if (write_reg) begin
                    I2C_tx_data = fsm_wdata_reg;
                    if (I2C_done) begin
                        I2C_cmd_write = 1'b1;
                        next_state    = STOP;
                    end
                end else begin
                    if (I2C_done) begin
                        I2C_cmd_read = 1'b1;
                        next_state   = STOP;
                    end
                end
            end
            STOP: begin
                if (I2C_done) begin
                    I2C_cmd_stop = 1;
                    next_state   = GOTO_IDLE;
                end
            end
            GOTO_IDLE: begin
                if (I2C_done) next_state = IDLE;
            end
        endcase
    end

endmodule





module I2C_Master (
    input              clk,
    input              rst,
    // command port
    input              cmd_start,
    input              cmd_write,
    input              cmd_read,
    input              cmd_stop,
    input        [7:0] tx_data,
    input              ack_in,
    // internal output
    output logic [7:0] rx_data,
    output logic       done,
    output logic       ack_out,
    output logic       busy,
    // external port
    output logic       scl,
    inout  wire        sda
);
    logic sda_o, sda_i;

    assign sda   = (sda_o) ? 1'bz : 1'b0;
    assign sda_i = sda;


    i2c_master U_I2C_MASTER_CORE (
        .*,
        .sda_o(sda_o),
        .sda_i(sda_i)
    );

endmodule

module i2c_master (
    input              clk,
    input              rst,
    // command port
    input              cmd_start,
    input              cmd_write,
    input              cmd_read,
    input              cmd_stop,
    input        [7:0] tx_data,
    input              ack_in,
    // internal output
    output logic [7:0] rx_data,
    output logic       done,
    output logic       ack_out,
    output logic       busy,
    // external port
    output logic       scl,
    output logic       sda_o,
    input  logic       sda_i
);

    typedef enum logic [2:0] {
        IDLE     = 3'b0,
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

    assign scl   = scl_r;
    assign sda_o = sda_r;
    assign busy  = (state != IDLE);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            div_cnt  <= 0;
            qtr_tick <= 1'b0;
        end else begin
            if (div_cnt == 250 - 1) begin  //SCL : 100Khz
                div_cnt  <= 0;
                qtr_tick <= 1'b1;
            end else begin
                div_cnt  <= div_cnt + 1;
                qtr_tick <= 1'b0;
            end
        end
    end


    always_ff @(posedge clk or posedge rst) begin : i2c_master_ff
        if (rst) begin
            state        <= IDLE;
            scl_r        <= 1'b1;
            sda_r        <= 1'b1;
            step         <= 1'b0;
            done         <= 1'b0;
            tx_shift_reg <= 0;
            rx_shift_reg <= 0;
            is_read      <= 1'b0;
            bit_cnt      <= 0;
            ack_in_r     <= 1'b1;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    scl_r <= 1'b1;
                    sda_r <= 1'b1;
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
                        bit_cnt      <= 0;
                        is_read      <= 1'b0;
                        state        <= DATA;
                        sda_r        <= tx_data[7];
                    end else if (cmd_read) begin
                        rx_shift_reg <= 0;
                        bit_cnt      <= 0;
                        is_read      <= 1'b1;
                        ack_in_r     <= ack_in;
                        state        <= DATA;
                        sda_r        <= 1'b1;
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
                                scl_r <= 1'b1;
                                step  <= 2'd1;
                            end
                            2'd1: begin
                                scl_r <= 1'b1;
                                if (is_read) begin
                                    rx_shift_reg <= {rx_shift_reg[6:0], sda_i};
                                end
                                step <= 2'd2;
                            end
                            2'd2: begin
                                scl_r <= 1'b0;
                                if (!is_read) begin
                                    tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                                end
                                step <= 2'd3;
                            end
                            2'd3: begin
                                scl_r <= 1'b0;
                                step  <= 2'd0;
                                if (bit_cnt < 7) begin
                                    sda_r = (is_read) ? 1'b1 : tx_shift_reg[7];
                                    bit_cnt <= bit_cnt + 1;
                                end else if (bit_cnt == 7) begin
                                    state <= DATA_ACK;
                                    if (is_read) begin
                                        sda_r <= ack_in_r;
                                    end else begin
                                        sda_r <= 1'b1;  //sda input 설정
                                    end
                                end
                            end
                        endcase
                    end
                end
                DATA_ACK: begin
                    if (qtr_tick) begin
                        case (step)
                            2'd0: begin
                                scl_r <= 1'b1;
                                step  <= 2'd1;
                            end
                            2'd1: begin
                                scl_r <= 1'b1;
                                if (!is_read) begin  //ack 수신
                                    ack_out <= sda_i;
                                end else begin
                                    rx_data <= rx_shift_reg;
                                end
                                step <= 2'd2;
                            end
                            2'd2: begin
                                scl_r <= 1'b0;
                                step  <= 2'd3;
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
