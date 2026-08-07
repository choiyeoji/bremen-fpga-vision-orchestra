`timescale 1ns / 1ps

module OV7670_MemController (
    input  logic                       pclk,
    input  logic                       reset,
    // ov767 side
    input  logic                       href,
    input  logic                       vsync,
    input  logic [                7:0] pdata,
    // framebuffer side 
    output logic                       we,
    output logic [$clog2(320*240)-1:0] wAddr,
    output logic [               15:0] wData
);

    logic [15:0] pixelData;
    logic        pixelEvenOdd;

    assign wData = pixelData;

    always_ff @(posedge pclk or posedge reset) begin
        if (reset) begin
            we           <= 1'b0;
            pixelData    <= 0;
            wAddr        <= 0;
            pixelEvenOdd <= 1'b0;
        end else begin
            if (href) begin
                if (pixelEvenOdd == 1'b0) begin
                    we              <= 1'b0;
                    pixelData[15:8] <= pdata;
                    pixelEvenOdd    <= ~pixelEvenOdd;
                end else begin
                    we             <= 1'b1;
                    pixelData[7:0] <= pdata;
                    wAddr          <= wAddr + 1;
                    pixelEvenOdd   <= ~pixelEvenOdd;
                end
            end else begin
                we           <= 1'b0;
                pixelData    <= 0;
                pixelEvenOdd <= 1'b0;
            end
            if (vsync) begin
                we           <= 1'b0;
                pixelData    <= 0;
                wAddr        <= 0;
                pixelEvenOdd <= 1'b0;
            end
        end
    end

endmodule