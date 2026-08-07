`timescale 1ns / 1ps

module OV7670_SCCB_Controller (
    input  wire clk,
    input  wire reset,
    input  wire ack_in,
    output wire ack_out,
    output wire busy,
    output wire scl,
    inout  wire sda
);

    logic [15:0] mem_start   [ 0:1];
    logic [15:0] mem_config  [0:41];
    logic [15:0] mem_res     [0:13];
    logic [15:0] mem_color_ex[ 0:3];

    initial begin
        $readmemh("rom_start.mem", mem_start);
    end
    initial begin
        $readmemh("rom_config.mem", mem_config);
    end
    initial begin
        $readmemh("rom_res.mem", mem_res);
    end
    initial begin
        $readmemh("rom_color_ex.mem", mem_color_ex);
    end

    wire sda_o, sda_i;
    logic cmd_start, cmd_write, cmd_read, cmd_stop;
    logic [7:0] rx_data, tx_data;
    logic done;
    logic start;

    assign sda_i = sda;
    assign sda   = sda_o ? 1'bz : 1'b0;

    i2c_master u_i2c_master (
        .clk(clk),
        .reset(reset),
        .cmd_start(cmd_start),
        .cmd_write(cmd_write),
        .cmd_read(cmd_read),
        .cmd_stop(cmd_stop),
        .tx_data(tx_data),
        .ack_in(ack_in),
        .rx_data(rx_data),
        .done(done),
        .ack_out(ack_out),
        .busy(busy),
        .scl(scl),
        .sda_o(sda_o),
        .sda_i(sda_i)
    );

    typedef enum logic [2:0] {
        IDLE       = 3'b000,
        START      = 3'b001,
        CON_SEND   = 3'b010,
        CON_WAIT   = 3'b011,
        RES_SEND   = 3'b100,
        RES_WAIT   = 3'b101,
        COLOR_SEND = 3'b110,
        COLOR_WAIT = 3'b111
    } state_t;
    state_t state_o;

    typedef enum logic [2:0] {
        I_IDLE = 3'b000,
        I_START = 3'b001,
        I_ADDR_OV = 3'b010,
        I_ADDR_ROM = 3'b011,
        I_DATA = 3'b100,
        I_STOP = 3'b101,
        I_STOP_WAIT = 3'b110
    } state_s;
    state_s state_i;

    logic [15:0] send_value;
    logic send_start;
    logic send_done;

    // simulation delay
    // localparam delay_1  = 100;
    // localparam delay_10 = 300;
    // localparam delay_30 = 900;
    localparam delay_1 = 100_000;
    localparam delay_10 = 1_000_000;
    localparam delay_30 = 3_000_000;
    logic [ $clog2(delay_1)-1:0] count_1;
    logic [$clog2(delay_10)-1:0] count_10;
    logic [$clog2(delay_30)-1:0] count_30;
    logic tick_1, tick_10, tick_30;
    logic start_1, start_10, start_30;
    logic [5:0] idx;

    logic counting_1, counting_10, counting_30;

    logic start_tri;

    always_ff @(posedge clk) begin
        if (reset) begin
            start     <= 1'b0;
            start_tri <= 1'b0;
        end else begin
            start <= 1'b0;
            if (!start_tri) begin
                start     <= 1'b1;
                start_tri <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            count_1    <= '0;
            tick_1     <= 1'b0;
            counting_1 <= 1'b0;
        end else begin
            tick_1 <= 1'b0;
            if (start_1) begin
                counting_1 <= 1'b1;
                count_1    <= '0;
            end else if (counting_1) begin
                if (count_1 == delay_1) begin
                    tick_1     <= 1'b1;
                    counting_1 <= 1'b0;
                end else begin
                    count_1 <= count_1 + 1;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            count_10    <= '0;
            tick_10     <= 1'b0;
            counting_10 <= 1'b0;
        end else begin
            tick_10 <= 1'b0;
            if (start_10) begin
                counting_10 <= 1'b1;
                count_10    <= '0;
            end else if (counting_10) begin
                if (count_10 == delay_10) begin
                    tick_10     <= 1'b1;
                    counting_10 <= 1'b0;
                end else begin
                    count_10 <= count_10 + 1;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            count_30    <= '0;
            tick_30     <= 1'b0;
            counting_30 <= 1'b0;
        end else begin
            tick_30 <= 1'b0;
            if (start_30) begin
                counting_30 <= 1'b1;
                count_30    <= '0;
            end else if (counting_30) begin
                if (count_30 == delay_30) begin
                    tick_30     <= 1'b1;
                    counting_30 <= 1'b0;
                end else begin
                    count_30 <= count_30 + 1;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            idx <= 1'b0;
            send_start <= 1'b0;
            start_1 <= 1'b0;
            start_10 <= 1'b0;
            start_30 <= 1'b0;
        end else begin
            send_start <= 1'b0;
            start_1 <= 1'b0;
            start_10 <= 1'b0;
            start_30 <= 1'b0;
            case (state_o)
                IDLE: begin
                    if (start) begin
                        send_value <= mem_start[0];
                        send_start <= 1'b1;
                        state_o <= START;
                    end
                end
                START: begin
                    if (send_done) begin
                        start_30 <= 1'b1;
                    end
                    if (tick_30) begin
                        state_o <= CON_SEND;
                    end
                end
                CON_SEND: begin
                    send_value <= mem_config[idx];
                    send_start <= 1'b1;
                    state_o <= CON_WAIT;
                end
                CON_WAIT: begin
                    if (send_done) begin
                        if (idx == 41) begin
                            start_10 <= 1'b1;
                        end else begin
                            start_1 <= 1'b1;
                        end
                    end
                    if (tick_1) begin
                        idx <= idx + 1'b1;
                        state_o <= CON_SEND;
                    end
                    if (tick_10) begin
                        idx <= '0;
                        state_o <= RES_SEND;
                    end
                end
                RES_SEND: begin
                    send_value <= mem_res[idx];
                    send_start <= 1'b1;
                    state_o <= RES_WAIT;
                end
                RES_WAIT: begin
                    if (send_done) begin
                        if (idx == 13) begin
                            start_10 <= 1'b1;
                        end else begin
                            start_1 <= 1'b1;
                        end
                    end
                    if (tick_1) begin
                        idx <= idx + 1'b1;
                        state_o <= RES_SEND;
                    end
                    if (tick_10) begin
                        idx <= '0;
                        state_o <= COLOR_SEND;
                    end
                end
                COLOR_SEND: begin
                    send_value <= mem_color_ex[idx];
                    send_start <= 1'b1;
                    state_o <= COLOR_WAIT;
                end
                COLOR_WAIT: begin
                    if (send_done) begin
                        if (idx == 3) begin
                            state_o <= IDLE;
                        end else begin
                            idx <= idx + 1;
                            state_o <= COLOR_SEND;
                        end
                    end
                end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state_i   <= I_IDLE;
            cmd_start <= 1'b0;
            cmd_write <= 1'b0;
            cmd_read  <= 1'b0;
            cmd_stop  <= 1'b0;
            send_done <= 1'b0;
            tx_data   <= '0;
        end else begin
            cmd_start <= 1'b0;
            cmd_write <= 1'b0;
            cmd_stop  <= 1'b0;
            send_done <= 1'b0;
            case (state_i)
                I_IDLE: begin
                    if (send_start) begin
                        state_i <= I_START;
                    end
                end
                I_START: begin
                    cmd_start <= 1'b1;
                    state_i   <= I_ADDR_OV;
                end
                I_ADDR_OV: begin
                    if (done) begin
                        cmd_write <= 1'b1;
                        tx_data   <= 8'h42;
                        state_i   <= I_ADDR_ROM;
                    end
                end
                I_ADDR_ROM: begin
                    if (done) begin
                        cmd_write <= 1'b1;
                        tx_data   <= send_value[15:8];
                        state_i   <= I_DATA;
                    end
                end
                I_DATA: begin
                    if (done) begin
                        cmd_write <= 1'b1;
                        tx_data   <= send_value[7:0];
                        state_i   <= I_STOP;
                    end
                end
                I_STOP: begin
                    if (done) begin
                        cmd_stop <= 1'b1;
                        state_i  <= I_STOP_WAIT;
                    end
                end
                I_STOP_WAIT: begin
                    if (done) begin
                        send_done <= 1'b1;
                        state_i   <= I_IDLE;
                    end
                end
            endcase
        end
    end

endmodule

module i2c_master (
    input wire clk,
    input wire reset,
    // command port
    input wire cmd_start,
    input wire cmd_write,
    input wire cmd_read,
    input wire cmd_stop,
    input wire [7:0] tx_data,
    input wire ack_in,
    // internal output
    output reg [7:0] rx_data,
    output reg done,
    output reg ack_out,
    output wire busy,
    // external i2c port
    output wire scl,
    output wire sda_o,
    input wire sda_i
);

    localparam [2:0] IDLE = 3'b000;
    localparam [2:0] START = 3'b001;
    localparam [2:0] WAIT_CMD = 3'b010;
    localparam [2:0] DATA = 3'b011;
    localparam [2:0] DATA_ACK = 3'b100;
    localparam [2:0] STOP = 3'b101;

    reg [2:0] state;
    reg [7:0] div_cnt;
    reg qtr_tick;
    reg scl_r, sda_r;
    reg [1:0] step;
    reg [7:0] tx_shift_reg, rx_shift_reg;
    reg [2:0] bit_cnt;
    reg is_read, ack_in_r;

    assign scl   = scl_r;
    assign sda_o = sda_r;
    assign busy  = (state != IDLE) && (state != WAIT_CMD);

    always @(posedge clk) begin
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

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            scl_r <= 1'b1;
            sda_r <= 1'b1;
            step <= 0;
            done <= 1'b0;
            tx_shift_reg <= 0;
            rx_shift_reg <= 0;
            is_read <= 1'b0;
            bit_cnt <= 0;
            ack_in_r <= 1'b1;
            ack_out <= 1'b1;
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
                                scl_r <= 1'b1;
                                sda_r <= 1'b1;
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
                                    rx_shift_reg <= {rx_shift_reg[6:0], sda_i};
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
                                    sda_r <= 1'b1;  // sda input setting
                                end
                                step <= 2'd1;
                            end
                            2'd1: begin
                                scl_r <= 1'b1;
                                step  <= 2'd2;
                            end
                            2'd2: begin
                                scl_r <= 1'b1;
                                if (!is_read) begin  // ack susin
                                    ack_out <= sda_i;
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
                                scl_r <= 1'b0;
                                sda_r <= 1'b0;
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

