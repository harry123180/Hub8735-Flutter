import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class Page3 extends StatefulWidget {
  const Page3({Key? key}) : super(key: key);

  @override
  State<Page3> createState() => _Page3State();
}

class _Page3State extends State<Page3> {
  DateTime selectedDate = DateTime.now(); // ✅ 預設當前日期

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Page 3"),
        backgroundColor: Colors.blueAccent,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ✅ 大標題
          const Center(
            child: Text(
              "This is Page 3",
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

          // ✅ 顯示當前選擇的日期
          Text(
            "Selected Date: ${_formatDate(selectedDate)}",
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
          ),

          const SizedBox(height: 20),

          // ✅ 標準日期選擇器
          _buildDatePickerButton(
            label: "Standard Date Picker",
            onPressed: _showStandardDatePicker,
          ),

          // ✅ iOS 風格日期選擇器
          _buildDatePickerButton(
            label: "iOS Style Picker",
            onPressed: _showIOSDatePicker,
          ),

          // ✅ 動畫風格日期選擇器
          
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

  /// **日期選擇器按鈕**
  Widget _buildDatePickerButton({required String label, required VoidCallback onPressed}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueAccent,
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
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// **標準版 DatePicker**
  Future<void> _showStandardDatePicker() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2050),
    );

    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  /// **iOS 風格 DatePicker**
  void _showIOSDatePicker() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext builder) {
        return SizedBox(
          height: 250,
          child: CupertinoDatePicker(
            initialDateTime: selectedDate,
            mode: CupertinoDatePickerMode.date,
            minimumYear: 2000,
            maximumYear: 2050,
            onDateTimeChanged: (DateTime newDate) {
              setState(() {
                selectedDate = newDate;
              });
            },
          ),
        );
      },
    );
  }


  
  /// **格式化日期顯示**
  String _formatDate(DateTime date) {
    return "${date.year}-${date.month}-${date.day}";
  }
}
