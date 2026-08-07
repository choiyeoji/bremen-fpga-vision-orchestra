`timescale 1ns / 1ps

module SCCB_fsm (
    input  logic        clk,
    input  logic        reset,
    // user control
    input  logic        start_btn,
    // OV7670_INIT_ROM interface
    output logic [ $clog2(57)-1:0] init_addr,
    input  logic [15:0] init_rdata,
    // AUTO_SETTING_ADDR_MEM interface
    output logic [$clog2(10)-1:0] set_addr,
    input  logic [ 7:0] set_data,
    // SCCB interface
    input  logic        ready,
    input  logic [ 7:0] sccb_rdata,
    output logic [ 7:0] o_addr,
    output logic [ 7:0] o_wdata,
    output logic        en,
    output logic        write
);

    typedef enum logic [3:0] {
        S0,
        S1,
        S2,
        D2,
        D3,
        S3,
        D4,
        S4,
        S5,
        D5,
        S6,
        S7,
        S8,
        S9,
        S10
    } sccb_state;

    sccb_state state, next_state;

    localparam int CLK_FREQ_HZ = 100_000_000;
    localparam int DELAY_COUNT_30 = CLK_FREQ_HZ / 1000 * 30;
    localparam int DELAY_COUNT_10 = CLK_FREQ_HZ / 1000 * 10;
    localparam int DELAY_COUNT_1 = CLK_FREQ_HZ / 1000 * 1;

    logic [$clog2(DELAY_COUNT_30)-1:0] delay_cnt, next_delay_cnt;

    logic [5:0] pc_cnt, next_pc_cnt;

    logic [7:0] temp0, next_temp0;
    logic [7:0] temp1, next_temp1;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            state     <= S0;
            pc_cnt    <= 6'd0;
            delay_cnt <= '0;
            temp0     <= 8'd0;
            temp1     <= 8'd0;
        end else begin
            state     <= next_state;
            pc_cnt    <= next_pc_cnt;
            delay_cnt <= next_delay_cnt;
            temp0     <= next_temp0;
            temp1     <= next_temp1;
        end
    end

    always_comb begin
        next_state     = state;
        next_pc_cnt    = pc_cnt;
        next_delay_cnt = delay_cnt;
        next_temp0     = temp0;
        next_temp1     = temp1;

        o_addr         = 8'd0;
        o_wdata        = 8'd0;
        en             = 1'b0;
        write          = 1'b0;
        init_addr      = 8'd0;
        set_addr       = 8'd0;

        case (state)
            S0: begin
                next_pc_cnt    = 6'd0;
                next_delay_cnt = 0;

                if (start_btn) begin
                    next_state = S1;
                end
            end

            S1: begin
                init_addr = 8'd0;

                if (ready) begin
                    if (delay_cnt == 0) begin
                        o_addr  = init_rdata[15:8];
                        o_wdata = init_rdata[7:0];
                        en      = 1'b1;
                        write   = 1'b1;
                    end else begin
                        en    = 1'b0;
                        write = 1'b1;
                    end
                end

                if (delay_cnt == DELAY_COUNT_30 - 1) begin
                    next_delay_cnt = 0;
                    next_state     = S2;
                end else begin
                    next_delay_cnt = delay_cnt + 1'b1;
                end
            end

            S2: begin
                if (pc_cnt == 6'd42) begin
                    next_pc_cnt = 6'd0;
                    next_state  = D3;
                end else if (ready) begin
                    init_addr   = 8'd1 + pc_cnt;
                    o_addr      = init_rdata[15:8];
                    o_wdata     = init_rdata[7:0];
                    en          = 1'b1;
                    write       = 1'b1;
                    next_pc_cnt = pc_cnt + 1'b1;
                    next_state  = D2;
                end
            end

            D2: begin
                if (delay_cnt == DELAY_COUNT_1 - 1) begin
                    next_delay_cnt = 0;
                    next_state     = S2;
                end else begin
                    next_delay_cnt = delay_cnt + 1'b1;
                end
            end

            D3: begin
                if (delay_cnt == DELAY_COUNT_10 - 1) begin
                    next_delay_cnt = 0;
                    next_state     = S3;
                end else begin
                    next_delay_cnt = delay_cnt + 1'b1;
                end
            end

            S3: begin
                if (pc_cnt == 6'd8) begin
                    next_pc_cnt = 6'd0;
                    next_state  = S4;
                end else if (ready) begin
                    init_addr   = 8'd43 + pc_cnt;
                    o_addr      = init_rdata[15:8];
                    o_wdata     = init_rdata[7:0];
                    en          = 1'b1;
                    write       = 1'b1;
                    next_pc_cnt = pc_cnt + 1'b1;
                    next_state  = D4;
                end
            end

            D4: begin
                if (delay_cnt == DELAY_COUNT_1 - 1) begin
                    next_delay_cnt = 0;
                    next_state     = S3;
                end else begin
                    next_delay_cnt = delay_cnt + 1'b1;
                end
            end

            S4: begin
                if (pc_cnt == 6'd6) begin
                    next_pc_cnt = 6'd0;
                    next_state  = S5;
                end else if (ready) begin
                    init_addr   = 8'd51 + pc_cnt;
                    o_addr      = init_rdata[15:8];
                    o_wdata     = init_rdata[7:0];
                    en          = 1'b1;
                    write       = 1'b1;
                    next_pc_cnt = pc_cnt + 1'b1;
                end
            end

            S5: begin
                if (pc_cnt == 6'd2) begin
                    next_pc_cnt = 6'd0;
                    next_state  = D5;
                end else if (ready) begin
                    if (pc_cnt == 6'd0) begin
                        o_addr = 8'h12;
                    end else begin
                        o_addr = 8'h40;
                    end

                    en          = 1'b1;
                    write       = 1'b0;
                    next_pc_cnt = pc_cnt + 1'b1;

                    if (pc_cnt == 6'd0) begin
                        next_temp0 = sccb_rdata;
                    end else begin
                        next_temp1 = sccb_rdata;
                    end
                end
            end

            D5: begin
                if (delay_cnt == DELAY_COUNT_10 - 1) begin
                    next_delay_cnt = 0;
                    next_state     = S6;
                end else begin
                    next_delay_cnt = delay_cnt + 1'b1;
                end
            end

            S6: begin
                if (pc_cnt == 6'd2) begin
                    next_pc_cnt = 6'd0;
                    next_state  = S7;
                end else if (ready) begin
                    if (pc_cnt == 6'd0) begin
                        set_addr = 8'd2;
                        o_addr   = set_data;
                        o_wdata  = (temp0 & 8'b1111_1010) | 8'h04;
                    end else begin
                        set_addr = 8'd3;
                        o_addr   = set_data;
                        o_wdata  = (temp1 & 8'b0000_1111) | 8'h10;
                    end

                    en          = 1'b1;
                    write       = 1'b1;
                    next_pc_cnt = pc_cnt + 1'b1;
                end
            end

            S7: begin
                if (ready) begin
                    o_addr     = 8'h13;
                    en         = 1'b1;
                    write      = 1'b0;
                    next_temp0 = sccb_rdata;
                    next_state = S8;
                end
            end

            S8: begin
                if (pc_cnt == 6'd2) begin
                    next_pc_cnt = 6'd0;
                    next_state  = S9;
                end else if (ready) begin
                    if (pc_cnt == 6'd0) begin
                        set_addr = 8'd5;
                        o_addr   = set_data;
                        o_wdata  = temp0 | 8'h01;
                    end else begin
                        set_addr = 8'd6;
                        o_addr   = set_data;
                        o_wdata  = 8'h87;
                    end

                    en          = 1'b1;
                    write       = 1'b1;
                    next_pc_cnt = pc_cnt + 1'b1;
                end
            end

            S9: begin
                if (ready) begin
                    o_addr     = 8'h13;
                    en         = 1'b1;
                    write      = 1'b0;
                    next_temp1 = sccb_rdata;
                    next_state = S10;
                end
            end

            S10: begin
                if (ready) begin
                    set_addr = 8'd8;
                    o_addr   = set_data;
                    o_wdata  = temp1 | 8'h04;
                    en       = 1'b1;
                    write    = 1'b1;
                end

                //next_state = S0;
            end

            default: begin
                //next_state = S0;
            end
        endcase
    end

endmodule
