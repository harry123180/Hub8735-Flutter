import 'package:flutter/material.dart';
import 'page_1.dart'; // ✅ 導入 Page1
import 'page_2.dart'; // ✅ 新增導入 Page2
import 'page_3.dart'; // ✅ 新增導入 Page3
import 'page_4.dart'; // ✅ 新增導入 Page4
import 'page_5.dart'; // ✅ 新增導入 Page5
class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Home Page"),
        backgroundColor: Colors.blueAccent,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildButton(
              context,
              label: "Go to Page 1",
              color: Colors.blue,
              onPressed: () {
                // TODO: 未來導航到 Page 1
                print("Navigate to Page 1");
                 Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const Page1()), // ✅ 導航到 Page1
                );
              },
            ),
            const SizedBox(height: 16),
            _buildButton(
              context,
              label: "Go to Page 2",
              color: Colors.green,
              onPressed: () {
                // TODO: 未來導航到 Page 2
                print("Navigate to Page 2");
                  Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const Page2()), // ✅ 導航到 Page2
                );
              },
            ),
            const SizedBox(height: 16),
            _buildButton(
              context,
              label: "Go to Page 3",
              color: Colors.orange,
              onPressed: () {
                // TODO: 未來導航到 Page 3
                print("Navigate to Page 3");
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const Page3()), // ✅ 導航到 Page3
                );
              },
            ),
            const SizedBox(height: 16),
            _buildButton(
              context,
              label: "Go to Page 4",
              color: Colors.purple,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const Page4()), // ✅ 導航到 Page4
                );
              },
            ),
            const SizedBox(height: 16),
            _buildButton(
              context,
              label: "Go to Page 5",
              color: Colors.teal,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const Page5()), // ✅ 導航到 Page5
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// **統一按鈕樣式**
  Widget _buildButton(BuildContext context,
      {required String label, required Color color, required VoidCallback onPressed}) {
    return SizedBox(
      width: 200, // 固定按鈕寬度
      height: 50, // 固定按鈕高度
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color, // 設定按鈕顏色
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), // 設定圓角
          ),
          elevation: 5, // 設定陰影效果
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white, // 讓文字顏色固定為白色
          ),
        ),
      ),
    );
  }
}
