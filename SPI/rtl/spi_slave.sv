`timescale 1ns / 1ps

module spi_slave (
    input logic clk,
    input logic rst,

    input  logic [7:0] tx_data,
    output logic [7:0] rx_data,
    output logic       valid,

    input  logic sclk,
    input  logic mosi,
    output logic miso,
    input  logic cs_n
);

    logic [7:0] tx_shift_reg;
    logic [7:0] rx_shift_reg;
    logic [2:0] bit_cnt;
    logic sclk_rise, sclk_fall, sclk_1, sclk_2;
    logic cs_sync1, cs_sync2, mosi_sync1, mosi_sync2;

    assign sclk_rise = sclk_1 & ~sclk_2;
    assign sclk_fall = ~sclk_1 & sclk_2;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            // Edge detection
            sclk_1       <= 1'b0;
            sclk_2       <= 1'b0;

            // 2FF Synchrozier
            cs_sync1     <= 1'b1;
            cs_sync2     <= 1'b1;
            mosi_sync1   <= 1'b1;
            mosi_sync2   <= 1'b1;

            rx_data      <= 8'h0;
            valid        <= 1'b0;
            miso         <= 1'b1;
            tx_shift_reg <= 8'h0;
            rx_shift_reg <= 8'h0;
            bit_cnt      <= 3'd0;
        end else begin
            sclk_1     <= sclk;
            sclk_2     <= sclk_1;
            cs_sync1   <= cs_n;
            cs_sync2   <= cs_sync1;
            mosi_sync1 <= mosi;
            mosi_sync2 <= mosi_sync1;

            valid      <= 1'b0;
            if (cs_sync2) begin
                tx_shift_reg <= tx_data;
                rx_shift_reg <= 8'h0;
                bit_cnt      <= 3'd0;
                miso         <= tx_data[7];
            end else begin
                if (sclk_rise) begin
                    if (bit_cnt == 3'd7) begin
                        rx_data <= {rx_shift_reg[6:0], mosi_sync2};
                        valid   <= 1'b1;
                        bit_cnt <= 3'd0;
                    end else begin
                        rx_shift_reg <= {rx_shift_reg[6:0], mosi_sync2};
                        bit_cnt      <= bit_cnt + 1'b1;
                    end
                end

                // SPI mode 0: update the next MISO bit on SCLK falling edge.
                if (sclk_fall) begin
                    tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                    miso         <= tx_shift_reg[6];
                end
            end
        end
    end

endmodule
