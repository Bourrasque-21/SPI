#ifndef SRC_HAL_SPI_H_
#define SRC_HAL_SPI_H_

#include <stdint.h>

typedef struct
{
    volatile uint32_t CTRL;
    volatile uint32_t TXDATA;
    volatile uint32_t STATUS;
    volatile uint32_t CLKDIV;
} SPI_Typedef_t;

#define SPI_MASTER_BASE_ADDR 0x44a00000U
#define SPI_MASTER ((SPI_Typedef_t *)(SPI_MASTER_BASE_ADDR))

#define SPI_CTRL_START 0x01U
#define SPI_CTRL_SLAVE_SEL 0x02U

#define SPI_STATUS_BUSY 0x01U
#define SPI_STATUS_DONE 0x02U

void SPI_WriteTxData(SPI_Typedef_t *SPIx, uint8_t tx_data);
void SPI_SetClkDiv(SPI_Typedef_t *SPIx, uint8_t clk_div);
void SPI_WriteCtrl(SPI_Typedef_t *SPIx, uint8_t ctrl);
uint32_t SPI_ReadStatus(SPI_Typedef_t *SPIx);
uint8_t SPI_ReadRxData(SPI_Typedef_t *SPIx);
uint8_t SPI_IsBusy(SPI_Typedef_t *SPIx);
uint8_t SPI_IsDone(SPI_Typedef_t *SPIx);

#endif
