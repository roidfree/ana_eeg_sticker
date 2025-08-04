#include "ads1299.h"
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/drivers/spi.h>

LOG_MODULE_REGISTER(ads1299, LOG_LEVEL_ERR);



static int ads1299_read_register(const struct device *dev, uint8_t reg, uint8_t *val){
    struct ads1299_data *data = dev->data;

    uint8_t tx_buf[3] = {0x20 | reg, 0x00, 0x00}; //read register command
    struct spi_buf tx = {.buf = tx_buf, .len = sizeof(tx_buf)};
    struct spi_buf rx = {.buf = tx_buf, .len = sizeof(tx_buf)};
    struct spi_buf_set tx_set = {.buffers = &tx, .count = 1};
    struct spi_buf_set rx_set = {.buffers = &tx, . count = 1};

    int ret = spi_transceive_dt(&data->spi, &tx_set, &rx_set);
    if(ret < 0 ){
        return ret;
    }

    *val = rx_buf[2];
    return 0;
}

int ads1299_read_id(const struct device *dev, uint8_t *id){
    return ads1299_read_register(dev, ADS1299_REG, ID);
}

static int ads1299_init(const struct device *dev){
    struct ads1299_data *data = dev->data;
    
    if(!spi_is_ready_dt(&data->spi)) {
        LOG_ERR("SPI bus not ready");
        return -ENODEV;
    }

    if(!device_is_ready(data->drdy_gpio.port)) {
        LOG_ERR("DRDY GPIO not ready");
        return -ENODEV;
    }

    gpio_pin_configure_dt(&data->drdy_gpio.port, GPIO_INPUT);

    if(!device_is_ready(data->reset_gpio.port)){
        LOG_ERR("RESET GPIO not ready");
        return -ENODEV;
    }

    LOG_INF("ADS1299 initialised");
    return 0;
}

#define ADS1299_DEFINE(inst) static struct ads1299_data ads1299_data_##inst = {
    .spi = SPI_DT_SPEC_GET(DT_DRV_INST(inst), SPI_WORD_SET(8) | SPI_TRANSFER_MSB, 0 ),
    .drdy_gpio = GPIO_DT_SPEC_GET(DT_DRV_INST(inst), drdy_gpios),
    .reset_gpio = GPIO_DT_SPEC_GET(DT_DRV_INST(inst), reset_gpios)
    };
    DEVICE_DT_INST_DEFINE(inst, ads1299_init, NULL, &ads1299_data_##inst, NULL, POST_KERNEL, CONFIG_KERNEL_INIT_PRIORITY_DEVICE, NULL);

    DT_INST_FOREACH_STATUS_OKAY(ADS1299_DEFINE)