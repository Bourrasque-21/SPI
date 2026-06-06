#include "spi_app.h"

#define SPI_APP_CLK_DIV 100U

void SPI_App_Init(void)
{
    SPI_Init(SPI_APP_CLK_DIV);
}

int SPI_App_Send_Slv0(uint8_t data, uint8_t *rx_data)
{
    return SPI_Transfer(SPI_SLAVE_0, data, rx_data);
}

int SPI_App_Send_Slv1(uint8_t data, uint8_t *rx_data)
{
    return SPI_Transfer(SPI_SLAVE_1, data, rx_data);
}

int SPI_App_ClearAll(void)
{
    uint8_t rx_data;

    SPI_Transfer(SPI_SLAVE_0, 0x00U, &rx_data);
    SPI_Transfer(SPI_SLAVE_1, 0x00U, &rx_data);

    return 0;
}