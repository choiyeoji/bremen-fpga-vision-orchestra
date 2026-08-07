`timescale 1ns / 1ps

module UnScaleImage (
    input logic       de,
    input logic [9:0] x_pixel,
    input logic [9:0] y_pixel,

    // cam side (1번 위치: Top-Middle)
    output logic [$clog2(106*120)-1:0] cam_raddr,
    input  logic [               11:0] cam_rdata1,

    // mem side (나머지 5개 위치)
    output logic [$clog2(106*120/4)-1:0] mem_raddr,
    input  logic [                 23:0] mem_rdata0,
    input  logic [                 23:0] mem_rdata2,
    input  logic [                 23:0] mem_rdata3,
    input  logic [                 23:0] mem_rdata4,
    input  logic [                 23:0] mem_rdata5,

    // VGA side
    // output logic cam_flag, //0: mem 1: cam
    // output logic [23:0] mem_rdata,
    // output logic [11:0] cam_rdata
    output logic [3:0] port_red,
    output logic [3:0] port_green,
    output logic [3:0] port_blue
);

    logic [23:0] mem_rdata_reg;
    logic        cam_flag;
    logic        border_flag;
    logic [3:0] Y_data;
    logic signed [4:0] Co_data, Cg_data;
    logic signed [6:0] red_calc, green_calc, blue_calc;
    logic [3:0] decoded_red, decoded_green, decoded_blue;

    // ==========================================
    // 🧮 1. 로컬 좌표계 (Local Coordinates) 계산
    // ==========================================
    // 화면 어느 영역에 있든, 해당 박스 안에서의 상대 좌표(0~105, 0~119)를 구합니다.
    logic [9:0] local_x;
    logic [9:0] local_y;

    logic [8:0] scale_x;
    logic [8:0] scale_y;

    // frameBuffer는 동기식 읽기이므로 다음 VGA 픽셀의 주소를 미리 넣는다.
    logic [9:0] next_x_pixel;
    logic [9:0] next_y_pixel;
    logic       next_de;
    logic [8:0] read_scale_x;
    logic [8:0] read_scale_y;
    logic [9:0] read_local_x;
    logic [9:0] read_local_y;

    assign scale_x = x_pixel >> 1;
    assign scale_y = y_pixel >> 1;

    always_comb begin
        if (x_pixel == 10'd799) begin
            next_x_pixel = 10'd0;
            if (y_pixel == 10'd524) next_y_pixel = 10'd0;
            else next_y_pixel = y_pixel + 1'b1;
        end else begin
            next_x_pixel = x_pixel + 1'b1;
            next_y_pixel = y_pixel;
        end
    end

    assign next_de      = (next_x_pixel < 640) && (next_y_pixel < 480);
    assign read_scale_x = next_x_pixel >> 1;
    assign read_scale_y = next_y_pixel >> 1;

    always_comb begin
        // 320×240 논리 화면 기준 로컬 Y
        if (scale_y >= 120) local_y = scale_y - 120;
        else local_y = scale_y;

        // 320×240 논리 화면 기준 로컬 X
        if (scale_x > 213) local_x = scale_x - 214;
        else if (scale_x > 106) local_x = scale_x - 107;
        else local_x = scale_x;
    end

    // 다음 화면 픽셀에 대응하는 메모리 내부 좌표
    always_comb begin
        if (read_scale_y >= 120) read_local_y = read_scale_y - 120;
        else read_local_y = read_scale_y;

        if (read_scale_x > 213) read_local_x = read_scale_x - 214;
        else if (read_scale_x > 106) read_local_x = read_scale_x - 107;
        else read_local_x = read_scale_x;
    end

    // ==========================================
    // 📍 2. 메모리/카메라 주소(Address) 할당
    // ==========================================
    // 6개의 화면이 모두 같은 크기이므로, 계산된 로컬 좌표를 기반으로 주소를 계산합니다.

    // --- 카메라 (320x240 다운스케일링 읽기) ---
    logic [9:0] mapped_cam_x;
    logic [9:0] mapped_cam_y;

    // 106x120 표시 영역과 106x120 카메라 메모리를 1:1로 매핑한다.
    assign mapped_cam_x = read_local_x;
    assign mapped_cam_y = read_local_y;

    // 106x120 메모리의 1D 주소 = (Y * 106) + X
    assign cam_raddr    = next_de ? ((mapped_cam_y * 106) + mapped_cam_x) : '0;

    // --- 메모리 (2x2 압축 읽기) ---
    // 가로세로 >> 1 하여 주소 계산, 가로폭 53
    assign mem_raddr    = next_de ? ((read_local_y >> 1) * 53
                                      + (read_local_x >> 1)) : '0;

    // ==========================================
    // 📺 3. 영역별 데이터 멀티플렉싱 (Mux)
    // ==========================================
    always_comb begin
        mem_rdata_reg = 24'd0;
        cam_flag      = 1'b0;
        border_flag   = 1'b0;

        if (de) begin
            if (scale_x == 106 || scale_x == 213) begin
                border_flag = 1'b1;
            end else if (scale_y < 120) begin
                if (scale_x < 106) mem_rdata_reg = mem_rdata0;
                else if (scale_x < 213) cam_flag = 1'b1;
                else mem_rdata_reg = mem_rdata2;
            end else begin
                if (scale_x < 106) mem_rdata_reg = mem_rdata3;
                else if (scale_x < 213) mem_rdata_reg = mem_rdata4;
                else mem_rdata_reg = mem_rdata5;
            end
        end
    end

    // ==========================================
    // 🎨 4. 데이터 추출 및 YCoCg 연산 (1:1 스케일)
    // ==========================================
    always_comb begin
        // SPI 수신 워드 배치: {Y3, Y2, Y1, Y0, Co, Cg}
        Cg_data = $signed({1'b0, mem_rdata_reg[3:0]}) - 5'sd8;
        Co_data = $signed({1'b0, mem_rdata_reg[7:4]}) - 5'sd8;

        case ({
            local_y[0], local_x[0]
        })
            2'b00: Y_data = mem_rdata_reg[11:8];   // Y0: 좌상단
            2'b01: Y_data = mem_rdata_reg[15:12];  // Y1: 우상단
            2'b10: Y_data = mem_rdata_reg[19:16];  // Y2: 좌하단
            2'b11: Y_data = mem_rdata_reg[23:20];  // Y3: 우하단
        endcase

        red_calc   = $signed({1'b0, Y_data}) - Cg_data + Co_data;
        green_calc = $signed({1'b0, Y_data}) + Cg_data;
        blue_calc  = $signed({1'b0, Y_data}) - Cg_data - Co_data;

        if (red_calc < 0) decoded_red = 4'd0;
        else if (red_calc > 15) decoded_red = 4'd15;
        else decoded_red = red_calc[3:0];

        if (green_calc < 0) decoded_green = 4'd0;
        else if (green_calc > 15) decoded_green = 4'd15;
        else decoded_green = green_calc[3:0];

        if (blue_calc < 0) decoded_blue = 4'd0;
        else if (blue_calc > 15) decoded_blue = 4'd15;
        else decoded_blue = blue_calc[3:0];
    end

    // ==========================================
    // 🖥️ 5. 최종 RGB 출력
    // ==========================================
    // border_flag가 1이거나 de가 0일 때는 모두 0(검은색)을 출력합니다.
    assign port_red   = (!de || border_flag) ? 4'd0 : (cam_flag) ? cam_rdata1[11:8] : decoded_red;
    assign port_green = (!de || border_flag) ? 4'd0 : (cam_flag) ? cam_rdata1[7:4]  : decoded_green;
    assign port_blue  = (!de || border_flag) ? 4'd0 : (cam_flag) ? cam_rdata1[3:0]  : decoded_blue;
endmodule
