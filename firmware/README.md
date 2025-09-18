# Log of firmware code 
- spi_loopback - test for spi gpios working ✅
- random_data_ble_setup - test for bluetooth setup with simulated eeg values ✅
- ads1299 - driver created for reading device ID ✅
- ads1299 - driver used to check how to read data from ads1299 board using RDATAC and send data to terminal✅
- firmware - merger between the BLE and SPI function attempted, failed ❌
- spi_ble_final - attempted to use sephamores and mutexes to avoid work queue issues between the two protocols ❌
- ble_rdata - used polling to overcome workqueue issues,  much simpler approach. DRDY fires, SPI data read occurs, BLE transmits the data. Final version of the code fully functional and stable ✅
