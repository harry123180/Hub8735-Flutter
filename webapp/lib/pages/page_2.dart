import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class Page2 extends StatefulWidget {
  const Page2({Key? key}) : super(key: key);

  @override
  State<Page2> createState() => _Page2State();
}

class _Page2State extends State<Page2> {
  bool _standardSwitch = false;
  bool _iosSwitch = false;
  bool _animatedSwitch = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Page 2"),
        backgroundColor: Colors.blueAccent,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ✅ 大標題
          const Center(
            child: Text(
              "This is Page 2",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 40),

          // ✅ Go Back 按鈕
          _buildButton(
            label: "Go Back",
            color: Colors.redAccent,
            onPressed: () {
              Navigator.pop(context); // ✅ 返回 HomePage
            },
          ),

          const SizedBox(height: 40),

          // ✅ 標準 Switch
          _buildSwitchTile(
            label: "Standard Switch",
            value: _standardSwitch,
            onChanged: (value) {
              setState(() {
                _standardSwitch = value;
              });
            },
          ),

          // ✅ iOS 風格 Switch
          _buildSwitchTile(
            label: "iOS Style Switch",
            value: _iosSwitch,
            isIOS: true,
            onChanged: (value) {
              setState(() {
                _iosSwitch = value;
              });
            },
          ),

          // ✅ 帶動畫的 Switch
          _buildSwitchTile(
            label: "Animated Switch",
            value: _animatedSwitch,
            isAnimated: true,
            onChanged: (value) {
              setState(() {
                _animatedSwitch = value;
              });
            },
          ),
        ],
      ),
    );
  }

  /// **統一按鈕樣式**
  Widget _buildButton({required String label, required Color color, required VoidCallback onPressed}) {
    return SizedBox(
      width: 200,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 5,
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// **統一 Switch 設計**
  Widget _buildSwitchTile({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isIOS = false,
    bool isAnimated = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),

          // ✅ 根據類型顯示不同 Switch
          isIOS
              ? CupertinoSwitch(
                  value: value,
                  activeColor: Colors.green,
                  onChanged: onChanged,
                )
              : isAnimated
                  ? AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 60,
                      height: 30,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        color: value ? Colors.blue : Colors.grey.shade400,
                      ),
                      child: Stack(
                        children: [
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            left: value ? 30 : 0,
                            right: value ? 0 : 30,
                            child: GestureDetector(
                              onTap: () => onChanged(!value),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 3,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Switch(
                      value: value,
                      activeColor: Colors.blue,
                      onChanged: onChanged,
                    ),

          // ✅ 顯示當前狀態 (1 / 0)
          Text(value ? "1" : "0", style: const TextStyle(fontSize: 20)),
        ],
      ),
    );
  }
}
