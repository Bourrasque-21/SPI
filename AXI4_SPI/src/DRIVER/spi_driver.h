#ifndef SRC_DRIVER_SPI_H_
#define SRC_DRIVER_SPI_H_

#include <stdint.h>

#define SPI_SLAVE_0 0U
#define SPI_SLAVE_1 1U

void SPI_Init(uint8_t clk_div);
int SPI_Transfer(uint8_t slave, uint8_t tx_data, uint8_t *rx_data);

#endif