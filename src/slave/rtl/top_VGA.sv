`timescale 1ns / 1ps

module top_VGA (
    input logic clk,
    input logic reset,
    output logic [1:0] led,

    // ov7670
    input  logic       ov7670_pclk,
    output logic       xclk,
    input  logic       href,
    input  logic       ov7670_vsync,
    input  logic [7:0] pdata,
    output logic       scl,
    inout  wire        sda,

    // vga 
    output logic [3:0] port_red,
    output logic [3:0] port_green,
    output logic [3:0] port_blue,
    output logic h_sync,
    output logic v_sync,

    // spi slave
    input  logic spi_sclk,
    input  logic spi_mosi,
    input  logic spi_cs_n,
    output logic spi_miso,

    // i2c slave
    input logic scl_s,
    inout wire  sda_s
);

    logic clk_100, clk_25;
    assign xclk = clk_25;

    // vga
    logic p_tick;
    logic [9:0] x_pixel, y_pixel;
    logic [9:0] x_pixel_d, y_pixel_d;
    logic de, de_d;

    // 320x240 frameBuffer
    logic [16:0] addr, wAddr;
    logic [15:0] imgPxlData, wData;
    logic        we;

    // downscale -> cam buffer
    logic [11:0] downscale_color;
    logic        ds_valid;
    logic        cam_we;
    logic [13:0] cam_waddr, cam_raddr;
    logic [11:0] cam_rdata;
    logic        frame_done;

    // frame handshake
    logic        frame_ready;
    logic sender_busy, sender_done;
    logic send_start, sending, send_done;
    logic send_abort;

    logic push, full;
    logic [7:0] push_data;

    logic [1:0] data;

    logic ack_out, busy;

    clk_wiz_0 CLK_DIVIDER (
        .clk_out1(clk_100),
        .clk_out2(clk_25),
        .reset(reset),
        .clk_in1(clk)
    );

    OV7670_SCCB_Controller U_OV7670_SCCB_Controller (
        .clk    (clk_100),
        .reset  (reset),
        .ack_in (1'b1),
        .ack_out(ack_out),
        .busy   (busy),
        .scl    (scl),
        .sda    (sda)
    );

    VGA_Decoder U_VGA_Decoder (
        .clk    (clk_100),
        .reset  (reset),
        .p_tick (p_tick),
        .h_sync (h_sync),
        .v_sync (v_sync),
        .x_pixel(x_pixel),
        .y_pixel(y_pixel),
        .de     (de)
    );

    VGA_pixel_delay U_VGA_pixel_delay (
        .clk      (clk_100),
        .reset    (reset),
        .p_tick   (p_tick),
        .de       (de),
        .x_pixel  (x_pixel),
        .y_pixel  (y_pixel),
        .de_d     (de_d),
        .x_pixel_d(x_pixel_d),
        .y_pixel_d(y_pixel_d)
    );

    OV7670_MemController U_OV7670_MemController (
        .pclk (ov7670_pclk),
        .reset(reset),
        .href (href),
        .vsync(ov7670_vsync),
        .pdata(pdata),
        .we   (we),
        .wAddr(wAddr),
        .wData(wData)
    );

    frameBuffer U_frameBuffer (
        .wclk (ov7670_pclk),
        .we   (we),
        .wAddr(wAddr),
        .wData(wData),
        .rclk (clk_100),
        .ren  (p_tick),
        .rAddr(addr),
        .rData(imgPxlData)
    );

    DownScaleimage U_DownScaleimage (
        .clk       (clk_100),
        .reset     (reset),
        .p_tick    (p_tick),
        .de        (de),
        .x_pixel   (x_pixel),
        .y_pixel   (y_pixel),
        .addr      (addr),
        .imgPxlData(imgPxlData),
        .port_red  (downscale_color[11:8]),
        .port_green(downscale_color[7:4]),
        .port_blue (downscale_color[3:0]),
        .o_valid   (ds_valid)
    );

    assign {port_red, port_blue, port_green} = downscale_color;

    Cam_WriteController U_Cam_WriteController (
        .clk     (clk_100),
        .reset   (reset),
        .p_tick  (p_tick),
        .v_sync  (v_sync),
        .ds_valid(ds_valid),
        .we      (cam_we),
        .wAddr   (cam_waddr),
        .done    (frame_done)
    );

    Cam_frameBuffer U_Cam_frameBuffer (
        .clk        (clk_100),
        .reset      (reset),
        .we         (cam_we),
        .wAddr      (cam_waddr),
        .wData      (downscale_color),
        .frame_done (frame_done),
        .rAddr      (cam_raddr),
        .rData      (cam_rdata),
        .sending    (sending),
        .sender_busy(sender_busy),
        .tx_done    (send_done),
        .frame_ready(frame_ready)
    );

    ycocg_frame_sender U_YCOCG_frame_sender (
        .clk      (clk_100),
        .reset    (reset),
        .abort    (send_abort),
        .start    (send_start),
        .busy     (sender_busy),
        .done     (sender_done),
        .rAddr    (cam_raddr),
        .rData    (cam_rdata),
        .push     (push),
        .push_data(push_data),
        .full     (full)
    );

    SPI_Slave U_SPI_Slave (
        .clk        (clk_100),
        .reset      (reset),
        .sclk       (spi_sclk),
        .mosi       (spi_mosi),
        .cs_n       (spi_cs_n),
        .miso       (spi_miso),
        .push       (push),
        .push_data  (push_data),
        .full       (full),
        .frame_ready(frame_ready),
        .sender_busy(sender_busy),
        .send_start (send_start),
        .sending    (sending),
        .send_done  (send_done),
        .send_abort (send_abort)
    );

    OV7670_Music_Scale_Detect U_OV7670_Music_Scale_Detect (
        .clk       (clk_100),
        .reset     (reset),
        .vsync     (v_sync),
        .p_tick     (p_tick),
        .imgPxlData(imgPxlData),
        .x_pixel   (x_pixel_d),
        .y_pixel   (y_pixel_d),
        .data_lat  (data)
    );

    i2c_slave #(
        .SLA_ADDR(7'h10)
    ) U_I2C_SLAVE (
        .clk(clk_100),
        .reset(reset),
        .tx_data({6'd0, data}),
        .rx_data(),
        .done(),
        .scl(scl_s),
        .sda(sda_s)
    );

    assign led = data;
    // I2C_SLAVE U_I2C_SLAVE (
    //     .clk    (clk_100),
    //     .reset  (reset),
    //     .tx_data({6'b0, data}),
    //     .rx_data(),
    //     .done   (),
    //     .busy   (),
    //     .scl    (i2c_scl),
    //     .sda    (i2c_sda)
    // );

endmodule
