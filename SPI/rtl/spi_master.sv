`timescale 1ns / 1ps

module spi_master (
    input logic clk,
    input logic rst,

    // Control
    input logic       start,
    input logic [7:0] tx_data,
    input logic [7:0] clk_div,
    input logic       slave_sel,

    output logic [7:0] rx_data,
    output logic       busy,
    output logic       done,

    // SPI mode
    input logic cpol,  // Clock Polarity | SCLK IDLE level 0: LOW,          1: HIGH
    input logic cpha,  // Clock Phase    | Sampling edge   0: First edge,   1: Second edge

    // SPI pins
    output logic sclk,
    output logic mosi,
    input  logic miso,
    output logic [1:0] cs_n
);

    typedef enum logic [1:0] {
        IDLE,
        START,
        DATA,
        STOP
    } spi_state_e;
    spi_state_e state;

    logic [7:0] div_cnt, tx_shift_reg, rx_shift_reg;
    logic [2:0] bit_cnt;
    logic half_tick;  // 1-cycle pulse for each SCLK half-period during DATA
    logic sclk_r;  // Internal SCLK level
    logic step;  // 0: First SCLK edge, 1: Second SCLK edge

    assign sclk = sclk_r;

    // Divide system clock to create SCLK half-period tick
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            div_cnt   <= 0;
            half_tick <= 1'b0;
        end else begin
            if (state == DATA) begin
                if (div_cnt == clk_div) begin
                    div_cnt   <= 0;
                    half_tick <= 1'b1;
                end else begin
                    div_cnt   <= div_cnt + 1;
                    half_tick <= 1'b0;
                end
            end else begin
                div_cnt   <= 0;
                half_tick <= 0;
            end
        end
    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            state        <= IDLE;
            rx_data      <= 8'h0;
            busy         <= 1'b0;
            done         <= 1'b0;
            mosi         <= 1'b1;
            cs_n         <= 2'b11;
            tx_shift_reg <= 8'h0;
            rx_shift_reg <= 8'h0;
            bit_cnt      <= 3'd0;
            step         <= 1'b0;
            sclk_r       <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    mosi   <= 1'b1;
                    cs_n   <= 2'b11;
                    sclk_r <= cpol;
                    if (start) begin
                        tx_shift_reg <= tx_data;
                        bit_cnt      <= 3'd0;
                        busy         <= 1'b1;
                        cs_n[slave_sel] <= 1'b0;
                        step         <= 1'b0;
                        state        <= START;
                    end
                end

                START: begin
                    // Drive the first MOSI bit before SCLK starts toggling
                    if (!cpha) begin
                        mosi         <= tx_shift_reg[7];  // MSB First
                        tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                    end
                    state <= DATA;
                end

                DATA: begin
                    if (half_tick) begin
                        sclk_r <= ~sclk_r;
                        if (step == 1'b0) begin  // First SCLK edge
                            step <= 1'b1;
                            if (!cpha) begin  // CPHA=0: sample on first edge
                                rx_shift_reg <= {rx_shift_reg[6:0], miso};
                            end else begin // CPHA=1: drive data before second edge
                                mosi         <= tx_shift_reg[7];
                                tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                            end
                        end else begin  // Second SCLK edge
                            step <= 1'b0;
                            if (!cpha) begin // CPHA=0: drive next bit after sampling
                                if (bit_cnt == 3'd7) begin
                                    // Finish after the last bit
                                    state   <= STOP;
                                    rx_data <= rx_shift_reg;
                                end else begin
                                    mosi         <= tx_shift_reg[7];
                                    tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                                    bit_cnt      <= bit_cnt + 1'b1;
                                end
                            end else begin  // CPHA=1: sample on second edge
                                if (bit_cnt == 3'd7) begin
                                    rx_shift_reg <= {rx_shift_reg[6:0], miso};
                                    rx_data      <= {rx_shift_reg[6:0], miso};
                                    state        <= STOP;
                                end else begin
                                    rx_shift_reg <= {rx_shift_reg[6:0], miso};
                                    bit_cnt      <= bit_cnt + 1'b1;
                                end
                            end
                        end
                    end
                end

                STOP: begin
                    busy   <= 1'b0;
                    done   <= 1'b1;
                    cs_n   <= 2'b11;
                    mosi   <= 1'b1;
                    sclk_r <= cpol;
                    state  <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
