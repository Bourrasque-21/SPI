`timescale 1ns / 1ps

module demo_spi_slave_fnd #(
    parameter int FND_SCAN_DIV = 100_000
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        w_sclk,
    input  logic        w_mosi,
    input  logic [ 1:0] w_cs_n,
    output logic        miso,
    input  logic [15:0] sw,
    output logic [ 3:0] fnd_digit,
    output logic [ 7:0] fnd_data
);

    localparam int SCAN_CNT_WIDTH = (FND_SCAN_DIV <= 1) ? 1 : $clog2(FND_SCAN_DIV);

    logic [SCAN_CNT_WIDTH-1:0] scan_cnt;
    logic [1:0] scan_sel;

    logic [7:0] slv0_rx_data;
    logic [7:0] slv1_rx_data;
    logic [3:0] slv0_hex_hi;
    logic [3:0] slv0_hex_lo;
    logic [3:0] slv1_hex_hi;
    logic [3:0] slv1_hex_lo;
    logic       slv0_miso;
    logic       slv1_miso;

    assign miso = (!w_cs_n[0]) ? slv0_miso :
                  (!w_cs_n[1]) ? slv1_miso : 1'b1;

    spi_slave_fnd U_SPI_SLAVE_FND0 (
        .clk        (clk),
        .rst        (rst),
        .sclk       (w_sclk),
        .mosi       (w_mosi),
        .miso       (slv0_miso),
        .cs_n       (w_cs_n[0]),
        .tx_data    (sw[7:0]),
        .rx_data    (slv0_rx_data),
        .valid      (),
        .hex_data_hi(slv0_hex_hi),
        .hex_data_lo(slv0_hex_lo)
    );

    spi_slave_fnd U_SPI_SLAVE_FND1 (
        .clk        (clk),
        .rst        (rst),
        .sclk       (w_sclk),
        .mosi       (w_mosi),
        .miso       (slv1_miso),
        .cs_n       (w_cs_n[1]),
        .tx_data    (sw[15:8]),
        .rx_data    (slv1_rx_data),
        .valid      (),
        .hex_data_hi(slv1_hex_hi),
        .hex_data_lo(slv1_hex_lo)
    );

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            scan_cnt <= '0;
            scan_sel <= 2'd0;
        end else begin
            if (scan_cnt == FND_SCAN_DIV - 1) begin
                scan_cnt <= '0;
                scan_sel <= scan_sel + 1'b1;
            end else begin
                scan_cnt <= scan_cnt + 1'b1;
            end
        end
    end

    always_comb begin
        fnd_digit = 4'b1111;
        fnd_data  = 8'hff;

        case (scan_sel)
            2'd0: begin
                fnd_digit = 4'b1110;
                fnd_data  = hex_to_fnd(slv1_hex_lo);
            end
            2'd1: begin
                fnd_digit = 4'b1101;
                fnd_data  = hex_to_fnd(slv1_hex_hi);
            end
            2'd2: begin
                fnd_digit = 4'b1011;
                fnd_data  = hex_to_fnd(slv0_hex_lo);
            end
            2'd3: begin
                fnd_digit = 4'b0111;
                fnd_data  = hex_to_fnd(slv0_hex_hi);
            end
            default: begin
                fnd_digit = 4'b1111;
                fnd_data  = 8'hff;
            end
        endcase
    end

    function automatic logic [7:0] hex_to_fnd(input logic [3:0] hex_data);
        begin
            case (hex_data)
                4'h0: hex_to_fnd = 8'hc0;
                4'h1: hex_to_fnd = 8'hf9;
                4'h2: hex_to_fnd = 8'ha4;
                4'h3: hex_to_fnd = 8'hb0;
                4'h4: hex_to_fnd = 8'h99;
                4'h5: hex_to_fnd = 8'h92;
                4'h6: hex_to_fnd = 8'h82;
                4'h7: hex_to_fnd = 8'hf8;
                4'h8: hex_to_fnd = 8'h80;
                4'h9: hex_to_fnd = 8'h90;
                4'ha: hex_to_fnd = 8'h88;
                4'hb: hex_to_fnd = 8'h83;
                4'hc: hex_to_fnd = 8'hc6;
                4'hd: hex_to_fnd = 8'ha1;
                4'he: hex_to_fnd = 8'h86;
                4'hf: hex_to_fnd = 8'h8e;
                default: hex_to_fnd = 8'hff;
            endcase
        end
    endfunction

endmodule

module spi_slave_fnd (
    input  logic       clk,
    input  logic       rst,
    input  logic       sclk,
    input  logic       mosi,
    output logic       miso,
    input  logic       cs_n,
    input  logic [7:0] tx_data,
    output logic [7:0] rx_data,
    output logic       valid,
    output logic [3:0] hex_data_hi,
    output logic [3:0] hex_data_lo
);

    assign hex_data_hi = rx_data[7:4];
    assign hex_data_lo = rx_data[3:0];

    spi_slave U_SPI_SLAVE (
        .clk    (clk),
        .rst    (rst),
        .tx_data(tx_data),
        .rx_data(rx_data),
        .valid  (valid),
        .sclk   (sclk),
        .mosi   (mosi),
        .miso   (miso),
        .cs_n   (cs_n)
    );

endmodule
