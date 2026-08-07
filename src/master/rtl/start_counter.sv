`timescale 1ns / 1ps


module start_counter #(
    parameter COUNT = 500_000_000
) (
    input  logic clk,
    input  logic rst,
    output logic start_tick
);

    logic [$clog2(COUNT)-1:0] counter;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            start_tick <= 1'b0;
            counter    <= 0;
        end else begin
            if (counter == COUNT - 1) begin
                counter    <= 0;
                start_tick <= 1'b1;
            end else begin
                start_tick <= 1'b0;
                counter    <= counter + 1;
            end
        end
    end

endmodule