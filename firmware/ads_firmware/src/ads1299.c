#include "ads1299.h"
#include <zephyr/kernel.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/logging/log.h>
#include <zephyr/device.h>

#define DT_DRV_COMPAT ti_ads1299
LOG_MODULE_REGISTER(ads1299, LOG_LEVEL_DBG);
struct ads1299_config {
    struct spi_dt_spec bus;
    struct gpio_dt_spec drdy_gpio;
    struct gpio_dt_spec reset_gpio;
};

int ads1299_send_command(const struct device *dev, uint8_t command) {
    const struct ads1299_config *config = dev->config;
    const struct spi_buf tx_buf ={.buf = &command, .len = 1};
    const struct spi_buf_set tx_set = {.buffers = &tx_buf, .count = 1};

    return spi_write_dt(&config->bus, &tx_set);
}

int ads1299_write_register(const struct device *dev, uint8_t address, uint8_t value) {
    const struct ads1299_config *config = dev->config;
    uint8_t command_buf[2];

    command_buf[0] = 0x40 | address;
    command_buf[1] = 0x00;
    
    struct spi_buf bufs[2] = {
        {.buf = command_buf, .len = 2},
        {.buf = &value, .len = 1}
    };

    const struct spi_buf_set tx_set = {
        .buffers = bufs,
        .count = 2
    };

    return spi_write_dt(&config->bus, &tx_set);

}

int ads1299_read_register(const struct device *dev, uint8_t address, uint8_t *value){
    const struct ads1299_config *config = dev->config;
    uint8_t command_buf[2];

    command_buf[0] = 0x20 | address;
    command_buf[1] = 0x00;

    const struct spi_buf tx_buf = {
        .buf = command_buf,
        .len = 2
    };

    const struct spi_buf_set tx_set = {
        .buffers = &tx_buf,
        .count = 1
    };

    const struct spi_buf rx_buf = {
        .buf = value,
        .len = 1
    };

    const struct spi_buf_set rx_set = {
        .buffers = &rx_buf,
        .count = 1
    };

    return spi_transceive_dt(&config->bus, &tx_set, &rx_set);

}

int ads1299_init_driver(const struct device *dev){
    const struct ads1299_config *config = dev->config;
    int err;

    if(!spi_is_ready_dt(&config->bus)) {
        LOG_ERR("SPI Bus is not ready");
        return -ENODEV;
    }
    if(!gpio_is_ready_dt(&config->reset_gpio)){
        LOG_ERR("SPI reset is not ready");
        return -ENODEV;
    }

    err = gpio_pin_configure_dt(&config->reset_gpio, GPIO_OUTPUT);
    if(err){
        return err;
    }

    gpio_pin_set_dt(&config->reset_gpio, 0); 
    k_msleep(10);                             
    gpio_pin_set_dt(&config->reset_gpio, 1); 
    k_msleep(10);

    err = ads1299_send_command(dev, _SDATAC);
    if(err){
        LOG_ERR("Failed to send SDATAC command");
        return err;
    }

    LOG_INF("ADS1299 setup succesffully");
    return 0;
}

static const struct ads1299_config ads1299_config_0 = {
    .bus = SPI_DT_SPEC_INST_GET(0,(SPI_OP_MODE_MASTER|SPI_WORD_SET(8)|SPI_MODE_CPHA),0),
    .drdy_gpio = GPIO_DT_SPEC_INST_GET(0,drdy_gpios),
    .reset_gpio = GPIO_DT_SPEC_INST_GET(0, reset_gpios)
};

struct ads1299_data {};
static struct ads1299_data ads1299_data_0;


DEVICE_DT_INST_DEFINE(0,
&ads1299_init_driver,
NULL,
&ads1299_data_0,
&ads1299_config_0,
POST_KERNEL,
90,
NULL
);