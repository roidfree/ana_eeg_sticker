#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/logging/log.h>
#include "asd1299.h"

LOG_MODULE_REGISTER(main, LOG_LEVEL_ERR);


void main(void)
{
        const struct device *dev = DEVICE_DT_GET_ONE(ti_ads1299);
        if(!device_is_ready(dev)){
                LOG_ERR("ADS1299 device not ready");
                return;
        }

        uint8_t id = 0;
        if(ads1299_read_id(dev, &id) == 0) {
                LOG_INF("ADS1299 ID: 0x%02X", id);
        }
        else {
                LOG_ERR("Failed to read ADS1299 ID");
        }
}
