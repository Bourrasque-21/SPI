#include <stdint.h>
#include "xil_printf.h"
#include "APP/spi_app.h"

int main(void)
{
    uint8_t rx_data;
    uint8_t selected_slave = 0U;
    char c;

    SPI_App_Init();

    xil_printf("================\r\n");
    xil_printf("SPI Start\r\n");
    xil_printf("1: Select Slave0\r\n");
    xil_printf("2: Select Slave1\r\n");
    xil_printf("0: Clear All\r\n");
    xil_printf("================\r\n");

    while (1)
    {
        c = inbyte();

        if (c == '1')
        {
            selected_slave = 0U;
            xil_printf("Selected SLV 0\r\n");
        }

        else if (c == '2')
        {
            selected_slave = 1U;
            xil_printf("Selected SLV 1\r\n");
        }

        else if (c == '0')
        {
            SPI_App_ClearAll();
            xil_printf("CLEAR 7-Segment => [0 0 0 0]\r\n");
        }

        else
        {
            if (selected_slave == 0U)
            {
                SPI_App_Send_Slv0((uint8_t)c, &rx_data);
            }
            else
            {
                SPI_App_Send_Slv1((uint8_t)c, &rx_data);
            }

            xil_printf("TX = %c(0x%x), RX = 0x%x\r\n", c, c, rx_data);
        }
    }
    return 0;
}