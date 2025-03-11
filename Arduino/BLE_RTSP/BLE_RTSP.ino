#include "BLEDevice.h"
#include "WiFi.h"
#include "StreamIO.h"
#include "VideoStream.h"
#include "RTSP.h"

// 硬體與 RTSP 設定
#define CHANNELVID  0   // RTSP 影像串流通道
#define RTSP_PORT   554 // RTSP 服務埠
String rtspURL = "";

// LED 設定
#define LED1_PIN 22  // LED1
#define LED2_PIN 21  // LED2

// Wi-Fi 設定變數
char ssid[32] = {0};      // SSID
char password[32] = {0};  // Wi-Fi 密碼
bool wifiConfigured = false; // Wi-Fi 配置完成標誌
IPAddress ip;

// BLE 服務 UUID
BLEService WiFiService("B000");
BLECharacteristic SSID_Char("B001");
BLECharacteristic PWD_Char("B002");
BLECharacteristic IP_Char("B003");

BLEService LEDService("A000");
BLECharacteristic LED1_Char("A001");
BLECharacteristic LED2_Char("A002");

// RTSP 相關變數
RTSP rtsp;
StreamIO videoStreamer(1, 1);

// 📡 當手機寫入 SSID
void ssidWriteCB(BLECharacteristic* chr, uint8_t connID) {
    String receivedSSID = chr->readString();
    Serial.print("📡 Received SSID: ");
    Serial.println(receivedSSID);
    receivedSSID.toCharArray(ssid, sizeof(ssid));
}

// 🔑 當手機寫入 Wi-Fi 密碼
void passwordWriteCB(BLECharacteristic* chr, uint8_t connID) {
    String receivedPWD = chr->readString();
    Serial.print("🔑 Received Password: ");
    Serial.println(receivedPWD);
    receivedPWD.toCharArray(password, sizeof(password));
    wifiConfigured = true;  // 設定 Wi-Fi 配置完成標誌
}

// 💡 LED 控制回調函數
void ledWriteCB(BLECharacteristic* chr, uint8_t connID) {
    uint8_t value = chr->readData8();
    if (chr->getUUID() == "A001") {  
        digitalWrite(LED1_PIN, value ? HIGH : LOW);
        Serial.println(value ? "💡 LED1 ON" : "💡 LED1 OFF");
    } else if (chr->getUUID() == "A002") {  
        digitalWrite(LED2_PIN, value ? HIGH : LOW);
        Serial.println(value ? "💡 LED2 ON" : "💡 LED2 OFF");
    }
}

// 📡 連接 Wi-Fi
void connectWiFi() {
    Serial.println("📡 嘗試連接 Wi-Fi...");
    WiFi.begin(ssid, password);

    int retries = 0;
    while (WiFi.status() != WL_CONNECTED && retries < 20) {
        delay(500);
        Serial.print(".");
        retries++;
    }

    if (WiFi.status() == WL_CONNECTED) {
        ip = WiFi.localIP();
        Serial.println("\n✅ Wi-Fi 連線成功！");
        Serial.print("📡 設備 IP: ");
        Serial.println(ip);
    } else {
        Serial.println("\n❌ Wi-Fi 連線失敗！");
        return;
    }
}

// 🎥 啟動 RTSP 影像串流
void startRTSPStream() {
    Serial.println("🎥 嘗試啟動 RTSP 影像串流...");

    VideoSetting configVID(VIDEO_VGA, 15, VIDEO_H264, 0);
    configVID.setBitrate(512 * 1024); // 512Kbps Bitrate
    configVID.setRotation(0);

    Serial.println("📡 設定 Camera 影像通道...");
    Camera.configVideoChannel(CHANNELVID, configVID);
    Camera.videoInit();
    delay(2000);

    int status = Camera.videostream_status(CHANNELVID);
    Serial.print("📷 Camera Stream 狀態: ");
    Serial.println(status);

    if (status != 1) {
        Serial.println("❌ Camera 初始化失敗！請檢查 Camera 連接狀態！");
        return;
    }
    Serial.println("✅ Camera 初始化成功！");

    Serial.println("📡 初始化 RTSP 伺服器...");
    rtsp.configVideo(configVID);
    rtsp.begin();   // 讓 RTSP 伺服器自己決定使用哪個埠
    delay(1000);

    // **獲取 RTSP 伺服器實際埠號**
    int actualRTSPPort = rtsp.getPort();
    Serial.print("✅ RTSP 伺服器實際埠號: ");
    Serial.println(actualRTSPPort);

    // 設定 RTSP 串流
    Serial.println("📡 嘗試啟動影像串流...");
    videoStreamer.registerInput(Camera.getStream(CHANNELVID));
    videoStreamer.registerOutput(rtsp);

    if (videoStreamer.begin() != 0) {
        Serial.println("❌ RTSP Stream 啟動失敗！");
        return;
    } else {
        Serial.println("✅ RTSP Stream 啟動成功！");
    }

    Serial.println("🎥 開啟 Camera 影像通道...");
    Camera.channelBegin(CHANNELVID);
    delay(1000);

    // **構建 RTSP URL**
    rtspURL = "rtsp://" + String(ip[0]) + "." + String(ip[1]) + "." + String(ip[2]) + "." + String(ip[3]) + ":" + String(actualRTSPPort) + "/live";
    Serial.print("📡 RTSP Stream URL: ");
    Serial.println(rtspURL);

    // 📡 **回傳 RTSP URL 給 App**
    sendRTSPUrl();
}

// 📡 BLE 發送 RTSP URL (分段傳輸)
void sendRTSPUrl() {
    Serial.println("📡 發送 RTSP URL...");

    size_t urlLength = rtspURL.length();
    size_t chunkSize = 20;  // BLE 最大 buffer 限制

    for (size_t i = 0; i < urlLength; i += chunkSize) {
        String chunk = rtspURL.substring(i, min(i + chunkSize, urlLength));

        Serial.print("📤 發送區塊: ");
        Serial.println(chunk);

        IP_Char.writeString(chunk);
        IP_Char.notify(0);
        delay(100);  // ✅ 讓 BLE 有時間處理，避免數據遺漏
    }

    Serial.println("✅ RTSP URL 傳輸完成！");
}

// 🔧 初始化 BLE
void setupBLE() {
    BLE.init();
    BLE.configServer(2);

    // 📡 設定 Wi-Fi 配置服務
    SSID_Char.setWriteProperty(true);
    SSID_Char.setWritePermissions(GATT_PERM_WRITE);
    SSID_Char.setWriteCallback(ssidWriteCB);
    PWD_Char.setWriteProperty(true);
    PWD_Char.setWritePermissions(GATT_PERM_WRITE);
    PWD_Char.setWriteCallback(passwordWriteCB);
    IP_Char.setReadProperty(true);
    IP_Char.setNotifyProperty(true);

    WiFiService.addCharacteristic(SSID_Char);
    WiFiService.addCharacteristic(PWD_Char);
    WiFiService.addCharacteristic(IP_Char);
    BLE.addService(WiFiService);

    // LED 控制服務
    LED1_Char.setWriteProperty(true);
    LED1_Char.setWritePermissions(GATT_PERM_WRITE);
    LED1_Char.setWriteCallback(ledWriteCB);
    LED2_Char.setWriteProperty(true);
    LED2_Char.setWritePermissions(GATT_PERM_WRITE);
    LED2_Char.setWriteCallback(ledWriteCB);

    LEDService.addCharacteristic(LED1_Char);
    LEDService.addCharacteristic(LED2_Char);
    BLE.addService(LEDService);

    BLE.beginPeripheral();
    Serial.println("📡 BLE 伺服器啟動，請用手機 App 連線");
}

// 🔧 設定函數
void setup() {
    Serial.begin(115200);
    pinMode(LED1_PIN, OUTPUT);
    pinMode(LED2_PIN, OUTPUT);
    setupBLE();
}

// 📡 主迴圈
void loop() {
    if (wifiConfigured) {
        wifiConfigured = false;
        connectWiFi();
        if (WiFi.status() == WL_CONNECTED) {
            startRTSPStream();
        }
    }
    delay(1000);
}
