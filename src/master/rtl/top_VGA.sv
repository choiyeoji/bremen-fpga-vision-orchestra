`timescale 1ns / 1ps

module top_master (
    input logic clk,
    input logic reset,

    // i2c side
    output logic       scl,
    inout  logic       sda,
    // ov7670 side
    output logic       xclk,
    input  logic       pclk,
    input  logic       href,
    input  logic       vsync,
    input  logic [7:0] pdata,
    // vga side
    output logic       h_sync,
    output logic       v_sync,
    output logic [3:0] port_red,
    output logic [3:0] port_green,
    output logic [3:0] port_blue,
    // spi side
    output logic       sclk,
    input  logic [4:0] miso,
    output logic       mosi,
    output logic [4:0] cs_n,
    output logic [7:0] led,
    // Mugic sclae
    output logic       Mscale_scl,
    inout  logic       Mscale_sda,
    // uart
    input  logic       uart_rx,
    output logic       uart_tx
);

    // ==========================================
    // 🔗 내부 연결선 (Wire/Logic) 선언
    // ==========================================
    logic clk_100M, clk_25M, rclk;
    assign xclk = clk_25M;

    // VGA Decoder 및 픽셀 신호
    logic [                  9:0] x_pixel;
    logic [                  9:0] y_pixel;
    logic                         de;

    // OV7670 -> MMU 쓰기 신호
    logic                         cam_raw_we;
    logic [  $clog2(320*240)-1:0] cam_raw_wAddr;
    logic [                 15:0] cam_raw_wData;
    logic                         we;
    logic [  $clog2(106*120)-1:0] wAddr;
    logic [                 15:0] wData;

    // SPI 관련 신호
    logic                         decoder_start;
    logic                         fsm_done;
    logic [                  4:0] SPI_error;
    logic [                  4:0] SPI_we;
    logic [$clog2(106*120/4)-1:0] SPI_waddr;
    logic [                119:0] SPI_wdata;

    // MMU 제어 및 데이터 신호
    logic [4:0] r_sel, w_sel;

    // 주소 및 데이터 분리 신호
    logic [  $clog2(106*120)-1:0] cam_rAddr;
    logic [$clog2(106*120/4)-1:0] mem_rAddr;

    logic [23:0] rData0, rData2, rData3, rData4, rData5;
    logic [11:0] rData1;
    logic [ 7:0] slv0_rx_data;



    // 불필요한(Floating) Logic 선언부 싹 정리 완료!

    ila_0 U_ila_0 (
        .clk(clk),  // input wire clk
        .probe0(SPI_error[0]),  // input wire [0:0]  probe0  
        .probe1(SPI_we[0]),  // input wire [0:0]  probe1 
        .probe2(SPI_waddr),  // input wire [11:0]  probe2 
        .probe3({16'b0, slv0_rx_data[7:0]}),  // slave 0 data
        .probe4(cs_n[0]),  // input wire [0:0]  probe4 
        .probe5(miso[0])  // input wire [0:0]  probe5
    );
    // ==========================================
    // 🧱 하위 모듈 인스턴스화
    // ==========================================
    clk_wiz_0 U_clk_wiz (
        .clk_100M(clk_100M),
        .clk_25M (clk_25M),
        .reset   (reset),
        .clk_in1 (clk)
    );

    OV7670_controller U_OV7670_controller (
        .clk  (pclk),
        .reset(reset),
        .start(1'b1),
        .scl  (scl),
        .sda  (sda)
    );

    VGA_Decoder U_VGA_Decoder (
        .clk    (clk_100M),
        .reset  (reset),
        .rclk   (rclk),
        .h_sync (h_sync),
        .v_sync (v_sync),
        .x_pixel(x_pixel),
        .y_pixel(y_pixel),
        .de     (de)
    );

    OV7670_MemController U_OV7670_MemController (
        .pclk (pclk),
        .reset(reset),
        .href (href),
        .vsync(vsync),
        .pdata(pdata),
        .we   (cam_raw_we),
        .wAddr(cam_raw_wAddr),
        .wData(cam_raw_wData)
    );

    CameraDownScale106x120 U_CameraDownScale106x120 (
        .pclk   (pclk),
        .reset  (reset),
        .vsync  (vsync),
        .i_we   (cam_raw_we),
        .i_wData(cam_raw_wData),
        .o_we   (we),
        .o_wAddr(wAddr),
        .o_wData(wData)
    );

    SPI_sender U_SPI_sender (
        .clk          (clk_100M),
        .reset        (reset),
        .decoder_start(decoder_start),
        .fsm_done     (fsm_done),
        .SPI_error    (SPI_error),
        .sclk         (sclk),
        .mosi         (mosi),
        .miso         (miso),
        .cs_n         (cs_n),
        .we           (SPI_we),
        .waddr        (SPI_waddr),
        .wdata        (SPI_wdata),
        .slv0_rx_data (slv0_rx_data)
    );

    mem_controller U_mem_controller (
        .clk         (clk_100M),
        .reset       (reset),
        .x_pixel     (x_pixel),
        .y_pixel     (y_pixel),
        .de          (de),
        .SPI_start   (decoder_start),
        .SPI_error   (SPI_error),
        .SPI_fsm_done(fsm_done),
        .w_sel       (w_sel),
        .r_sel       (r_sel)
    );

    MMU U_MMU (
        .CAM_pclk (pclk),
        .CAM_we   (we),
        .CAM_wAddr(wAddr),
        .CAM_wData(wData),
        .wclk     (clk_100M),
        .w_sel    (w_sel),
        .we       (SPI_we),
        .wAddr    (SPI_waddr),
        .wData    (SPI_wdata),
        .rclk     (rclk),
        .r_sel    (r_sel),
        .cam_rAddr(cam_rAddr),
        .mem_rAddr(mem_rAddr),
        .rData0   (rData0),
        .rData1   (rData1),
        .rData2   (rData2),
        .rData3   (rData3),
        .rData4   (rData4),
        .rData5   (rData5)
    );

    UnScaleImage U_UnScaleImage (
        .de        (de),
        .x_pixel   (x_pixel),
        .y_pixel   (y_pixel),
        // cam side 
        .cam_raddr (cam_rAddr),
        .cam_rdata1(rData1),
        // mem side 
        .mem_raddr (mem_rAddr),
        .mem_rdata0(rData0),
        .mem_rdata2(rData2),
        .mem_rdata3(rData3),
        .mem_rdata4(rData4),
        .mem_rdata5(rData5),
        // VGA side
        .port_red  (port_red),
        .port_green(port_green),
        .port_blue (port_blue)
    );
    //------------------Mugic------------
    logic w_start_5s;
    logic w_done, p_tick;
    logic [11:0] uart_note;
    logic [ 1:0] m_note;
    logic [ 7:0] w_tx_data;
    logic w_u_start, w_start_2s;
    logic [11:0] uart_note_piano;
    // logic [1:0] mst_m_data;

    logic [1:0] m_note_sync0, m_note_sync1;
    always_ff @(posedge clk_100M) begin
        m_note_sync0 <= m_note;
        m_note_sync1 <= m_note_sync0;
    end

    OV7670_Music_Scale_Detect U_OV7670_Music_Scale_Detect (
        .rclk(pclk),
        .reset(reset),
        .we(we),
        // .p_tick(pclk),
        .vsync(vsync),
        .imgPxlData(wData),
        .wAddr(wAddr),
        .data_lat(m_note)
    );


    start_counter #(
        .COUNT(100_000_000)
    ) U_START_COUNTER_5s (
        .clk(clk_100M),
        .rst(reset),
        .start_tick(w_start_5s)
    );

    uart_master_fsm U_UART_MST_FSM (
        .clk    (clk_100M),
        .rst    (reset),
        .i_start(w_start_5s),
        .note   (uart_note),
        .done   (w_done),
        .tx_data(w_tx_data),
        .o_start(w_u_start)
    );
    //0.2ms
    start_counter #(
        .COUNT(200_000)
    ) U_START_COUNTER_2s (
        .clk       (clk_100M),
        .rst       (reset),
        .start_tick(w_start_2s)
    );
    // logic dbg_ack;

    I2C_master_fsm U_I2C_MASTER_FSM (
        .clk          (clk_100M),
        .rst          (reset),
        .start_i2c_fsm(w_start_2s),
        .m_note       (m_note_sync1),
        .note         (uart_note),
        .dbg_ack_slv1 (dbg_ack_slv1),
        .scl          (Mscale_scl),
        .sda          (Mscale_sda),
        .done         ()

    );



    // assign uart_note_piano = {
    //     6'b0, uart_note[5:4], uart_note[3:2], uart_note[1:0]
    // };

    uart_top U_UART_TOP (
        .clk(clk_100M),  // 100MHz 마스터 시스템 클럭
        .rst(reset),  // Active High 비동기 리셋 (posedge)

        // 외부 제어 인터페이스 (FSM / 시퀀서 연동용)
        .tx_data (w_tx_data),  // 전송할 8비트 데이터
        .tx_valid(w_u_start),  // 전송 시작 명령 틱 (1클럭 High)
        .tx_done (w_done),     // 전송 완료 응답 틱 (1클럭 High)
        .tx_ready(),           // 송신기 가용 상태 (Ready)

        // UART 물리 핀 인터페이스
        .tx(uart_tx),  // FPGA -> PC (TXD 핀)
        .rx(uart_rx)   // PC -> FPGA (RXD 핀)
    );
    assign led = {5'b0, dbg_ack_slv1, uart_note[1:0]};
    // assign led = {6'b0, m_note_sync1};
    // assign led = m_note;

endmodule


// `timescale 1ns / 1ps

// module top_master (
//     input logic clk,
//     input logic reset,

//     // i2c side
//     output logic       scl,
//     inout  logic       sda,
//     // ov7670 side
//     output logic       xclk,
//     input  logic       pclk,
//     input  logic       href,
//     input  logic       vsync,
//     input  logic [7:0] pdata,
//     // vga side
//     output logic       h_sync,
//     output logic       v_sync,
//     output logic [3:0] port_red,
//     output logic [3:0] port_green,
//     output logic [3:0] port_blue,
//     // spi side
//     output logic       sclk,
//     input  logic [4:0] miso,
//     output logic       mosi,
//     output logic [4:0] cs_n,
//     output logic       LED_xy00
// );

//     // ==========================================
//     // 🔗 내부 연결선 (Wire/Logic) 선언
//     // ==========================================
//     logic clk_100M, clk_25M, rclk;
//     assign xclk = clk_25M;

//     // VGA Decoder 및 픽셀 신호
//     logic [                  9:0] x_pixel;
//     logic [                  9:0] y_pixel;
//     logic                         de;

//     // OV7670 -> MMU 쓰기 신호
//     logic                         cam_raw_we;
//     logic [  $clog2(320*240)-1:0] cam_raw_wAddr;
//     logic [                 15:0] cam_raw_wData;
//     logic                         we;
//     logic [  $clog2(106*120)-1:0] wAddr;
//     logic [                 15:0] wData;

//     // SPI 관련 신호
//     logic                         decoder_start;
//     logic                         fsm_done;
//     logic [                  4:0] SPI_error;
//     logic [                  4:0] SPI_we;
//     logic [$clog2(106*120/4)-1:0] SPI_waddr;
//     logic [                119:0] SPI_wdata;

//     // MMU 제어 및 데이터 신호
//     logic [4:0] r_sel, w_sel;

//     // 주소 및 데이터 분리 신호
//     logic [  $clog2(106*120)-1:0] cam_rAddr;
//     logic [$clog2(106*120/4)-1:0] mem_rAddr;

//     logic [23:0] rData0, rData2, rData3, rData4, rData5;
//     logic [11:0] rData1;
//     logic [ 7:0] slv0_rx_data;

//     always_ff @(posedge clk_100M or posedge reset) begin
//         if (reset) begin
//             LED_xy00 <= 0;
//         end else if(x_pixel == 0 && LED_xy00 == 0) begin
//             LED_xy00 <= ~LED_xy00;
//         end
//     end


//     // 불필요한(Floating) Logic 선언부 싹 정리 완료!

//     ila_0 U_ila_0 (
//         .clk(clk),  // input wire clk
//         .probe0(SPI_error[0]),  // input wire [0:0]  probe0  
//         .probe1(SPI_we[0]),  // input wire [0:0]  probe1 
//         .probe2(SPI_waddr),  // input wire [11:0]  probe2 
//         .probe3({16'b0, slv0_rx_data[7:0]}),  // slave 0 data
//         .probe4(cs_n[0]),  // input wire [0:0]  probe4 
//         .probe5(miso[0])  // input wire [0:0]  probe5
//     );
//     // ==========================================
//     // 🧱 하위 모듈 인스턴스화
//     // ==========================================
//     clk_wiz_0 U_clk_wiz (
//         .clk_100M(clk_100M),
//         .clk_25M (clk_25M),
//         .reset   (reset),
//         .clk_in1 (clk)
//     );

//     OV7670_controller U_OV7670_controller (
//         .clk  (pclk),
//         .reset(reset),
//         .start(1'b1),
//         .scl  (scl),
//         .sda  (sda)
//     );

//     VGA_Decoder U_VGA_Decoder (
//         .clk    (clk_100M),
//         .reset  (reset),
//         .rclk   (rclk),
//         .h_sync (h_sync),
//         .v_sync (v_sync),
//         .x_pixel(x_pixel),
//         .y_pixel(y_pixel),
//         .de     (de)
//     );

//     OV7670_MemController U_OV7670_MemController (
//         .pclk (pclk),
//         .reset(reset),
//         .href (href),
//         .vsync(vsync),
//         .pdata(pdata),
//         .we   (cam_raw_we),
//         .wAddr(cam_raw_wAddr),
//         .wData(cam_raw_wData)
//     );

//     CameraDownScale106x120 U_CameraDownScale106x120 (
//         .pclk   (pclk),
//         .reset  (reset),
//         .vsync  (vsync),
//         .i_we   (cam_raw_we),
//         .i_wData(cam_raw_wData),
//         .o_we   (we),
//         .o_wAddr(wAddr),
//         .o_wData(wData)
//     );

//     SPI_sender U_SPI_sender (
//         .clk          (clk_100M),
//         .reset        (reset),
//         .decoder_start(decoder_start),
//         .fsm_done     (fsm_done),
//         .SPI_error    (SPI_error),
//         .sclk         (sclk),
//         .mosi         (mosi),
//         .miso         (miso),
//         .cs_n         (cs_n),
//         .we           (SPI_we),
//         .waddr        (SPI_waddr),
//         .wdata        (SPI_wdata),
//         .slv0_rx_data (slv0_rx_data)
//     );

//     mem_controller U_mem_controller (
//         .clk         (clk_100M),
//         .reset       (reset),
//         .x_pixel     (x_pixel),
//         .y_pixel     (y_pixel),
//         .de          (de),
//         .SPI_start   (decoder_start),
//         .SPI_error   (SPI_error),
//         .SPI_fsm_done(fsm_done),
//         .w_sel       (w_sel),
//         .r_sel       (r_sel)
//     );

//     MMU U_MMU (
//         .CAM_pclk (pclk),
//         .CAM_we   (we),
//         .CAM_wAddr(wAddr),
//         .CAM_wData(wData),
//         .wclk     (clk_100M),
//         .w_sel    (w_sel),
//         .we       (SPI_we),
//         .wAddr    (SPI_waddr),
//         .wData    (SPI_wdata),
//         .rclk     (rclk),
//         .r_sel    (r_sel),
//         .cam_rAddr(cam_rAddr),
//         .mem_rAddr(mem_rAddr),
//         .rData0   (rData0),
//         .rData1   (rData1),
//         .rData2   (rData2),
//         .rData3   (rData3),
//         .rData4   (rData4),
//         .rData5   (rData5)
//     );

//     UnScaleImage U_UnScaleImage (
//         .de        (de),
//         .x_pixel   (x_pixel),
//         .y_pixel   (y_pixel),
//         // cam side 
//         .cam_raddr (cam_rAddr),
//         .cam_rdata1(rData1),
//         // mem side 
//         .mem_raddr (mem_rAddr),
//         .mem_rdata0(rData0),
//         .mem_rdata2(rData2),
//         .mem_rdata3(rData3),
//         .mem_rdata4(rData4),
//         .mem_rdata5(rData5),
//         // VGA side
//         .port_red  (port_red),
//         .port_green(port_green),
//         .port_blue (port_blue)
//     );

// endmodule
