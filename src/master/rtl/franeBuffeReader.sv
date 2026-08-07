`timescale 1ns / 1ps

module frameBufferReader (
    // VGA Decoder side
    input  logic               de,
    input  logic [9:0]         x_pixel,
    input  logic [9:0]         y_pixel,
    // MEM side
    output logic [2:0]         mem_sel,
    output logic               LB_rline,
    output logic [14:0]        addr,        // 넉넉하게 15비트로 할당
    input  logic [11:0]        imgPxlData,  // RGB444 (12비트)
    // VGA PORT side
    output logic [3:0]         port_red,
    output logic [3:0]         port_green,
    output logic [3:0]         port_blue
);
    // --- 파라미터 정의 (가상 320x240 좌표계 기준) ---
    localparam IMG0_START_X = 0,   IMG0_END_X = 105;
    localparam IMG1_START_X = 107, IMG1_END_X = 212; // 내부 마스터 이미지
    localparam IMG2_START_X = 214, IMG2_END_X = 319;
    
    // --- 해상도 2배 확대 (Upscale) 가상 좌표 ---
    logic [8:0] Upscale_x; 
    logic [8:0] Upscale_y;

    assign Upscale_x = x_pixel[9:1]; // x_pixel / 2 와 동일
    assign Upscale_y = y_pixel[9:1]; // y_pixel / 2 와 동일

    // 핑퐁 라인 버퍼 스위칭 (VGA의 Y라인이 바뀔 때마다 0, 1 토글)
    assign LB_rline = y_pixel[0];

    // --- MUX 및 주소 계산 로직 ---
    logic [6:0] local_x; // 각 버퍼 내의 로컬 X 좌표 (0 ~ 105)
    logic [6:0] local_y; // 각 버퍼 내의 로컬 Y 좌표 (0 ~ 119)
    logic       is_gap;  // 베젤 (Gap) 여부

    always_comb begin
        // 래치(Latch) 방지를 위한 기본값 초기화
        mem_sel = 3'd0;
        local_x = 7'd0;
        local_y = 7'd0;
        is_gap  = 1'b0;

        // 주의: 물리적 y_pixel이 아닌, 가상 좌표 Upscale_y로 비교해야 함!
        if (Upscale_y < 120) begin
            local_y = Upscale_y; // 상단 영역
            
            if (Upscale_x <= IMG0_END_X) begin
                mem_sel = 3'd0;
                local_x = Upscale_x - IMG0_START_X;
            end else if (Upscale_x == 106) begin
                is_gap = 1'b1;
            end else if (Upscale_x <= IMG1_END_X) begin
                mem_sel = 3'd1;
                local_x = Upscale_x - IMG1_START_X;
            end else if (Upscale_x == 213) begin
                is_gap = 1'b1;
            end else if (Upscale_x <= IMG2_END_X) begin
                mem_sel = 3'd2;
                local_x = Upscale_x - IMG2_START_X;
            end
            
        end else if (Upscale_y < 240) begin
            local_y = Upscale_y - 120; // 하단 영역 (0~119로 정규화)
            
            if (Upscale_x <= IMG0_END_X) begin
                mem_sel = 3'd3;
                local_x = Upscale_x - IMG0_START_X;
            end else if (Upscale_x == 106) begin
                is_gap = 1'b1;
            end else if (Upscale_x <= IMG1_END_X) begin
                mem_sel = 3'd4;
                local_x = Upscale_x - IMG1_START_X;
            end else if (Upscale_x == 213) begin
                is_gap = 1'b1;
            end else if (Upscale_x <= IMG2_END_X) begin
                mem_sel = 3'd5;
                local_x = Upscale_x - IMG2_START_X;
            end
        end
    end

    // --- 어드레스(addr) 매핑 ---
    // SLV1(내부 이미지)는 전체 프레임을 담고 있는 ROM/RAM이므로 1D 배열 주소(y*width + x)가 필요함.
    // 나머지 외부 SLV(0,2,3,4,5)는 1줄짜리 라인 버퍼이므로 로컬 X좌표(0~105)만 있으면 됨.
    assign addr = (mem_sel == 3'd1) ? (local_y * 106 + local_x) : local_x;

    // --- 최종 출력 ---
    // de 구간이면서 화면 사이의 틈(Gap)이 아닐 때만 픽셀 데이터 출력
    assign {port_red, port_green, port_blue} = (de && !is_gap) ? imgPxlData : 12'h000;

endmodule
