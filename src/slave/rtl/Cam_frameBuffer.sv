`timescale 1ns / 1ps

module Cam_frameBuffer (
    input logic clk,
    input logic reset,

    input logic        we,
    input logic [13:0] wAddr,
    input logic [11:0] wData,
    input logic        frame_done,

    input  logic [13:0] rAddr,
    output logic [11:0] rData,

    input  logic sending,
    input  logic sender_busy,
    input  logic tx_done,
    output logic frame_ready
);

    logic [11:0] mem0[0:12719];
    logic [11:0] mem1[0:12719];

    logic w_sel;
    logic [11:0] rd0, rd1;
    logic tx_busy;

    assign tx_busy = sending | sender_busy;

    always_ff @(posedge clk) begin
        if (we) begin
            if (w_sel) begin
                mem1[wAddr] <= wData;
            end else begin
                mem0[wAddr] <= wData;
            end
        end
    end

    always_ff @(posedge clk) begin
        rd0 <= mem0[rAddr];
        rd1 <= mem1[rAddr];
    end
    assign rData = w_sel ? rd0 : rd1;

    always_ff @(posedge clk) begin
        if (reset) begin
            w_sel       <= 1'b0;
            frame_ready <= 1'b0;
        end else begin
            if (frame_done && !tx_busy) begin
                w_sel       <= ~w_sel;
                frame_ready <= 1'b1;
            end else if (tx_done) begin
                frame_ready <= 1'b0;
            end
        end
    end

endmodule
