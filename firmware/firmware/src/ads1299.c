#include "ads1299.h"
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/drivers/gpio.h>



#define DT_DRV_COMPAT ti_ads1299
#define ADS1299_CMD_DELAY_US 30
#define EEG_CHANNELS 4
uint8_t latest_eeg_sample[EEG_CHANNELS * 3];
bool sample_ready = false;
K_MUTEX_DEFINE(eeg_mutex); // protects the latest sample
LOG_MODULE_REGISTER(ads1299, LOG_LEVEL_INF);
K_THREAD_STACK_DEFINE(drdy_stack, 1024);
struct k_work_q drdy_work_q;

//Powerup and reset
void ads1299_power_up(const struct device *dev){
    const struct ads1299_data *data = dev->data;
    LOG_INF("Starting ADS1299 Power Up");
    k_usleep(1000000); //Delay power for 1s
    k_usleep(70000); // Delay t_por = 2^16 x t_CLK of ADS (1/1MHz)=0.065s => Delay 70ms CHECK!!!!
    gpio_pin_set_dt(&data->reset_gpio, 1);
    k_busy_wait(10); // Delay 2 x t_CLK of ADS = 2x(1/1MHz)=2us CHECK!!!!
    gpio_pin_set_dt(&data->reset_gpio, 0);
    k_busy_wait(18); // Delay 18 x t_CLK of ADS = 18x(1/1MHz)=18us to start using the Device CHECK!!!!
    k_usleep(1000000); //Delay power for 1s
    LOG_INF("ADS1299 Powered up");
}

//SPI read/write register
uint8_t ads1299_rreg(const struct device *dev, uint8_t address){
    const struct ads1299_data *data = dev->data;
    LOG_INF("Beginning to read from register at address: 0x%02X", address);
    uint8_t tx_buf[3];
    uint8_t rx_buf[3];

    tx_buf[0] = 0x20 | address; // RREG + register address
    tx_buf[1] = 0x00;       // Number of registers to read - 1
    tx_buf[2] = 0x00;       // Dummy byte to clock out register value

    struct spi_buf tx = { .buf = tx_buf, .len = sizeof(tx_buf) };
    struct spi_buf rx = { .buf = rx_buf, .len = sizeof(rx_buf) };

    struct spi_buf_set tx_set = { .buffers = &tx, .count = 1 };
    struct spi_buf_set rx_set = { .buffers = &rx, .count = 1 };
    
    gpio_pin_set_dt(&data->cs_gpios, 1);
    int ret = spi_transceive(data->spi, data->spi_cfg, &tx_set, &rx_set);
    
    if (ret < 0) {
        LOG_ERR("Failed to read register: 0x%02X", ret);
        return ret;
    }
    
    k_busy_wait(30);
    gpio_pin_set_dt(&data->cs_gpios, 0);
    LOG_INF("Register succesfully read from address: 0x%02X", address);
    return rx_buf[2];// Register value arrives in the last byte
}
void ads1299_wrreg(const struct device *dev, uint8_t address, uint8_t value){
    const struct ads1299_data *data = dev->data;
    LOG_INF("Beginning to write to register at address: 0x%02X", address);
    uint8_t tx_buf[3];
    tx_buf[0] = 0x40 | address; // WREG + register address
    tx_buf[1] = 0x00;           // Number of registers to write - 1
    tx_buf[2] = value;           // Data byte

    struct spi_buf tx = { .buf = tx_buf, .len = sizeof(tx_buf) };
    struct spi_buf_set tx_set = { .buffers = &tx, .count = 1 };

    // Send WREG command + data
    gpio_pin_set_dt(&data->cs_gpios, 1);
    int ret = spi_write(data->spi, data->spi_cfg, &tx_set);
    if (ret < 0) {
        LOG_ERR("Failed to write register: 0x%02X", ret);
    }
    k_busy_wait(30); 
    gpio_pin_set_dt(&data->cs_gpios, 0);
    LOG_INF("Succesfully wrote to register at address: 0x%02X", address);
}

//Device recognition(reading device id)
void ads1299_recognise(const struct device *dev){
    const struct ads1299_data *data = dev->data;
    uint8_t ADS_ID = ads1299_rreg(dev, ID);
    if(ADS_ID == 0x3e){
        LOG_INF("Succesfully read device ID: 0x%02X", ADS_ID);
    }
    else{
        LOG_INF("Failed to read device ID: 0x%02X", ADS_ID);
    }
}

//send commands
void ads1299_send_command(const struct device *dev, uint8_t cmd){
    const struct ads1299_data *data = dev->data;
    LOG_INF("Sending command: 0x%02X", cmd);
    struct spi_buf tx_buf = {
        .buf = &cmd,
        .len = 1
    };
    struct spi_buf_set tx_set = {
        .buffers = &tx_buf,
        .count = 1
    };
    
    
    gpio_pin_set_dt(&data->cs_gpios, 1);
    int ret = spi_write(data->spi, data->spi_cfg, &tx_set);
    if (ret < 0 ){
        LOG_INF("Command send failed");
    }
    k_busy_wait(ADS1299_CMD_DELAY_US);
    gpio_pin_set_dt(&data->cs_gpios, 0);
    LOG_INF("Command sent sucesfully");
}

//DRDY INTERRUPT/CALLBACK(data acquisition)
static void drdy_callback(const struct device *port,
                          struct gpio_callback *cb,
                          uint32_t pins)
{
    struct ads1299_data *data = CONTAINER_OF(cb, struct ads1299_data, drdy_cb);

    // Schedule the work on the high-priority workqueue
    k_work_submit_to_queue(&drdy_work_q, &data->drdy_work);
}



#define BASELINE_SAMPLES 500

static int32_t channel_baseline[EEG_CHANNELS] = {0};
static int32_t baseline_accum[EEG_CHANNELS] = {0};
static int baseline_count = 0;
static bool baseline_captured = false;



void ads1299_store_sample(uint8_t *data)
{
    k_mutex_lock(&eeg_mutex, K_FOREVER);
    memcpy(latest_eeg_sample, data, EEG_CHANNELS * 3);
    sample_ready = true;  // <-- mark sample ready
    k_mutex_unlock(&eeg_mutex);
}
void ads1299_get_latest_sample(uint8_t *buf)
{
    k_mutex_lock(&eeg_mutex, K_FOREVER);
    memcpy(buf, latest_eeg_sample, EEG_CHANNELS * 3);
    sample_ready = false;  // <-- sample has been consumed
    k_mutex_unlock(&eeg_mutex);
}

// Called from DRDY work handler
static void ads1299_readout_work_handler(struct k_work *work)
{
    struct ads1299_data *data = CONTAINER_OF(work, struct ads1299_data, drdy_work);

    uint8_t rx_buf[27] = {0};
    uint8_t tx_buf[27] = {0};

    struct spi_buf tx = { .buf = tx_buf, .len = sizeof(tx_buf) };
    struct spi_buf rx = { .buf = rx_buf, .len = sizeof(rx_buf) };

    struct spi_buf_set tx_set = { .buffers = &tx, .count = 1 };
    struct spi_buf_set rx_set = { .buffers = &rx, .count = 1 };
    unsigned int key = irq_lock();   
    gpio_pin_set_dt(&data->cs_gpios, 1);
    int ret = spi_transceive(data->spi, data->spi_cfg, &tx_set, &rx_set);
    gpio_pin_set_dt(&data->cs_gpios, 0);
    irq_unlock(key);
    if (ret < 0) {
        LOG_ERR("SPI read failed: %d", ret);
        return;
    }

    uint8_t eeg_packet[EEG_CHANNELS * 3];
    for (int ch = 0; ch < EEG_CHANNELS; ch++) {
        int32_t val = (rx_buf[3 + 3*ch] << 16) |
                      (rx_buf[3 + 3*ch + 1] << 8) |
                      rx_buf[3 + 3*ch + 2];
        if (val & 0x800000) val |= 0xFF000000; // sign extend
        val -= channel_baseline[ch];

        eeg_packet[ch*3 + 0] = (val >> 16) & 0xFF;
        eeg_packet[ch*3 + 1] = (val >> 8) & 0xFF;
        eeg_packet[ch*3 + 2] = val & 0xFF;
    }

    // store safely under mutex
    printk("Raw bytes: %02X %02X %02X ...\n", rx_buf[3], rx_buf[4], rx_buf[5]);
    ads1299_store_sample(eeg_packet);
}


/* ADS1299 device initialization */
static int ads1299_init(const struct device *dev){
    struct ads1299_data *data = dev->data;
    

    if(!device_is_ready(data->spi)) {
        LOG_ERR("SPI bus not ready");
        return -ENODEV;
    }

    if(!device_is_ready(data->drdy_gpio.port)) {
        LOG_ERR("DRDY GPIO not ready");
        return -ENODEV;
    }

    gpio_pin_configure_dt(&data->drdy_gpio, GPIO_INPUT); //configure as input
    gpio_pin_interrupt_configure_dt(&data->drdy_gpio, GPIO_INT_EDGE_TO_INACTIVE); 

    if(!device_is_ready(data->reset_gpio.port)){
        LOG_ERR("RESET GPIO not ready");
        return -ENODEV;
    }
    gpio_pin_configure_dt(&data->reset_gpio, GPIO_OUTPUT_LOW);
    if(!device_is_ready(data->cs_gpios.port)){
        LOG_ERR("CS GPIO not ready");
        return -ENODEV;
    }
    gpio_pin_configure_dt(&data->cs_gpios, GPIO_OUTPUT_HIGH);

    // Init the work item
    k_work_init(&data->drdy_work, ads1299_readout_work_handler);
    k_work_queue_start(&drdy_work_q,
                   drdy_stack,
                   K_THREAD_STACK_SIZEOF(drdy_stack),
                   K_HIGHEST_APPLICATION_THREAD_PRIO,  // very high priority
                   NULL);
    // Init GPIO callback
    gpio_init_callback(&data->drdy_cb, drdy_callback, BIT(data->drdy_gpio.pin));
    gpio_add_callback(data->drdy_gpio.port, &data->drdy_cb);
   
    //reset and power up ads
    ads1299_power_up(dev);

    // Wake up and stop continuous read
    ads1299_send_command(dev, _WAKEUP);
    ads1299_send_command(dev, _SDATAC);

    LOG_INF("ADS1299 initialised");
    return 0;
}


/* Macro to define an instance of ADS1299 using DT */
static const struct spi_config ads1299_spi_cfg = {
    .frequency = 1000000,                   // 1 MHz, adjust if needed
    .operation = SPI_WORD_SET(8) | SPI_TRANSFER_MSB| SPI_FULL_DUPLEX| SPI_MODE_CPHA| SPI_OP_MODE_MASTER,
    .slave = 0,                              // SPI slave number
    .cs = 0,                       // setting to 0 if doing it manually
};
    #define ADS1299_DEFINE(inst) \
    static struct ads1299_data ads1299_data_##inst = { \
        .spi = DEVICE_DT_GET(DT_INST_BUS(inst)), \
        .spi_cfg = &ads1299_spi_cfg, \
        .cs_gpios = GPIO_DT_SPEC_GET(DT_DRV_INST(inst), cs_gpios), \
        .drdy_gpio = GPIO_DT_SPEC_GET(DT_DRV_INST(inst), drdy_gpios), \
        .reset_gpio = GPIO_DT_SPEC_GET(DT_DRV_INST(inst), reset_gpios) \
    }; \
    DEVICE_DT_INST_DEFINE(inst, \
        ads1299_init, \
        NULL, \
        &ads1299_data_##inst, \
        NULL, \
        POST_KERNEL, \
        CONFIG_KERNEL_INIT_PRIORITY_DEVICE, \
        NULL)

DT_INST_FOREACH_STATUS_OKAY(ADS1299_DEFINE)
