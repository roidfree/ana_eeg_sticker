/*
 * Copyright (c) 2016 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdio.h>
#include <zephyr/kernel.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/logging/log.h>
#include <string.h>
//register file for holdiong log information, (ONLY AT INFORMATION LEVEL)
LOG_MODULE_REGISTER(spi_loopback, LOG_LEVEL_INF);

//message being sent
uint8_t tx_data[] = "SPI Loopback test";
//message being received
uint8_t rx_data[sizeof(tx_data)];

//spi peripheral from device tree will let me talk to all the pins
static const struct device *spi_dev = DEVICE_DT_GET(DT_NODELABEL(spi1));
//configure the spi to have the default settings of frequency and polarity(defined in overlay file)
static const struct spi_config spi_cfg = {
    .operation =    SPI_OP_MODE_MASTER |
                    SPI_WORD_SET(8) |
                    SPI_MODE_CPHA,
    .frequency =    1000000
};

void main(void)
{
    LOG_INF("STARTING SPI LOOPBACK TEST:");

    //check if device is ready to be used
    if(!device_is_ready(spi_dev)){
        LOG_ERR("SPI device %s is not ready to be used", spi_dev->name);
        return;
    }

    //define the buffers rx and tx 
    struct spi_buf tx_buf_desc = {
        .buf = tx_data,  //pointer to data to be sent
        .len = sizeof(tx_data) //pointer to length of the data
    };

    struct spi_buf rx_buf_desc = {
        .buf= rx_data,
        .len = sizeof(rx_data)
    };

    //creating as set, this will determine how many buffers are in each set
    struct spi_buf_set tx_set = {
        .buffers = &tx_buf_desc,
        .count = 1
    };

    struct spi_buf_set rx_set = {
        .buffers = &rx_buf_desc,
        .count = 1
    };
    
    //check for errors with transmitting the data
	int error = spi_transceive(spi_dev, &spi_cfg, &tx_set, &rx_set);
    if (error != 0) {
        LOG_ERR("SPI transceive failed with error %d", error);
        return;
    }

    //Verify the result and print to the terminal
    LOG_INF("SPI data sent:     %s", tx_data);
    LOG_INF("SPI data received: %s", rx_data);

    if (memcmp(tx_data, rx_data, sizeof(tx_data)) == 0) {
        LOG_INF("SUCCESS: Sent and received data match!");
    } else {
        LOG_ERR("ERROR: Sent and received data do not match.");
    }
}
