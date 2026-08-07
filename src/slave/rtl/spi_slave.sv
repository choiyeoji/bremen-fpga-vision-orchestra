`timescale 1ns / 1ps

module SPI_Slave (
    input logic clk,
    input logic reset,

    // spi
    input  logic sclk,
    input  logic mosi,
    input  logic cs_n,
    output logic miso,

    // frame_sender
    input  logic       push,
    input  logic [7:0] push_data,
    output logic       full,

    // frame handshake
    input  logic frame_ready,
    input  logic sender_busy,
    output logic send_start,
    output logic sending,
    output logic send_done,
    output logic send_abort
);

    logic [7:0] rx_data, tx_data, fifo_rdata;
    logic rx_done, tx_load;
    logic fifo_pop, fifo_trash, fifo_empty;

    // ★ 추가: cs_n 유휴 감시 → flush 펄스 -------------------------
    // 프레임 간 유휴(~9ms) 대비 충분히 짧고, 바이트 간 간격(<수십 ns) 대비 충분히 긴 값.
    localparam int IDLE_TIMEOUT = 10000;  // 100us @100MHz (튜닝 가능)
    logic [ 1:0] csn_sync;
    logic [13:0] idle_cnt;
    logic        flush;

    always_ff @(posedge clk) begin
        if (reset) csn_sync <= 2'b11;
        else csn_sync <= {csn_sync[0], cs_n};
    end
    wire cs_n_idle = csn_sync[1];  // 1 = 통신 안 함(inactive)

    always_ff @(posedge clk) begin
        if (reset) begin
            idle_cnt <= 14'd0;
            flush    <= 1'b0;
        end else begin
            flush <= 1'b0;
            if (!cs_n_idle) begin
                idle_cnt <= 14'd0;  // 전송 중이면 리셋
            end else if (idle_cnt != IDLE_TIMEOUT) begin
                idle_cnt <= idle_cnt + 1'b1;
                if (idle_cnt == IDLE_TIMEOUT - 1)
                    flush <= 1'b1;  // 1클럭 펄스 (한 번만)
            end
        end
    end

    assign send_abort = flush;

    spi_slave U_SPI_SLAVE (
        .clk    (clk),
        .reset  (reset),
        .tx_data(tx_data),
        .rx_data(rx_data),
        .rx_done(rx_done),
        .tx_load(tx_load),
        .sclk   (sclk),
        .mosi   (mosi),
        .miso   (miso),
        .cs_n   (cs_n)
    );

    Slave_Decoder U_SLAVE_DECODER (
        .clk        (clk),
        .reset      (reset),
        .rx_data    (rx_data),
        .rx_done    (rx_done),
        .tx_data    (tx_data),
        .tx_load    (tx_load),
        .flush      (flush),
        .frame_ready(frame_ready),
        .sender_busy(sender_busy),
        .send_start (send_start),
        .sending    (sending),
        .send_done  (send_done),
        .fifo_rdata (fifo_rdata),
        .fifo_empty (fifo_empty),
        .fifo_pop   (fifo_pop),
        .fifo_trash (fifo_trash)
    );

    tx_fifo U_TX_FIFO (
        .clk  (clk),
        .reset(reset),
        .trash(fifo_trash | flush),
        .push (push),
        .wdata(push_data),
        .pop  (fifo_pop),
        .rdata(fifo_rdata),
        .full (full),
        .empty(fifo_empty)
    );

endmodule

module spi_slave (
    input logic clk,
    input logic reset,
    input logic [7:0] tx_data,
    output logic [7:0] rx_data,
    output logic rx_done,
    output logic tx_load,
    input logic sclk,
    input logic mosi,
    output logic miso,
    input logic cs_n
);

    logic [2:0] sclk_sync;
    logic [2:0] cs_n_sync;
    logic [1:0] mosi_sync;

    always_ff @(posedge clk) begin
        if (reset) begin
            sclk_sync <= 3'b000;
            cs_n_sync <= 3'b111;
            mosi_sync <= 2'b11;
        end else begin
            sclk_sync <= {sclk_sync[1:0], sclk};
            cs_n_sync <= {cs_n_sync[1:0], cs_n};
            mosi_sync <= {mosi_sync[0], mosi};
        end
    end

    wire sclk_rise = (sclk_sync[2:1] == 2'b01);
    wire sclk_fall = (sclk_sync[2:1] == 2'b10);
    wire cs_n_fall = (cs_n_sync[2:1] == 2'b10);
    wire cs_active = ~cs_n_sync[1];
    wire mosi_in = mosi_sync[1];

    logic [7:0] tx_shift_reg, rx_shift_reg;
    logic [2:0] bit_cnt;
    logic       miso_r;

    assign miso = cs_active ? miso_r : 1'bz;

    always_ff @(posedge clk) begin
        if (reset) begin
            tx_shift_reg <= 8'd0;
            rx_shift_reg <= 8'd0;
            bit_cnt      <= 3'd0;
            rx_data      <= 8'd0;
            rx_done      <= 1'b0;
            tx_load      <= 1'b0;
            miso_r       <= 1'b1;
        end else begin
            rx_done <= 1'b0;
            tx_load <= 1'b0;

            if (cs_n_fall) begin
                bit_cnt      <= 3'd0;
                miso_r       <= tx_data[7];
                tx_shift_reg <= {tx_data[6:0], 1'b0};
                tx_load      <= 1'b1;
            end else if (cs_active) begin
                if (sclk_rise) begin
                    rx_shift_reg <= {rx_shift_reg[6:0], mosi_in};
                    if (bit_cnt == 3'd7) begin
                        rx_data <= {rx_shift_reg[6:0], mosi_in};
                        rx_done <= 1'b1;
                    end
                end
                if (sclk_fall) begin
                    if (bit_cnt != 3'd7) begin
                        bit_cnt      <= bit_cnt + 1;
                        miso_r       <= tx_shift_reg[7];
                        tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                    end
                end
                // if (sclk_fall) begin
                //     if (bit_cnt == 3'd7) begin
                //         bit_cnt      <= 3'd0;
                //         miso_r       <= tx_data[7];
                //         tx_shift_reg <= {tx_data[6:0], 1'b0};
                //         tx_load      <= 1'b1;
                //     end else begin
                //         bit_cnt      <= bit_cnt + 1;
                //         miso_r       <= tx_shift_reg[7];
                //         tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                //     end
                // end
            end
        end
    end

endmodule

module Slave_Decoder (
    input logic clk,
    input logic reset,
    input logic [7:0] rx_data,
    input logic rx_done,
    output logic [7:0] tx_data,
    input logic tx_load,
    input logic flush,
    input logic frame_ready,
    input logic sender_busy,
    output logic send_start,
    output logic sending,
    output logic send_done,
    input logic [7:0] fifo_rdata,
    input logic fifo_empty,
    output logic fifo_pop,
    output logic fifo_trash
);

    localparam IDLE = 2'd0;
    localparam ACK = 2'd1;
    localparam DATA = 2'd2;

    logic [ 1:0] state;
    logic [ 7:0] reject;
    logic [13:0] byte_cnt;

    assign sending = (state != IDLE);

    always_comb begin
        fifo_pop = 1'b0;
        case (state)
            IDLE: tx_data = reject;
            ACK: tx_data = 8'h18;
            DATA: begin
                tx_data  = fifo_empty ? 8'h00 : fifo_rdata;
                fifo_pop = tx_load && !fifo_empty;
            end
            default: tx_data = 8'h00;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state      <= IDLE;
            reject     <= 8'h00;
            byte_cnt   <= 14'd0;
            send_start <= 1'b0;
            send_done  <= 1'b0;
            fifo_trash <= 1'b0;
        end else if (flush) begin
            state      <= IDLE;
            reject     <= 8'h00;
            byte_cnt   <= 14'd0;
            send_start <= 1'b0;
            send_done  <= 1'b0;
            fifo_trash <= 1'b0;
        end else begin
            send_start <= 1'b0;
            send_done  <= 1'b0;
            fifo_trash <= 1'b0;
            case (state)
                IDLE: begin
                    if (tx_load) reject <= 8'h00;
                    if (rx_done && rx_data == 8'hA9) begin
                        if (frame_ready && !sender_busy) begin
                            state      <= ACK;
                            byte_cnt   <= 14'd0;
                            send_start <= 1'b1;
                            fifo_trash <= 1'b1;
                        end else begin
                            reject <= 8'h24;
                        end
                    end
                end

                ACK: begin
                    if (tx_load) state <= DATA;
                end

                DATA: begin
                    if (tx_load) begin
                        if (byte_cnt == 14'd9539) begin
                            send_done <= 1'b1;
                            state     <= IDLE;
                            reject    <= 8'h00;
                        end else begin
                            byte_cnt <= byte_cnt + 1;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

module tx_fifo (
    input  logic       clk,
    input  logic       reset,
    input  logic       trash,
    input  logic       push,
    input  logic [7:0] wdata,
    input  logic       pop,
    output logic [7:0] rdata,
    output logic       full,
    output logic       empty
);

    logic [7:0] mem[0:31];
    logic [5:0] wp, rp;

    assign full  = ((wp - rp) == 6'd32);
    assign empty = (wp == rp);

    always_ff @(posedge clk) begin
        if (reset || trash) begin
            wp <= 6'd0;
            rp <= 6'd0;
        end else begin
            if (push && !full) begin
                mem[wp[4:0]] <= wdata;
                wp <= wp + 1;
            end
            if (pop && !empty) begin
                rp <= rp + 1;
            end
        end
    end

    assign rdata = mem[rp[4:0]];

endmodule
