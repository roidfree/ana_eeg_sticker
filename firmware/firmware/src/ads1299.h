#ifndef ADS1299_H_
#define ADS1299_H_

#include <zephyr/device.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/drivers/gpio.h>

/* -------------------------------------------------------------------------- */
/* ADS1299 Command Definitions                                                */
/* -------------------------------------------------------------------------- */
#define _WAKEUP   0x02  // Wake-up from standby mode
#define _STANDBY  0x04  // Enter standby mode
#define _RESET    0x06  // Reset the device
#define _START    0x08  // Start conversions
#define _STOP     0x0A  // Stop conversions
#define _RDATAC   0x10  // Enable continuous read mode
#define _SDATAC   0x11  // Stop continuous read mode
#define _RDATA    0x12  // Read data once

/* -------------------------------------------------------------------------- */
/* ADS1299 Register Addresses                                                 */
/* -------------------------------------------------------------------------- */
/* Device settings */
#define ID        0x00  // Device ID register

/* Global settings across all channels */
#define CONFIG1   0x01  // Data rate, daisy-chain mode, etc.
#define CONFIG2   0x02  // Test signal configuration
#define CONFIG3   0x03  // Bias drive, reference buffer

/* Individual channel settings */
#define CH1SET    0x05  // Channel 1 settings
#define CH2SET    0x06  // Channel 2 settings
#define CH3SET    0x07  // Channel 3 settings
#define CH4SET    0x08  // Channel 4 settings
#define CH5SET    0x09  // Channel 5 settings
#define CH6SET    0x0A  // Channel 6 settings
#define CH7SET    0x0B  // Channel 7 settings
#define CH8SET    0x0C  // Channel 8 settings

/* Lead-off detection */
#define LOFF      0x04  // Lead-off control register
#define LOFF_SENSP 0x0D // Positive lead-off settings
#define LOFF_SENSN 0x0E // Negative lead-off settings
#define LOFF_FLIP  0x0F // Lead-off flip register

/* GPIO and other registers */
#define GPIO       0x14 // General-purpose I/O register
#define MISC1      0x15 // Miscellaneous settings 1
#define MISC2      0x16 // Miscellaneous settings 2

/* -------------------------------------------------------------------------- */
/* Driver Data Structure                                                      */
/* -------------------------------------------------------------------------- */
struct ads1299_data {
    const struct device *spi;                   // SPI device
    const struct spi_config *spi_cfg;           // SPI configuration
    struct gpio_dt_spec cs_gpios;
    struct gpio_dt_spec drdy_gpio;              // DRDY pin (data ready)
    struct gpio_dt_spec reset_gpio;             // RESET pin
    struct gpio_callback drdy_cb;               //drdy callback
    struct k_work drdy_work;                    //drdy work queue
};
void ads1299_get_latest_sample(uint8_t *buf);
#define EEG_CHANNELS 4
extern uint8_t latest_eeg_sample[EEG_CHANNELS * 3];
extern bool sample_ready;
extern struct k_mutex eeg_mutex;
/* -------------------------------------------------------------------------- */
/* Function Prototypes                                                        */
/* -------------------------------------------------------------------------- */
//Powerup and reset
void ads1299_power_up(const struct device *dev);

//SPI read/write register
uint8_t ads1299_rreg(const struct device *dev, uint8_t address);
void ads1299_wrreg(const struct device *dev, uint8_t address, uint8_t value);

//Device recognition(reading device id)
void ads1299_recognise(const struct device *dev);

//send commands
void ads1299_send_command(const struct device *dev, uint8_t cmd);

//Data acquisition 
void ads1299_get_data_rdata(const struct device *dev);

//SPI initiliastion/GPIO setup
static int ads1299_init(const struct device *dev);

#endif /* ADS1299_H_ */
