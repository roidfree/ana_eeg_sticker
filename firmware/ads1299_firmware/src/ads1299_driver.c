#include "ads1299_driver.h"
#include <zephyr/drivers/spi.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/logging/log.h>
#include <zephyr/devicetree.h>

// //register file for logging 
// LOG_MODULE_REGISTER(ads1299_driver, LOG_LEVEL_DBG);

// //device handles from overlay file
// static const struct gpio_dt_spec cs_spec = GPIO_DT_SPEC_GET(DT_ALIAS(ads_cs), gpios);
// static const struct gpio_dt_spec drdy_spec = GPIO_DT_SPEC_GET(DT_ALIAS(ads_drdy), gpios);
// static const struct gpio_dt_spec reset_spec = GPIO_DT_SPEC_GET(DT_ALIAS(ads_reset), gpios);

// static const struct device *spi_dev = DEVICE_DT_GET(DT_NODELABEL(spi1));

// //SPI configuration for ADS1299
// static const struct spi_config spi_cfg = {
//         .operation = SPI_OP_MODE_MASTER | SPI_WORD_SET(8) | SPI_MODE_CPHA,
//         .frequency = 1000000,
// };

// //initialose the ads1299
// int ads1299_init(const struct device *dev){
//     (void)dev;
//     int ret;

//     if(!device_is_ready(cs_spec.port) | !device_is_ready(drdy_spec.port) | !device_is_ready(reset_spec.port)| !device_is_ready(spi_dev)){
//         LOG_ERR("Device is not ready");
//         return -ENODEV;
//     }

//     ret = gpio_pin_configure_dt(&cs_spec, GPIO_OUTPUT_INACTIVE);
//     if(ret < 0){
//         return ret;
//     }
//     ret = gpio_pin_configure_dt(&reset_spec, GPIO_OUTPUT_INACTIVE);
//     if(ret < 0 ){
//         return ret;
//     }
//     ret = gpio_pin_configure_dt(&drdy_spec, GPIO_INPUT);
//     if(ret < 0){
//         return ret;
//     }
//     LOG_INF("ADS1299 sucessfully initialised");
//     return 0;
// }


// //send singly byte command to ads1299
// int ads1299_send_command(const struct device *dev, uint8_t command){
//     (void)dev;

//     struct spi_buf tx_buf = {.buf = &command, .len = 1};
//     struct spi_buf_set tx_set = {.buffers = &tx_buf, .count = 1};

//     gpio_pin_set_dt(&cs_spec, 1); //pull cs pin low
//     k_sleep(K_USEC(1));

//     int error = spi_write(spi_dev, &spi_cfg, &tx_set);
//     if(error) {
//         LOG_ERR("SPI write failed with error %d", error);
//     }

//     k_sleep(K_USEC(1));
//     gpio_pin_set_dt(&cs_spec, 0);
    
//     return error;
// }

// //read from a single register from the ads1299
// int ads1299_read_register(const struct device *dev, uint8_t address, uint8_t *value){
//     (void)dev;

//     uint8_t tx_buffer[2] = {(0x20 | address), 0x00};
//     uint8_t rx_buffer[3]; //3 bytes are needed

//     struct spi_buf tx_bufs[] = {
//         {.buf = &tx_buffer[0], .len = 1},
//         {.buf = &tx_buffer[1], .len = 1}
//     };
//     struct spi_buf_set tx_set = {.buffers = tx_bufs, .count = 2};

//     struct spi_buf rx_bufs[] = {
//         {.buf = NULL, .len = 1},
//         {.buf = NULL, .len = 1},
//         {.buf = value, .len = 1}
//     };
//     struct spi_buf_set rx_set = {.buffers = rx_bufs, .count = 3};

//     gpio_pin_set_dt(&cs_spec, 1);
//     k_sleep(K_USEC(1));

//     int error = spi_transceive(spi_dev, &spi_cfg, &tx_set, &rx_set);
//     if(error) {
//         LOG_ERR("SPI transceive failed with error %d", error);
//     }

//     k_sleep(K_USEC(1));
//     gpio_pin_set_dt(&cs_spec, 0);

//     return error;
// }

// //write a single value to a register on the ads1299
// int ads1299_write_register(const struct device *dev, uint8_t address, uint8_t value){
//     (void)dev;

//     uint8_t tx_buffer[2] = {(0x40 | address), value};

//     struct spi_buf tx_buf = {.buf = tx_buffer, .len = 2};
//     struct spi_buf_set tx_set = {.buffers = &tx_buf, .count = 1};

//     gpio_pin_set_dt(&cs_spec, 1);
//     k_sleep(K_USEC(1));

//     int error = spi_write(spi_dev, &spi_cfg, &tx_set);
//     if(error) {
//         LOG_ERR("SPI write failed with error %d", error);
//     }

//     k_sleep(K_USEC(1));
//     gpio_pin_set_dt(&cs_spec, 0);

//     return error;

// }