`timescale 1ns / 1ps

module MMU (
    //Mem write side
    input  logic                         CAM_pclk,
    input  logic                         CAM_we,
    input  logic [  $clog2(106*120)-1:0] CAM_wAddr,
    input  logic [                 15:0] CAM_wData,
    //Mem write side
    input  logic                         wclk,
    input  logic [                  4:0] w_sel,
    input  logic [                  4:0] we,
    input  logic [$clog2(106*120/4)-1:0] wAddr,
    input  logic [                119:0] wData,
    //Mem read side
    input  logic                         rclk,
    input  logic [                  4:0] r_sel,
    input  logic [  $clog2(106*120)-1:0] cam_rAddr,
    input  logic [$clog2(106*120/4)-1:0] mem_rAddr,
    output logic [                 23:0] rData0,
    output logic [                 11:0] rData1,
    output logic [                 23:0] rData2,
    output logic [                 23:0] rData3,
    output logic [                 23:0] rData4,
    output logic [                 23:0] rData5
);

    //w_sel,r_sel은 0일때 A메모리, 1일때 B메모리
    logic we0A, we2A, we3A, we4A, we5A;
    logic we0B, we2B, we3B, we4B, we5B;
    logic [11:0] Cam_rData;
    logic [23:0]
        local_rData0A,
        local_rData1A,
        local_rData2A,
        local_rData3A,
        local_rData4A,
        local_rData5A;
    logic [23:0]
        local_rData0B,
        local_rData1B,
        local_rData2B,
        local_rData3B,
        local_rData4B,
        local_rData5B;


    assign we0A   = (!w_sel[0] & we[0]);
    assign we2A   = (!w_sel[1] & we[1]);
    assign we3A   = (!w_sel[2] & we[2]);
    assign we4A   = (!w_sel[3] & we[3]);
    assign we5A   = (!w_sel[4] & we[4]);

    assign we0B   = (w_sel[0] & we[0]);
    assign we2B   = (w_sel[1] & we[1]);
    assign we3B   = (w_sel[2] & we[2]);
    assign we4B   = (w_sel[3] & we[3]);
    assign we5B   = (w_sel[4] & we[4]);

    assign rData0 = (r_sel[0]) ? local_rData0B : local_rData0A;
    assign rData1 = Cam_rData;
    assign rData2 = r_sel[1] ? local_rData2B : local_rData2A;
    assign rData3 = r_sel[2] ? local_rData3B : local_rData3A;
    assign rData4 = r_sel[3] ? local_rData4B : local_rData4A;
    assign rData5 = r_sel[4] ? local_rData5B : local_rData5A;

    //CAM mem
    frameBuffer U_IMG1 (
        // write side
        .wclk (CAM_pclk),
        .we   (CAM_we),
        .wAddr(CAM_wAddr),
        .wData({CAM_wData[15:12], CAM_wData[10:7], CAM_wData[4:1]}),
        // read side
        .rclk (rclk),
        .rAddr(cam_rAddr),
        .rData(Cam_rData)
    );
    //---------A------------------
    YCoCgframeBuffer U_IMG0A (
        // write side
        .wclk (wclk),
        .we   (we0A),
        .wAddr(wAddr),
        .wData(wData[23:0]),
        // read side
        .rclk (rclk),
        .rAddr(mem_rAddr),
        .rData(local_rData0A)
    );
    YCoCgframeBuffer #(
        .INIT_FILE("image_a0.mem")
    ) U_IMG2A (
        // write side
        .wclk (wclk),
        .we   (we2A),
        .wAddr(wAddr),
        .wData(wData[47:24]),
        // read side
        .rclk (rclk),
        .rAddr(mem_rAddr),
        .rData(local_rData2A)
    );
    YCoCgframeBuffer #(
        .INIT_FILE("image_a1.mem")
    ) U_IMG3A (
        // write side
        .wclk (wclk),
        .we   (we3A),
        .wAddr(wAddr),
        .wData(wData[71:48]),
        // read side
        .rclk (rclk),
        .rAddr(mem_rAddr),
        .rData(local_rData3A)
    );
    YCoCgframeBuffer #(
        .INIT_FILE("image_a2.mem")
    ) U_IMG4A (
        // write side
        .wclk (wclk),
        .we   (we4A),
        .wAddr(wAddr),
        .wData(wData[95:72]),
        // read side
        .rclk (rclk),
        .rAddr(mem_rAddr),
        .rData(local_rData4A)
    );
    YCoCgframeBuffer #(
        .INIT_FILE("image_a3.mem")
    ) U_IMG5A (
        // write side
        .wclk (wclk),
        .we   (we5A),
        .wAddr(wAddr),
        .wData(wData[119:96]),
        // read side
        .rclk (rclk),
        .rAddr(mem_rAddr),
        .rData(local_rData5A)
    );
    //---------B------------------
    YCoCgframeBuffer U_IMG0B (
        // write side
        .wclk (wclk),
        .we   (we0B),
        .wAddr(wAddr),
        .wData(wData[23:0]),
        // read side
        .rclk (rclk),
        .rAddr(mem_rAddr),
        .rData(local_rData0B)
    );

    YCoCgframeBuffer #(
        .INIT_FILE("image_b0.mem")
    ) U_IMG2B (
        // write side
        .wclk (wclk),
        .we   (we2B),
        .wAddr(wAddr),
        .wData(wData[47:24]),
        // read side
        .rclk (rclk),
        .rAddr(mem_rAddr),
        .rData(local_rData2B)
    );

    YCoCgframeBuffer #(
        .INIT_FILE("image_b1.mem")
    ) U_IMG3B (
        // write side
        .wclk (wclk),
        .we   (we3B),
        .wAddr(wAddr),
        .wData(wData[71:48]),
        // read side
        .rclk (rclk),
        .rAddr(mem_rAddr),
        .rData(local_rData3B)
    );
    YCoCgframeBuffer #(
        .INIT_FILE("image_b2.mem")
    ) U_IMG4B (
        // write side
        .wclk (wclk),
        .we   (we4B),
        .wAddr(wAddr),
        .wData(wData[95:72]),
        // read side
        .rclk (rclk),
        .rAddr(mem_rAddr),
        .rData(local_rData4B)
    );
    YCoCgframeBuffer #(
        .INIT_FILE("image_b3.mem")
    ) U_IMG5B (
        // write side
        .wclk (wclk),
        .we   (we5B),
        .wAddr(wAddr),
        .wData(wData[119:96]),
        // read side
        .rclk (rclk),
        .rAddr(mem_rAddr),
        .rData(local_rData5B)
    );

endmodule

module frameBuffer (
    // write side
    input  logic                       wclk,
    input  logic                       we,
    input  logic [$clog2(106*120)-1:0] wAddr,
    input  logic [               11:0] wData,
    // read side
    input  logic                       rclk,
    input  logic [$clog2(106*120)-1:0] rAddr,
    output logic [               11:0] rData
);

    logic [11:0] mem[0:(106*120)-1];

    //write
    always_ff @(posedge wclk) begin
        if (we) begin
            mem[wAddr] <= wData;
        end
    end
    //read
    always_ff @(posedge rclk) begin
        rData <= mem[rAddr];
    end
endmodule


module YCoCgframeBuffer #(
    parameter string INIT_FILE = ""
) (
    // write side
    input  logic                         wclk,
    input  logic                         we,
    input  logic [$clog2(106*120/4)-1:0] wAddr,
    input  logic [                 23:0] wData,
    // read side
    input  logic                         rclk,
    input  logic [$clog2(106*120/4)-1:0] rAddr,
    output logic [                 23:0] rData
);

    logic [23:0] mem[0:(106*120/4)-1];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    //write
    always_ff @(posedge wclk) begin
        if (we) begin
            mem[wAddr] <= wData;
        end
    end
    //read
    always_ff @(posedge rclk) begin
        rData <= mem[rAddr];
    end
endmodule
