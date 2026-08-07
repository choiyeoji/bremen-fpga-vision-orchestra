`timescale 1ns / 1ps

module Cam_WriteController (
    input logic clk,
    input logic reset,

    input logic p_tick,
    input logic v_sync,
    input logic ds_valid,

    output logic        we,
    output logic [13:0] wAddr,
    output logic        done
);

    logic v_sync_q;

    always_ff @(posedge clk) begin
        if (reset) begin
            v_sync_q <= 1'b1;
        end else begin
            v_sync_q <= v_sync;
        end
    end

    assign done = v_sync_q & ~v_sync;
    assign we   = p_tick & ds_valid;

    always_ff @(posedge clk) begin
        if (reset) begin
            wAddr <= 14'd0;
        end else if (done) begin
            wAddr <= 14'd0;
        end else if (we) begin
            wAddr <= wAddr + 1;
        end
    end

endmodule
