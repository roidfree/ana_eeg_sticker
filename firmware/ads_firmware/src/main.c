#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#ifdef CONFIG_ADS1299
#include "ads1299.h"
#endif
LOG_MODULE_REGISTER(main, LOG_LEVEL_INF);

const struct device *const ads_dev = DEVICE_DT_GET(DT_NODELABEL(ads1299));

void main(void){
        LOG_INF("ADS1299 Device test");
        
        if (!device_is_ready(ads_dev)) {
                LOG_ERR("Failed to initialize ADS1299 driver. Halting.");
                return; // Stop execution if initialization fails
        }
        
        k_sleep(K_MSEC(500));

        LOG_INF("Sending reset command");
        ads1299_send_command(ads_dev, _RESET);
        k_sleep(K_MSEC(10));

        LOG_INF("Sending STOP continuous data command");
        ads1299_send_command(ads_dev, _SDATAC);
        k_sleep(K_MSEC(10));

        uint8_t device_id = 0;
        LOG_INF("Reading Device ID Register...");
        int error = ads1299_read_register(ads_dev, ID, &device_id);

        if(error == 0){
                LOG_INF("Read Succesful. Device ID: 0x%02X", device_id);

                if((device_id & 0xE0) == 0xC0){
                        LOG_INF("Valid Device ID ! SPI communication is working!");
                }
                else{
                        LOG_ERR("Invalid Device ID! Check wiring, power, configuration");
                }
        }
        else{
                LOG_ERR("Failed to read Device ID register. Error %d", error);
        }
}
