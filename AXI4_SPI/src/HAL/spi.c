#include "spi.h"

void SPI_WriteTxData(SPI_Typedef_t *SPIx, uint8_t tx_data)
{
    SPIx->TXDATA = tx_data;
}

void SPI_SetClkDiv(SPI_Typedef_t *SPIx, uint8_t clk_div)
{
    SPIx->CLKDIV = clk_div;
}

void SPI_WriteCtrl(SPI_Typedef_t *SPIx, uint8_t ctrl)
{
    SPIx->CTRL = ctrl;
}

uint32_t SPI_ReadStatus(SPI_Typedef_t *SPIx)
{
    return SPIx->STATUS;
}

uint8_t SPI_ReadRxData(SPI_Typedef_t *SPIx)
{
    return (uint8_t)(SPIx->STATUS >> 8);
}

uint8_t SPI_IsBusy(SPI_Typedef_t *SPIx)
{
    return (SPIx->STATUS & SPI_STATUS_BUSY) ? 1 : 0;
}

uint8_t SPI_IsDone(SPI_Typedef_t *SPIx)
{
    return (SPIx->STATUS & SPI_STATUS_DONE) ? 1 : 0;
}