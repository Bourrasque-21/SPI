`timescale 1ns / 1ps

module demo_spi_master (

    input  logic       clk,
    input  logic       rst,
    input  logic       start,
    input  logic [7:0] sw,
    output logic       w_sclk,
    output logic       w_mosi,
    output logic [1:0] w_cs_n,
    input  logic       miso,
    output logic [7:0] led,
    input  logic       slave_sel
);

    spi_master U_SPI_MASTER (
        .clk(clk),
        .rst(rst),

        // Control
        .start(start),
        .tx_data(sw),
        .clk_div(8'h49),
        .slave_sel(slave_sel),

        .rx_data(led),
        .busy   (),
        .done   (),

        .cpol(1'b0),
        .cpha(1'b0),
        // SPI pins
        .sclk(w_sclk),
        .mosi(w_mosi),
        .miso(miso),
        .cs_n(w_cs_n)
    );
endmodule
