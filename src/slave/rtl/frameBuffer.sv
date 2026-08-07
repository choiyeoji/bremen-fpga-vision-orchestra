`timescale 1ns / 1ps

module frameBuffer (
    input  logic        wclk,
    input  logic        we,
    input  logic [16:0] wAddr,
    input  logic [15:0] wData,
    input  logic        rclk,
    input  logic        ren,
    input  logic [16:0] rAddr,
    output logic [15:0] rData
);

    logic [15:0] mem[0:76799];

    always_ff @(posedge wclk) begin
        if (we) begin
            mem[wAddr] <= wData;
        end
    end

    always_ff @(posedge rclk) begin
        if (ren) begin
            rData <= mem[rAddr];
        end
    end

endmodule
