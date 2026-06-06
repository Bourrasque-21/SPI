`timescale 1ns / 1ps

module demo_spi_slave (
    input  logic        clk,
    input  logic        rst,
    input  logic        w_sclk,
    input  logic        w_mosi,
    input  logic        w_cs1,
    input  logic        w_cs2,
    output logic        miso,
    input  logic [15:0] sw,
    output logic [15:0] led

    // output logic       v_led

);

    logic [7:0] rx_led1, rx_led2;
    logic miso_led1, miso_led2;

    assign led[7:0] = rx_led1;
    assign led[15:8] = rx_led2;
    assign miso = (!w_cs1) ? miso_led1 : (!w_cs2) ? miso_led2 : 1'b1;

    spi_slave U_SPI_SLAVE_LED1 (
        .clk(clk),
        .rst(rst),

        .rx_data(rx_led1),
        .tx_data(sw[7:0]),
        .valid  (),

        .sclk(w_sclk),
        .mosi(w_mosi),
        .miso(miso_led1),
        .cs_n(w_cs1)
    );


    spi_slave U_SPI_SLAVE_LED2 (
        .clk(clk),
        .rst(rst),

        .rx_data(rx_led2),
        .tx_data(sw[15:8]),
        .valid  (),

        .sclk(w_sclk),
        .mosi(w_mosi),
        .miso(miso_led2),
        .cs_n(w_cs2)
    );

endmodule
