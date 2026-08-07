// `timescale 1ns / 1ps

// module OV7670_Music_Scale_Detect (
//     input  logic        clk,
//     input  logic        reset,
//     input  logic        p_tick,
//     input  logic        vsync,
//     input  logic [15:0] imgPxlData,
//     input  logic [ 9:0] x_pixel,
//     input  logic [ 9:0] y_pixel,
//     output logic [ 1:0] data_lat
// );

//     localparam CHADO   = 4'd3;
//     localparam RED_MIN = 4'd8;
//     localparam PIX_MIN = 8'd30;

//     logic [3:0] red, green, blue, max_val, min_val;
//     logic [4:0] g_plus, b_plus;
//     logic       red_detect;
//     logic       vsync_edge;
//     logic [7:0] cnt_do, cnt_re, cnt_mi;   // [수정] 구역별 독립 카운터

//     assign red = imgPxlData[15:12];
//     assign green = imgPxlData[10:7];
//     assign blue = imgPxlData[4:1];
//     assign g_plus = {1'b0, green} + 5'd2;
//     assign b_plus = {1'b0, blue} + 5'd2;
//     assign max_val = (red > green) ? ((red > blue) ? red : blue) : ((green > blue) ? green : blue);
//     assign min_val = (red < green) ? ((red < blue) ? red : blue) : ((green < blue) ? green : blue);

//     assign red_detect = (red >= RED_MIN)
//                      && ({1'b0, red} > g_plus)
//                      && ({1'b0, red} > b_plus)
//                      && ((max_val - min_val) > CHADO);

//     always_ff @(posedge clk) begin
//         if (reset) begin
//             vsync_edge <= 1'b0;
//             data_lat   <= 2'b00;
//             cnt_do     <= 8'd0;
//             cnt_re     <= 8'd0;
//             cnt_mi     <= 8'd0;
//         end else if (p_tick) begin
//             vsync_edge <= vsync;

//             if (!vsync && vsync_edge) begin
//                 // [수정] 각 구역이 "스스로" 문턱을 넘겼는지 개별 판정.
//                 // 여러 구역이 동시에 넘으면 카운트가 더 많은 쪽을 채택.
//                 if (cnt_do >= PIX_MIN && cnt_do >= cnt_re && cnt_do >= cnt_mi)
//                     data_lat <= 2'b01;
//                 else if (cnt_re >= PIX_MIN && cnt_re >= cnt_mi)
//                     data_lat <= 2'b10;
//                 else if (cnt_mi >= PIX_MIN)
//                     data_lat <= 2'b11;
//                 else
//                     data_lat <= 2'b00;

//                 cnt_do <= 8'd0;
//                 cnt_re <= 8'd0;
//                 cnt_mi <= 8'd0;
//             end else if (red_detect && y_pixel >= 80) begin
//                 // [수정] y_pixel < 80 (음과 무관한 영역)은 아예 카운트하지 않음
//                 if (x_pixel > 1 && x_pixel < 36) begin
//                     if (cnt_do != 8'hFF) cnt_do <= cnt_do + 1;
//                 end else if (x_pixel > 36 && x_pixel < 72) begin
//                     if (cnt_re != 8'hFF) cnt_re <= cnt_re + 1;
//                 end else if (x_pixel > 72) begin
//                     if (cnt_mi != 8'hFF) cnt_mi <= cnt_mi + 1;
//                 end
//             end
//         end
//     end

// endmodule

`timescale 1ns / 1ps

module OV7670_Music_Scale_Detect (
    input  logic        clk,
    input  logic        reset,
    input  logic        p_tick,
    input  logic        vsync,
    input  logic [15:0] imgPxlData,
    input  logic [ 9:0] x_pixel,
    input  logic [ 9:0] y_pixel,
    output logic [ 1:0] data_lat
);
    localparam CHADO = 4'h2;

    logic vsync_edge;
    logic red_detect;
    logic [1:0] data;
    logic [3:0] red, green, blue;
    logic [3:0] max_val, min_val;

    assign red_detect = (red > green + 4'h2) && (red > blue + 4'h2) && ((max_val - min_val) > CHADO);
    assign red = imgPxlData[15:12];
    assign green = imgPxlData[10:7];
    assign blue = imgPxlData[4:1];
    assign max_val = (red > green) ? ((red > blue) ? red : blue) : ((green > blue) ? green : blue);
    assign min_val = (red < green) ? ((red < blue) ? red : blue) : ((green < blue) ? green : blue);

    always_ff @(posedge clk) begin
        if (reset) begin
            vsync_edge <= 1'b0;
            data_lat   <= 2'b00;
            data       <= 2'b00;
        end else if (p_tick) begin
            vsync_edge <= vsync;
            if (!vsync && vsync_edge) begin
                data_lat <= data;
                data     <= 2'b00;
            end else if (red_detect) begin
                if (y_pixel < 80) data <= 2'b00;
                else if (x_pixel > 1 && x_pixel < 36) data <= 2'b01;
                else if (x_pixel > 36 && x_pixel < 72) data <= 2'b10;
                else if (x_pixel > 72) data <= 2'b11;
            end
        end
    end

endmodule
