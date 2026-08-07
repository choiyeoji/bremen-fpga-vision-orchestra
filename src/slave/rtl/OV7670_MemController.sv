`timescale 1ns / 1ps

module OV7670_MemController (
    input  logic        pclk,
    input  logic        reset,
    // ov7670
    input  logic        href,
    input  logic        vsync,
    input  logic [ 7:0] pdata,
    // framebuffer
    output logic        we,
    output logic [16:0] wAddr,
    output logic [15:0] wData
);

    logic [15:0] pixelData;
    logic        pixelEvenOdd;

    assign wData = pixelData;

    always_ff @(posedge pclk, posedge reset) begin
        if (reset) begin
            wAddr        <= 0;
            pixelData    <= 0;
            pixelEvenOdd <= 1'b0;
            we           <= 1'b0;
        end else begin
            if (we) begin
                wAddr <= wAddr + 1;
            end
            if (href) begin
                if (pixelEvenOdd == 1'b0) begin
                    we              <= 1'b0;
                    pixelData[15:8] <= pdata;
                    pixelEvenOdd    <= ~pixelEvenOdd;
                end else begin
                    we             <= 1'b1;
                    pixelData[7:0] <= pdata;
                    pixelEvenOdd   <= ~pixelEvenOdd;
                end
            end else begin
                we           <= 1'b0;
                pixelData    <= 0;
                pixelEvenOdd <= 1'b0;
            end
            if (vsync) begin
                wAddr        <= 0;
                pixelData    <= 0;
                pixelEvenOdd <= 1'b0;
                we           <= 1'b0;
            end
        end
    end

endmodule
