#ifndef SRC_APP_SPI_APP_H_
#define SRC_APP_SPI_APP_H_

#include <stdint.h>
#include "../DRIVER/spi_driver.h"

void SPI_App_Init(void);
int SPI_App_Send_Slv0(uint8_t data, uint8_t *rx_data);
int SPI_App_Send_Slv1(uint8_t data, uint8_t *rx_data);
int SPI_App_ClearAll(void);

#endif