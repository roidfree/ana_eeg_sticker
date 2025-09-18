#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/logging/log.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/drivers/gpio.h>
#include "ads1299.h"

LOG_MODULE_REGISTER(main, LOG_LEVEL_INF);


void main(void)
{
        LOG_INF("Starting ADS1299 test");
        const struct device *dev = DEVICE_DT_GET_ONE(ti_ads1299);
        if(!device_is_ready(dev)){
                LOG_ERR("ADS1299 device not ready");
                return;
        }

       ads1299_recognise(dev);

       ads1299_send_command(dev, _START);
       LOG_INF("Streaming of ADS Data started");
       ads1299_send_command(dev, _RDATAC);


}