/*
 * Copyright (c) 2018 Nordic Semiconductor ASA
 *
 * SPDX-License-Identifier: LicenseRef-Nordic-5-Clause
 */

/** @file
 *  @brief Nordic UART Bridge Service (NUS) sample
 */
#include <uart_async_adapter.h>

#include <zephyr/types.h>
#include <zephyr/kernel.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/usb/usb_device.h>

#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <soc.h>

#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/hci.h>

#include <bluetooth/services/nus.h>

#include <dk_buttons_and_leds.h>

#include <zephyr/settings/settings.h>

#include <stdio.h>
#include <string.h>

#include <zephyr/logging/log.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/drivers/gpio.h>
#define LOG_MODULE_NAME peripheral_uart
LOG_MODULE_REGISTER(LOG_MODULE_NAME);

#define STACKSIZE CONFIG_BT_NUS_THREAD_STACK_SIZE
#define PRIORITY 7

#define DEVICE_NAME CONFIG_BT_DEVICE_NAME
#define DEVICE_NAME_LEN	(sizeof(DEVICE_NAME) - 1)

#define RUN_STATUS_LED DK_LED1
#define RUN_LED_BLINK_INTERVAL 1000

#define CON_STATUS_LED DK_LED2

#define KEY_PASSKEY_ACCEPT DK_BTN1_MSK
#define KEY_PASSKEY_REJECT DK_BTN2_MSK

#define UART_BUF_SIZE CONFIG_BT_NUS_UART_BUFFER_SIZE
#define UART_WAIT_FOR_BUF_DELAY K_MSEC(50)
#define UART_WAIT_FOR_RX CONFIG_BT_NUS_UART_RX_WAIT_TIME
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
static K_SEM_DEFINE(ble_init_ok, 0, 1);

static struct bt_conn *current_conn;
static struct bt_conn *auth_conn;

static const struct device *uart = DEVICE_DT_GET(DT_CHOSEN(nordic_nus_uart));
static struct k_work_delayable uart_work;

struct uart_data_t {
	void *fifo_reserved;
	uint8_t data[UART_BUF_SIZE];
	uint16_t len;
};

static K_FIFO_DEFINE(fifo_uart_tx_data);
static K_FIFO_DEFINE(fifo_uart_rx_data);

static const struct bt_data ad[] = {
	BT_DATA_BYTES(BT_DATA_FLAGS, (BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR)),
	BT_DATA(BT_DATA_NAME_COMPLETE, DEVICE_NAME, DEVICE_NAME_LEN),
};

static const struct bt_data sd[] = {
	BT_DATA_BYTES(BT_DATA_UUID128_ALL, BT_UUID_NUS_VAL),
};

#ifdef CONFIG_UART_ASYNC_ADAPTER
UART_ASYNC_ADAPTER_INST_DEFINE(async_adapter);
#else
#define async_adapter NULL
#endif

static void uart_cb(const struct device *dev, struct uart_event *evt, void *user_data)
{
	ARG_UNUSED(dev);

	static size_t aborted_len;
	struct uart_data_t *buf;
	static uint8_t *aborted_buf;
	static bool disable_req;

	switch (evt->type) {
	case UART_TX_DONE:
		LOG_DBG("UART_TX_DONE");
		if ((evt->data.tx.len == 0) ||
		    (!evt->data.tx.buf)) {
			return;
		}

		if (aborted_buf) {
			buf = CONTAINER_OF(aborted_buf, struct uart_data_t,
					   data[0]);
			aborted_buf = NULL;
			aborted_len = 0;
		} else {
			buf = CONTAINER_OF(evt->data.tx.buf, struct uart_data_t,
					   data[0]);
		}

		k_free(buf);

		buf = k_fifo_get(&fifo_uart_tx_data, K_NO_WAIT);
		if (!buf) {
			return;
		}

		if (uart_tx(uart, buf->data, buf->len, SYS_FOREVER_MS)) {
			LOG_WRN("Failed to send data over UART");
		}

		break;

	case UART_RX_RDY:
		LOG_DBG("UART_RX_RDY");
		buf = CONTAINER_OF(evt->data.rx.buf, struct uart_data_t, data[0]);
		buf->len += evt->data.rx.len;

		if (disable_req) {
			return;
		}

		if ((evt->data.rx.buf[buf->len - 1] == '\n') ||
		    (evt->data.rx.buf[buf->len - 1] == '\r')) {
			disable_req = true;
			uart_rx_disable(uart);
		}

		break;

	case UART_RX_DISABLED:
		LOG_DBG("UART_RX_DISABLED");
		disable_req = false;

		buf = k_malloc(sizeof(*buf));
		if (buf) {
			buf->len = 0;
		} else {
			LOG_WRN("Not able to allocate UART receive buffer");
			k_work_reschedule(&uart_work, UART_WAIT_FOR_BUF_DELAY);
			return;
		}

		uart_rx_enable(uart, buf->data, sizeof(buf->data),
			       UART_WAIT_FOR_RX);

		break;

	case UART_RX_BUF_REQUEST:
		LOG_DBG("UART_RX_BUF_REQUEST");
		buf = k_malloc(sizeof(*buf));
		if (buf) {
			buf->len = 0;
			uart_rx_buf_rsp(uart, buf->data, sizeof(buf->data));
		} else {
			LOG_WRN("Not able to allocate UART receive buffer");
		}

		break;

	case UART_RX_BUF_RELEASED:
		LOG_DBG("UART_RX_BUF_RELEASED");
		buf = CONTAINER_OF(evt->data.rx_buf.buf, struct uart_data_t,
				   data[0]);

		if (buf->len > 0) {
			k_fifo_put(&fifo_uart_rx_data, buf);
		} else {
			k_free(buf);
		}

		break;

	case UART_TX_ABORTED:
		LOG_DBG("UART_TX_ABORTED");
		if (!aborted_buf) {
			aborted_buf = (uint8_t *)evt->data.tx.buf;
		}

		aborted_len += evt->data.tx.len;
		buf = CONTAINER_OF((void *)aborted_buf, struct uart_data_t,
				   data);

		uart_tx(uart, &buf->data[aborted_len],
			buf->len - aborted_len, SYS_FOREVER_MS);

		break;

	default:
		break;
	}
}

static void uart_work_handler(struct k_work *item)
{
	struct uart_data_t *buf;

	buf = k_malloc(sizeof(*buf));
	if (buf) {
		buf->len = 0;
	} else {
		LOG_WRN("Not able to allocate UART receive buffer");
		k_work_reschedule(&uart_work, UART_WAIT_FOR_BUF_DELAY);
		return;
	}

	uart_rx_enable(uart, buf->data, sizeof(buf->data), UART_WAIT_FOR_RX);
}

static bool uart_test_async_api(const struct device *dev)
{
	const struct uart_driver_api *api =
			(const struct uart_driver_api *)dev->api;

	return (api->callback_set != NULL);
}

static int uart_init(void)
{
	int err;
	int pos;
	struct uart_data_t *rx;
	struct uart_data_t *tx;

	if (!device_is_ready(uart)) {
		return -ENODEV;
	}

	if (IS_ENABLED(CONFIG_USB_DEVICE_STACK)) {
		err = usb_enable(NULL);
		if (err && (err != -EALREADY)) {
			LOG_ERR("Failed to enable USB");
			return err;
		}
	}

	rx = k_malloc(sizeof(*rx));
	if (rx) {
		rx->len = 0;
	} else {
		return -ENOMEM;
	}

	k_work_init_delayable(&uart_work, uart_work_handler);


	if (IS_ENABLED(CONFIG_UART_ASYNC_ADAPTER) && !uart_test_async_api(uart)) {
		/* Implement API adapter */
		uart_async_adapter_init(async_adapter, uart);
		uart = async_adapter;
	}

	err = uart_callback_set(uart, uart_cb, NULL);
	if (err) {
		k_free(rx);
		LOG_ERR("Cannot initialize UART callback");
		return err;
	}

	if (IS_ENABLED(CONFIG_UART_LINE_CTRL)) {
		LOG_INF("Wait for DTR");
		while (true) {
			uint32_t dtr = 0;

			uart_line_ctrl_get(uart, UART_LINE_CTRL_DTR, &dtr);
			if (dtr) {
				break;
			}
			/* Give CPU resources to low priority threads. */
			k_sleep(K_MSEC(100));
		}
		LOG_INF("DTR set");
		err = uart_line_ctrl_set(uart, UART_LINE_CTRL_DCD, 1);
		if (err) {
			LOG_WRN("Failed to set DCD, ret code %d", err);
		}
		err = uart_line_ctrl_set(uart, UART_LINE_CTRL_DSR, 1);
		if (err) {
			LOG_WRN("Failed to set DSR, ret code %d", err);
		}
	}

	tx = k_malloc(sizeof(*tx));

	if (tx) {
		pos = snprintf(tx->data, sizeof(tx->data),
			       "Starting Nordic UART service example\r\n");

		if ((pos < 0) || (pos >= sizeof(tx->data))) {
			k_free(rx);
			k_free(tx);
			LOG_ERR("snprintf returned %d", pos);
			return -ENOMEM;
		}

		tx->len = pos;
	} else {
		k_free(rx);
		return -ENOMEM;
	}

	err = uart_tx(uart, tx->data, tx->len, SYS_FOREVER_MS);
	if (err) {
		k_free(rx);
		k_free(tx);
		LOG_ERR("Cannot display welcome message (err: %d)", err);
		return err;
	}

	err = uart_rx_enable(uart, rx->data, sizeof(rx->data), UART_WAIT_FOR_RX);
	if (err) {
		LOG_ERR("Cannot enable uart reception (err: %d)", err);
		/* Free the rx buffer only because the tx buffer will be handled in the callback */
		k_free(rx);
	}

	return err;
}

static void connected(struct bt_conn *conn, uint8_t err)
{
	char addr[BT_ADDR_LE_STR_LEN];

	if (err) {
		LOG_ERR("Connection failed (err %u)", err);
		return;
	}

	bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));
	LOG_INF("Connected %s", addr);

	current_conn = bt_conn_ref(conn);

	dk_set_led_on(CON_STATUS_LED);
}

static void disconnected(struct bt_conn *conn, uint8_t reason)
{
	char addr[BT_ADDR_LE_STR_LEN];

	bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));

	LOG_INF("Disconnected: %s (reason %u)", addr, reason);

	if (auth_conn) {
		bt_conn_unref(auth_conn);
		auth_conn = NULL;
	}

	if (current_conn) {
		bt_conn_unref(current_conn);
		current_conn = NULL;
		dk_set_led_off(CON_STATUS_LED);
	}
}

#ifdef CONFIG_BT_NUS_SECURITY_ENABLED
static void security_changed(struct bt_conn *conn, bt_security_t level,
			     enum bt_security_err err)
{
	char addr[BT_ADDR_LE_STR_LEN];

	bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));

	if (!err) {
		LOG_INF("Security changed: %s level %u", addr, level);
	} else {
		LOG_WRN("Security failed: %s level %u err %d", addr,
			level, err);
	}
}
#endif

BT_CONN_CB_DEFINE(conn_callbacks) = {
	.connected    = connected,
	.disconnected = disconnected,
#ifdef CONFIG_BT_NUS_SECURITY_ENABLED
	.security_changed = security_changed,
#endif
};

#if defined(CONFIG_BT_NUS_SECURITY_ENABLED)
static void auth_passkey_display(struct bt_conn *conn, unsigned int passkey)
{
	char addr[BT_ADDR_LE_STR_LEN];

	bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));

	LOG_INF("Passkey for %s: %06u", addr, passkey);
}

static void auth_passkey_confirm(struct bt_conn *conn, unsigned int passkey)
{
	char addr[BT_ADDR_LE_STR_LEN];

	auth_conn = bt_conn_ref(conn);

	bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));

	LOG_INF("Passkey for %s: %06u", addr, passkey);
	LOG_INF("Press Button 1 to confirm, Button 2 to reject.");
}


static void auth_cancel(struct bt_conn *conn)
{
	char addr[BT_ADDR_LE_STR_LEN];

	bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));

	LOG_INF("Pairing cancelled: %s", addr);
}


static void pairing_complete(struct bt_conn *conn, bool bonded)
{
	char addr[BT_ADDR_LE_STR_LEN];

	bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));

	LOG_INF("Pairing completed: %s, bonded: %d", addr, bonded);
}


static void pairing_failed(struct bt_conn *conn, enum bt_security_err reason)
{
	char addr[BT_ADDR_LE_STR_LEN];

	bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));

	LOG_INF("Pairing failed conn: %s, reason %d", addr, reason);
}


static struct bt_conn_auth_cb conn_auth_callbacks = {
	.passkey_display = auth_passkey_display,
	.passkey_confirm = auth_passkey_confirm,
	.cancel = auth_cancel,
};

static struct bt_conn_auth_info_cb conn_auth_info_callbacks = {
	.pairing_complete = pairing_complete,
	.pairing_failed = pairing_failed
};
#else
static struct bt_conn_auth_cb conn_auth_callbacks;
static struct bt_conn_auth_info_cb conn_auth_info_callbacks;
#endif

static void bt_receive_cb(struct bt_conn *conn, const uint8_t *const data,
			  uint16_t len)
{
	int err;
	char addr[BT_ADDR_LE_STR_LEN] = {0};

	bt_addr_le_to_str(bt_conn_get_dst(conn), addr, ARRAY_SIZE(addr));

	LOG_INF("Received data from: %s", addr);

	for (uint16_t pos = 0; pos != len;) {
		struct uart_data_t *tx = k_malloc(sizeof(*tx));

		if (!tx) {
			LOG_WRN("Not able to allocate UART send data buffer");
			return;
		}

		/* Keep the last byte of TX buffer for potential LF char. */
		size_t tx_data_size = sizeof(tx->data) - 1;

		if ((len - pos) > tx_data_size) {
			tx->len = tx_data_size;
		} else {
			tx->len = (len - pos);
		}

		memcpy(tx->data, &data[pos], tx->len);

		pos += tx->len;

		/* Append the LF character when the CR character triggered
		 * transmission from the peer.
		 */
		if ((pos == len) && (data[len - 1] == '\r')) {
			tx->data[tx->len] = '\n';
			tx->len++;
		}

		err = uart_tx(uart, tx->data, tx->len, SYS_FOREVER_MS);
		if (err) {
			k_fifo_put(&fifo_uart_tx_data, tx);
		}
	}
}

static struct bt_nus_cb nus_cb = {
	.received = bt_receive_cb,
};

void error(void)
{
	dk_set_leds_state(DK_ALL_LEDS_MSK, DK_NO_LEDS_MSK);

	while (true) {
		/* Spin for ever */
		k_sleep(K_MSEC(1000));
	}
}

#ifdef CONFIG_BT_NUS_SECURITY_ENABLED
static void num_comp_reply(bool accept)
{
	if (accept) {
		bt_conn_auth_passkey_confirm(auth_conn);
		LOG_INF("Numeric Match, conn %p", (void *)auth_conn);
	} else {
		bt_conn_auth_cancel(auth_conn);
		LOG_INF("Numeric Reject, conn %p", (void *)auth_conn);
	}

	bt_conn_unref(auth_conn);
	auth_conn = NULL;
}

void button_changed(uint32_t button_state, uint32_t has_changed)
{
	uint32_t buttons = button_state & has_changed;

	if (auth_conn) {
		if (buttons & KEY_PASSKEY_ACCEPT) {
			num_comp_reply(true);
		}

		if (buttons & KEY_PASSKEY_REJECT) {
			num_comp_reply(false);
		}
	}
}
#endif /* CONFIG_BT_NUS_SECURITY_ENABLED */

static void configure_gpio(void)
{
	int err;

#ifdef CONFIG_BT_NUS_SECURITY_ENABLED
	err = dk_buttons_init(button_changed);
	if (err) {
		LOG_ERR("Cannot init buttons (err: %d)", err);
	}
#endif /* CONFIG_BT_NUS_SECURITY_ENABLED */

	err = dk_leds_init();
	if (err) {
		LOG_ERR("Cannot init LEDs (err: %d)", err);
	}
}
#define DT_DRV_COMPAT ti_ads1299
#define ADS1299_CMD_DELAY_US 30

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
        printk("Succesfully read device ID: 0x%02X", ADS_ID);
    }
    else{
        printk("Failed to read device ID: 0x%02X", ADS_ID);
    }
}

void ads1299_rdatac(const struct device *dev){
	const struct ads1299_data *data = dev->data;

	//setup buffers
	uint8_t tx_buf[27] = {0};
	uint8_t rx_buf[27] = {0};
	struct spi_buf tx = { .buf = tx_buf, .len = sizeof(tx_buf) };
    struct spi_buf rx = { .buf = rx_buf, .len = sizeof(rx_buf) };

    struct spi_buf_set tx_set = { .buffers = &tx, .count = 1 };
    struct spi_buf_set rx_set = { .buffers = &rx, .count = 1 };
    
	while(1){
		if(gpio_pin_get_dt(&data->drdy_gpio) != 1){
			gpio_pin_set_dt(&data->cs_gpios, 1);
			  int ret = spi_transceive(data->spi, data->spi_cfg, &tx_set, &rx_set);
			if (ret < 0) {
        		printk("Failed to write to collect data: 0x%02X", ret);
    		}
			gpio_pin_set_dt(&data->cs_gpios, 0);
			uint8_t ble_buf[12];
    		for (int ch = 0; ch < 4; ch++) {
				int32_t val = 	(rx_buf[3 + 3*ch] << 16) |
								(rx_buf[3 + 3*ch + 1] << 8) |
								rx_buf[3 + 3*ch + 2];
				if (val & 0x800000) val |= 0xFF000000;
					ble_buf[ch*3]   = rx_buf[3 + 3*ch];
					ble_buf[ch*3+1] = rx_buf[3 + 3*ch + 1];
					ble_buf[ch*3+2] = rx_buf[3 + 3*ch + 2];
					
    		}

			if (current_conn) {
				int err = bt_nus_send(current_conn, ble_buf, sizeof(ble_buf));
				if (err) printk("bt_nus_send error: %d\n", err);
				k_sleep(K_MSEC(1));
			}
			k_sleep(K_USEC(50));
	}
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
    switch(cmd) {
        case _RDATAC:
            gpio_pin_set_dt(&data->cs_gpios, 1);
            break;
        default:
            gpio_pin_set_dt(&data->cs_gpios, 0);
    }
    
    LOG_INF("Command sent sucesfully");
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

int main(void)
{
	int blink_status = 0;
	int err = 0;

	configure_gpio();

	err = uart_init();
	if (err) {
		error();
	}

	if (IS_ENABLED(CONFIG_BT_NUS_SECURITY_ENABLED)) {
		err = bt_conn_auth_cb_register(&conn_auth_callbacks);
		if (err) {
			printk("Failed to register authorization callbacks.\n");
			return 0;
		}

		err = bt_conn_auth_info_cb_register(&conn_auth_info_callbacks);
		if (err) {
			printk("Failed to register authorization info callbacks.\n");
			return 0;
		}
	}

	err = bt_enable(NULL);
	if (err) {
		error();
	}

	LOG_INF("Bluetooth initialized");

	k_sem_give(&ble_init_ok);

	if (IS_ENABLED(CONFIG_SETTINGS)) {
		settings_load();
	}

	err = bt_nus_init(&nus_cb);
	if (err) {
		LOG_ERR("Failed to initialize UART service (err: %d)", err);
		return 0;
	}

	err = bt_le_adv_start(BT_LE_ADV_CONN, ad, ARRAY_SIZE(ad), sd,
			      ARRAY_SIZE(sd));
	if (err) {
		LOG_ERR("Advertising failed to start (err %d)", err);
		return 0;
	}

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

		ads1299_rdatac(dev);

	
}

void ble_write_thread(void)
{
	/* Don't go any further until BLE is initialized */
	k_sem_take(&ble_init_ok, K_FOREVER);
	struct uart_data_t nus_data = {
		.len = 0,
	};

	for (;;) {
		/* Wait indefinitely for data to be sent over bluetooth */
		struct uart_data_t *buf = k_fifo_get(&fifo_uart_rx_data,
						     K_FOREVER);

		int plen = MIN(sizeof(nus_data.data) - nus_data.len, buf->len);
		int loc = 0;

		while (plen > 0) {
			memcpy(&nus_data.data[nus_data.len], &buf->data[loc], plen);
			nus_data.len += plen;
			loc += plen;

			if (nus_data.len >= sizeof(nus_data.data) ||
			   (nus_data.data[nus_data.len - 1] == '\n') ||
			   (nus_data.data[nus_data.len - 1] == '\r')) {
				if (bt_nus_send(NULL, nus_data.data, nus_data.len)) {
					LOG_WRN("Failed to send data over BLE connection");
				}
				nus_data.len = 0;
			}

			plen = MIN(sizeof(nus_data.data), buf->len - loc);
		}

		k_free(buf);
	}
}

K_THREAD_DEFINE(ble_write_thread_id, STACKSIZE, ble_write_thread, NULL, NULL,
		NULL, PRIORITY, 0, 0);
