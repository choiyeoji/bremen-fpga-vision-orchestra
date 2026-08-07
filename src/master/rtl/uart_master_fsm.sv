`timescale 1ns / 1ps


module uart_master_fsm (
    input logic clk,
    input logic rst,
    input logic i_start,
    input logic [11:0] note,
    input logic done,
    output logic [7:0] tx_data,
    output logic o_start
);

    typedef enum logic [1:0] {
        IDLE,
        WAIT_START,
        WAIT_PHASE1,
        WAIT_PHASE2
    } uart_fsm_e;

    uart_fsm_e c_state, n_state;
    logic [11:0] reg_note, next_note;
    logic [7:0] reg_tx_data, next_tx_data;
    logic reg_start, next_start;

    assign tx_data = reg_tx_data;
    assign o_start = reg_start;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            c_state     <= IDLE;
            reg_tx_data <= 0;
            reg_start   <= 0;
            reg_note    <= 0;
        end else begin
            c_state     <= n_state;
            reg_tx_data <= next_tx_data;
            reg_start   <= next_start;
            reg_note    <= next_note;
        end
    end

    always_comb begin
        n_state      = c_state;
        next_tx_data = reg_tx_data;
        next_start   = reg_start;
        next_note    = reg_note;
        case (c_state)
            IDLE: begin
                next_start   = 1'b0;
                next_tx_data = 0;
                if (i_start) begin
                    n_state      = WAIT_START;
                    next_start   = 1'b1;
                    next_tx_data = 8'hFF;
                    next_note    = note;
                end
            end
            WAIT_START: begin
                next_start = 1'b0;
                if (done) begin
                    n_state      = WAIT_PHASE1;
                    next_start   = 1'b1;
                    next_tx_data = {2'd0, reg_note[5:0]};
                end
            end
            WAIT_PHASE1: begin
                next_start = 1'b0;
                if (done) begin
                    n_state      = WAIT_PHASE2;
                    next_start   = 1'b1;
                    next_tx_data = {2'd0, reg_note[11:6]};
                end
            end
            WAIT_PHASE2: begin
                next_start = 1'b0;
                if (done) begin
                    n_state = IDLE;
                end
            end
        endcase
    end
endmodule