#include "BLEDevice.h"

#define LED1_PIN 22  // PIN18 上的 LED
#define LED2_PIN 21  // PIN21 上的 LED

// 定義 BLE 服務與特徵 UUID
BLEService ledService("A000"); // 自訂服務 UUID
BLECharacteristic led1Characteristic("A001");
BLECharacteristic led2Characteristic("A002");

// 當手機 App 寫入數據時的回調函數
void writeCB(BLECharacteristic* chr, uint8_t connID) {
    uint8_t value = chr->readData8();  // 讀取 8-bit 的數據

    Serial.print("Received data on ");
    Serial.print(chr->getUUID().str());
    Serial.print(": ");
    Serial.println(value, DEC);

    if (chr->getUUID() == "A001") {  // 控制 LED1 (PIN18)
        digitalWrite(LED1_PIN, value ? HIGH : LOW);
        Serial.println(value ? "LED1 ON" : "LED1 OFF");
    } else if (chr->getUUID() == "A002") {  // 控制 LED2 (PIN21)
        digitalWrite(LED2_PIN, value ? HIGH : LOW);
        Serial.println(value ? "LED2 ON" : "LED2 OFF");
    }
}

void setup() {
    Serial.begin(115200);
    Serial.println("初始化 BLE LED 伺服器...");

    pinMode(LED1_PIN, OUTPUT);
    pinMode(LED2_PIN, OUTPUT);
    digitalWrite(LED1_PIN, LOW);
    digitalWrite(LED2_PIN, LOW);

    // 設定 BLE 服務
    led1Characteristic.setWriteProperty(true);
    led1Characteristic.setWritePermissions(GATT_PERM_WRITE);
    led1Characteristic.setWriteCallback(writeCB);
    led1Characteristic.setBufferLen(1); // 只需要存一個 byte

    led2Characteristic.setWriteProperty(true);
    led2Characteristic.setWritePermissions(GATT_PERM_WRITE);
    led2Characteristic.setWriteCallback(writeCB);
    led2Characteristic.setBufferLen(1); // 只需要存一個 byte

    ledService.addCharacteristic(led1Characteristic);
    ledService.addCharacteristic(led2Characteristic);

    BLE.init();
    BLE.configServer(1);
    BLE.addService(ledService);

    // 設定 BLE 廣播
    BLEAdvertData advData;
    advData.addFlags();
    advData.addCompleteName("HUB8735_LED");
    BLE.configAdvert()->setAdvData(advData);

    BLE.beginPeripheral();
    Serial.println("BLE 伺服器啟動，請用手機 App 連線控制 LED");
}

void loop() {
    delay(1000);
}
