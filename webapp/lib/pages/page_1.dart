import 'package:flutter/material.dart';

class Page1 extends StatefulWidget {
  const Page1({Key? key}) : super(key: key);

  @override
  State<Page1> createState() => _Page1State();
}

class _Page1State extends State<Page1> {
  double _sliderValue = 50; // ✅ 預設滑動條數值

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Page 1"),
        backgroundColor: Colors.blueAccent,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ✅ 大標題
          const Center(
            child: Text(
              "This is Page 1",
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

          // ✅ 滑動條數值顯示
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: 1.0,
            child: Text(
              "Slider Value: ${_sliderValue.toStringAsFixed(1)}",
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ✅ 滑動條 (Slider)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.blueAccent,
                inactiveTrackColor: Colors.grey.shade300,
                trackHeight: 6.0,
                thumbColor: Colors.blue,
                overlayColor: Colors.blue.withOpacity(0.2),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
              ),
              child: Slider(
                value: _sliderValue,
                min: 0,
                max: 100,
                divisions: 100,
                label: _sliderValue.toStringAsFixed(1), // ✅ 顯示數值標籤
                onChanged: (value) {
                  setState(() {
                    _sliderValue = value; // ✅ 即時更新數值
                  });
                },
              ),
            ),
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
}
