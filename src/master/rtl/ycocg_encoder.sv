module ycocg_encoder (
    input                              clk,
    input                              reset,
    input  logic                       start,
    //mem
    output logic [$clog2(106*120)-1:0] raddr0,
    output logic [$clog2(106*120)-1:0] raddr1,
    output logic [$clog2(106*120)-1:0] raddr2,
    output logic [$clog2(106*120)-1:0] raddr3,
    input  logic [               11:0] rdata0,
    input  logic [               11:0] rdata1,
    input  logic [               11:0] rdata2,
    input  logic [               11:0] rdata3,
    //ycocg_data ={Y3, Y2, Y1, Y0, Co, Cg}
    output logic [               23:0] ycocg_data
);

    //img 106,120


endmodule
