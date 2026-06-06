#include "spi_driver.h"
#include "../HAL/spi.h"

#define SPI_TIMEOUT 1000000U

void SPI_Init(uint8_t clk_div)
{
    SPI_SetClkDiv(SPI_MASTER, clk_div);
}

static int SPI_WaitBusySet(void)
{
    uint32_t timeout = SPI_TIMEOUT;

    while ((SPI_IsBusy(SPI_MASTER) == 0U) && (timeout != 0U))
    {
        timeout--;
    }

    return (timeout != 0U) ? 0 : -1;
}

static int SPI_WaitBusyClear(void)
{
    uint32_t timeout = SPI_TIMEOUT;

    while ((SPI_IsBusy(SPI_MASTER) != 0U) && (timeout != 0U))
    {
        timeout--;
    }

    return (timeout != 0U) ? 0 : -1;
}

int SPI_Transfer(uint8_t slave, uint8_t tx_data, uint8_t *rx_data)
{
    uint8_t ctrl = 0U;

    if (slave == SPI_SLAVE_1)
    {
        ctrl |= SPI_CTRL_SLAVE_SEL;
    }
    SPI_WriteTxData(SPI_MASTER, tx_data);

    SPI_WriteCtrl(SPI_MASTER, ctrl | SPI_CTRL_START);
    SPI_WriteCtrl(SPI_MASTER, ctrl);

    if (SPI_WaitBusySet() != 0)
    {
        return -1;
    }

    if (SPI_WaitBusyClear() != 0)
    {
        return -2;
    }

    *rx_data = SPI_ReadRxData(SPI_MASTER);

    return 0;
}