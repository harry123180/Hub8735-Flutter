#include "WiFi.h"
#include "StreamIO.h"
#include "VideoStream.h"
#include "RTSP.h"

// 硬體與 RTSP 設定
#define CHANNELVID  0   // RTSP 影像串流通道
#define RTSP_PORT 554  // RTSP 服務埠
String rtspURL = "";

// Wi-Fi 設定
char ssid[] = "TP-Link_BDC5";       // ✅ 替換為你的 Wi-Fi SSID
const char* password = "42887416"; // ✅ 替換為你的 Wi-Fi 密碼
IPAddress ip;

// RTSP 相關變數
RTSP rtsp;
StreamIO videoStreamer(1, 1);

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
        while (true); // Wi-Fi 連線失敗則停止執行
    }
}

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

    // 顯示 RTSP URL
    rtspURL = "rtsp://" + String(ip[0]) + "." + String(ip[1]) + "." + String(ip[2]) + "." + String(ip[3]) + ":" + String(actualRTSPPort) + "/live";
    Serial.print("📡 RTSP Stream URL: ");
    Serial.println(rtspURL);
}


void setup() {
    Serial.begin(115200);
    Serial.println("🚀 RTSP 測試初始化中...");

    connectWiFi();  // 連接 Wi-Fi
    delay(2000);

    startRTSPStream();  // 啟動 RTSP
}

void loop() {
    // Do nothing, RTSP 會持續運行
}
