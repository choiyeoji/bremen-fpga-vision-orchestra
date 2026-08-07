`timescale 1ns / 1ps


module DownScaleimage(
    input logic de,
    input logic [9:0] x_pixel,
    input logic [9:0] y_pixel,
    output logic [$clog2(160*120)-1:0] addr,
    input logic [15:0] imgPxlData,
    output logic [3:0] port_red,
    output logic [3:0] port_green,
    output logic [3:0] port_blue
);

    logic [9:0] rom_x;
    logic [9:0] rom_y;
    logic valid_area;

    assign valid_area = (x_pixel < 106) && (y_pixel <120);

    assign rom_x = x_pixel + (x_pixel >> 1);
    assign rom_y = y_pixel;

    assign addr = (de && valid_area) ? (160 * rom_y + rom_x) : 'bz;

    assign {port_red, port_green, port_blue} = (de && valid_area) ? {imgPxlData[15:12], imgPxlData[10:7], imgPxlData[4:1]} : 0;


endmodule


module DownScaleimg(
    input logic we,
    input logic [$clog2(160*120)-1:0] addr,
    input logic [               15:0] wData,
    output logic o_we,
    output logic [$clog2(160*120)-1:0] o_addr,
    output logic [               15:0] o_wData
);
endmodule


// OV7670 QVGA(320x240) 스트림을 106x120으로 축소해서 저장한다.
// 나눗셈 대신 위상 누산기를 사용하여 전체 입력 영역에서 픽셀을 고르게 선택한다.
module CameraDownScale106x120 (
    input  logic                         pclk,
    input  logic                         reset,
    input  logic                         vsync,
    input  logic                         i_we,
    input  logic [                 15:0] i_wData,
    output logic                         o_we,
    output logic [$clog2(106*120)-1:0] o_wAddr,
    output logic [                 15:0] o_wData
);
    localparam int SRC_W = 320;
    localparam int SRC_H = 240;
    localparam int DST_W = 106;
    localparam int DST_H = 120;
    localparam int DST_SIZE = DST_W * DST_H;

    logic [8:0] src_x;
    logic [8:0] x_phase;
    logic [8:0] y_phase;
    logic       take_line;
    logic [9:0] x_sum;
    logic [9:0] y_sum;
    logic [$clog2(DST_SIZE)-1:0] dst_count;

    assign x_sum = x_phase + DST_W;
    assign y_sum = y_phase + DST_H;

    always_ff @(posedge pclk or posedge reset) begin
        if (reset) begin
            src_x      <= 9'd0;
            x_phase    <= SRC_W - 1;
            // 첫 번째 입력 라인은 선택된 상태이며, 선택 후 잔여 위상은 119이다.
            y_phase    <= DST_H - 1;
            take_line  <= 1'b1;
            o_we       <= 1'b0;
            o_wAddr    <= '0;
            o_wData    <= '0;
            dst_count  <= '0;
        end else if (vsync) begin
            src_x      <= 9'd0;
            x_phase    <= SRC_W - 1;
            y_phase    <= DST_H - 1;
            take_line  <= 1'b1;
            o_we       <= 1'b0;
            o_wAddr    <= '0;
            o_wData    <= '0;
            dst_count  <= '0;
        end else begin
            o_we <= 1'b0;

            if (i_we) begin
                if (take_line && (x_sum >= SRC_W)) begin
                    o_we    <= 1'b1;
                    o_wAddr <= dst_count;
                    o_wData <= i_wData;
                    if (dst_count < DST_SIZE - 1)
                        dst_count <= dst_count + 1'b1;
                end

                if (x_sum >= SRC_W) x_phase <= x_sum - SRC_W;
                else x_phase <= x_sum;

                if (src_x == SRC_W - 1) begin
                    src_x   <= 9'd0;
                    x_phase <= SRC_W - 1;

                    if (y_sum >= SRC_H) begin
                        y_phase   <= y_sum - SRC_H;
                        take_line <= 1'b1;
                    end else begin
                        y_phase   <= y_sum;
                        take_line <= 1'b0;
                    end
                end else begin
                    src_x <= src_x + 1'b1;
                end
            end
        end
    end
endmodule
