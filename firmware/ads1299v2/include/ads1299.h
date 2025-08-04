//
//  ADS1299.h
//  Part of the Arduino Library
//  Created by Conor Russomanno, Luke Travis, and Joel Murphy. Summer 2013.
//
//  Modified by Chip Audette through April 2014
//

#ifndef ADS1299_H
#define ADS1299_H

#include <zephyr/device.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/drivers/gpio.h>
#include <stdint.h>

//Register and command defintions; these values come from ads1299 datasheet(gemini also said they are universal)

//SPI command definitions
#define _WAKEUP     0x02 //wakeup from standby mode
#define _STANDBY    0x04 //Enter standby mode
#define _RESET      0x06 //reset the device
#define _START      0x08 //Start/restart (synchronise) conversions
#define _STOP       0x0A //stop conversion
#define _RDATAC     0x10 //Enable Read Data Continuous mode
#define _SDATAC     0x11 //Stop Read Data Continuous mode
#define _RDATA      0x12 //Read data by command

//Register Address
#define ID          0x00
#define ADS_CONFIG1 0x01
#define ADS_CONFIG2 0x02
#define ADS_CONFIG3 0x03
#define LOFF        0x04
#define CH1SET      0x05
#define CH2SET      0x06
#define CH3SET      0x07
#define CH4SET      0x08
#define CH5SET      0x09
#define CH6SET      0x0A
#define CH7SET      0x0B
#define CH8SET      0x0C
#define BIAS_SENSP  0x0D
#define BIAS_SENSN  0x0E
#define LOFF_SENSP  0x0F
#define LOFF_SENSN  0x10
#define LOFF_FLIP   0x11
#define LOFF_STATP  0x12
#define LOFF_STATN  0x13
#define GPIO        0x14
#define MISC1       0x15
#define MISC2       0x16
#define CONFIG4     0x17 

/*----------------------------------------------------------------------------------
Device Context Structure
------------------------------------------------------------------------------------*/
// struct ads1299_data {
//     const struct device *spi_dev;
//     struct spi_config spi_cfg;

//     const struct gpio_dt_spec drdy_gpio;
//     const struct gpio_dt_spec reset_gpio;
// }

struct ads1299_data {
    struct spi_dt_spec spi;
    struct gpio_dt_spec drdy_gpio;
    struct gpio_dt_spec reset_gpio;
};
//Public function properties; Public API for ads1299 driver; these functions will be called in main c to talk to ads
/*Read id function
    parameter:
    *dev-> pointer to the ads1299 device structure
    *id-> pointer to the device ID
*/
int ads1299_read_id(const struct device *dev, uint8_t *id);

/*Send a one byte command to the ads1299
    parameter:
    *dev-> pointer to the ads1299 device structure
    command -> the command byte to send from the above list
*/
int ads1299_send_command(const struct device *dev, uint8_t command);

/*Reads a single register from the ads1299
    parameter:
    *dev -> pointer to the ads1299 device structure
    address -> address of the register from list above
    value -> pointer to a variable where the value will be stored
*/
int ads1299_read_register(const struct device *dev, uint8_t address, uint8_t *value);

/*write a single value to a register in the ads1299
    parameter:
    *dev -> pointer to the ads1299 device structure
    address -> address of the register from the list above
    value -> the value to write to the register
*/
int ads1299_write_register(const struct device *dev, uint8_t address, uint8_t value);


#endif