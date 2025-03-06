import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class Page5 extends StatefulWidget {
  const Page5({Key? key}) : super(key: key);

  @override
  State<Page5> createState() => _Page5State();
}

class _Page5State extends State<Page5> {
  List<ScanResult> scanResults = [];
  BluetoothDevice? connectedDevice;
  List<BluetoothService> services = [];
  BluetoothCharacteristic? led1Characteristic;
  BluetoothCharacteristic? led2Characteristic;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  /// **開始掃描 BLE 設備**
  void _startScan() async {
    scanResults.clear();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    FlutterBluePlus.scanResults.listen((List<ScanResult> results) {
      setState(() {
        scanResults = results;
      });
    });
  }

  /// **連接 BLE 設備**
  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      connectedDevice = device;
    });

    await device.connect();
    print("✅ 已連接: ${device.name}");

    // **發現 GATT 服務**
    services = await device.discoverServices();
    _findCharacteristics(); // 找 LED 控制的特性
    setState(() {});
  }

  /// **查找 LED 控制的 Characteristics**
  void _findCharacteristics() {
    for (var service in services) {
      for (var characteristic in service.characteristics) {
        if (characteristic.uuid.toString().toUpperCase() == "A001") {
          led1Characteristic = characteristic;
          print("✅ 找到 LED1 控制特性: ${characteristic.uuid}");
        } else if (characteristic.uuid.toString().toUpperCase() == "A002") {
          led2Characteristic = characteristic;
          print("✅ 找到 LED2 控制特性: ${characteristic.uuid}");
        }
      }
    }
  }

  /// **發送指令來開關 LED**
  Future<void> _sendCommand(BluetoothCharacteristic? characteristic, int value) async {
    if (characteristic == null) return;
    List<int> command = [value];  // 0x00 (關閉) or 0x01 (開啟)
    await characteristic.write(command);
    print("📤 發送數據: ${command} 到 UUID: ${characteristic.uuid}");
  }

  /// **顯示 LED 控制按鈕**
  Widget _buildLEDControls() {
    return Column(
      children: [
        _buildLEDButton(led1Characteristic, "LED 1"),
        _buildLEDButton(led2Characteristic, "LED 2"),
      ],
    );
  }

  /// **建立 LED 控制按鈕**
  Widget _buildLEDButton(BluetoothCharacteristic? characteristic, String label) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: characteristic == null ? null : () => _sendCommand(characteristic, 0x01),  // 開啟 LED
          child: Text("$label ON"),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: characteristic == null ? null : () => _sendCommand(characteristic, 0x00),  // 關閉 LED
          child: Text("$label OFF"),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Page 5 - BLE LED 控制")),
      body: Column(
        children: [
          // **返回按鈕**
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Go Back"),
          ),
          const SizedBox(height: 10),

          // **顯示設備掃描列表**
          Expanded(
            child: connectedDevice == null
                ? ListView.builder(
                    itemCount: scanResults.length,
                    itemBuilder: (context, index) {
                      final device = scanResults[index].device;
                      return ListTile(
                        title: Text(device.name.isNotEmpty ? device.name : "未知設備"),
                        subtitle: Text(device.id.toString()),
                        trailing: ElevatedButton(
                          onPressed: () => _connectToDevice(device),
                          child: const Text("連接"),
                        ),
                      );
                    },
                  )
                : _buildLEDControls(),
          ),
        ],
      ),
    );
  }
}
