`timescale 1ns / 1ps


module OV7670_controller (
    input  clk,
    input  reset,
    input  start,
    output scl,
    inout  sda
);

    logic [$clog2(57)-1:0] init_raddr;
    logic [          15:0] init_rdata;
    logic [ $clog2(10)-1:0] RW_ADDR_raddr;
    logic [           7:0] RW_ADDR_rdata;

    logic                  fsm_start;
    logic                  write;
    logic [           7:0] fsm_addr;
    logic [           7:0] fsm_wdata;
    logic [           7:0] fsm_rdata;
    logic                  ready;

    SCCB_fsm U_SCCB_fsm (
        .clk       (clk),
        .reset     (reset),
        // user control
        .start_btn (start),
        // OV7670_INIT_ROM interface
        .init_addr (init_raddr),
        .init_rdata(init_rdata),
        // AUTO_SETTING_ADDR_MEM interface
        .set_addr  (RW_ADDR_raddr),
        .set_data  (RW_ADDR_rdata),
        // SCCB interface
        .ready     (ready),
        .sccb_rdata(fsm_rdata),
        .o_addr    (fsm_addr),
        .o_wdata   (fsm_wdata),
        .en        (fsm_start),
        .write     (write)
    );

    SCCB U_SCCB (
        .clk      (clk),
        .reset    (reset),
        //fsm side
        .start    (fsm_start),
        .write    (write),
        .fsm_addr (fsm_addr),
        .fsm_wdata(fsm_wdata),
        .fsm_rdata(fsm_rdata),
        .ready    (ready),
        //I2C side
        .scl      (scl),
        .sda      (sda)
    );


    init_ROM U_init_ROM (
        .raddr(init_raddr),
        .rdata(init_rdata)
    );
    RW_ADDR_ROM U_RW_ADDR_ROM (
        .raddr(RW_ADDR_raddr),
        .rdata(RW_ADDR_rdata)
    );

endmodule


module init_ROM (
    input  [$clog2(57)-1:0] raddr,
    output [          15:0] rdata
);
    logic [15:0] mem[0:56];

    initial begin
        $readmemh("OV7670_rom.mem", mem);
    end

    assign rdata = mem[raddr];
endmodule

module RW_ADDR_ROM (
    input  [$clog2(10)-1:0] raddr,
    output [          7:0] rdata
);

    logic [7:0] mem[0:8];


    initial begin
        $readmemh("OV7670_rw.mem", mem);
    end

    assign rdata = mem[raddr];
endmodule
