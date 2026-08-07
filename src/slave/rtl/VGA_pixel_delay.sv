`timescale 1ns / 1ps

module VGA_pixel_delay (
    input logic clk,
    input logic reset,
    input logic p_tick,
    input logic de,
    input logic [9:0] x_pixel,
    input logic [9:0] y_pixel,
    output logic de_d,
    output logic [9:0] x_pixel_d,
    output logic [9:0] y_pixel_d
);

    always_ff @(posedge clk) begin
        if (reset) begin
            de_d <= 1'b0;
            x_pixel_d <= '0;
            y_pixel_d <= '0;
        end else if (p_tick) begin
            de_d <= de;
            x_pixel_d <= x_pixel;
            y_pixel_d <= y_pixel;
        end
    end

endmodule
