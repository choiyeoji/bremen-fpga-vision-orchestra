// `timescale 1ns / 1ps

// module OV7670_Music_Scale_Detect (
//     input  logic                       rclk,
//     input  logic                       reset,
//     input  logic                       we,          // [추가] 유효 픽셀일 때만 검사
//     input  logic                       vsync,
//     input  logic [15:0]                imgPxlData,
//     input  logic [$clog2(106*120)-1:0] wAddr,
//     output logic [1:0]                 data_lat
// );
//     localparam CHADO   = 4'd3;
//     localparam RED_MIN = 4'd8;   // 절대 밝기 하한: 이보다 어두운 red는 무시
//     localparam PIX_MIN = 8'd30;  // 프레임당 최소 검출 픽셀 수

//     logic [3:0] red, green, blue, max_val, min_val;
//     logic [4:0] g_plus, b_plus;          // [수정] 5비트로 확장해 랩어라운드 차단
//     logic       red_detect;
//     logic       vsync_edge;
//     logic [7:0] cnt;
//     logic [1:0] data;

//     assign red    = imgPxlData[15:12];
//     assign green  = imgPxlData[10:7];
//     assign blue   = imgPxlData[4:1];
//     assign g_plus = {1'b0, green} + 5'd2;
//     assign b_plus = {1'b0, blue}  + 5'd2;
//     assign max_val = (red > green) ? ((red > blue) ? red : blue) : ((green > blue) ? green : blue);
//     assign min_val = (red < green) ? ((red < blue) ? red : blue) : ((green < blue) ? green : blue);

//     assign red_detect = (red >= RED_MIN)
//                      && ({1'b0, red} > g_plus)
//                      && ({1'b0, red} > b_plus)
//                      && ((max_val - min_val) > CHADO);

//     always_ff @(posedge rclk) begin
//         if (reset) begin
//             vsync_edge <= 1'b0;
//             data_lat   <= 2'b00;
//             data       <= 2'b00;
//             cnt        <= 8'd0;
//         end else begin
//             vsync_edge <= vsync;
//             if (!vsync && vsync_edge) begin
//                 data_lat <= (cnt >= PIX_MIN) ? data : 2'b00;  // 문턱 미달이면 무시
//                 data     <= 2'b00;
//                 cnt      <= 8'd0;
//             end else if (we && red_detect && (wAddr >= 106 * 80)) begin
//                 data <= 2'b11;
//                 if (cnt != 8'hFF) cnt <= cnt + 1;
//             end
//         end
//     end
// endmodule

`timescale 1ns / 1ps

module OV7670_Music_Scale_Detect (
    input  logic                       rclk,
    input  logic                       reset,
    input  logic                       we,
    input  logic                       vsync,
    input  logic [               15:0] imgPxlData,
    input  logic [$clog2(106*120)-1:0] wAddr,
    output logic [                1:0] data_lat
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

    always_ff @(posedge rclk) begin
        if (reset) begin
            vsync_edge <= 1'b0;
            data_lat   <= 2'b00;
            data       <= 2'b00;
        end else begin
            vsync_edge <= vsync;
            if (!vsync && vsync_edge) begin
                data_lat <= data;
                data     <= 2'b00;
            end else if (we && red_detect) begin
                if (wAddr < 106 * 80) data <= 2'b00;
                else data <= 2'b11;
            end
        end
    end

endmodule


