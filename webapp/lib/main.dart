import 'package:flutter/material.dart';
import 'pages/home_page.dart'; // ✅ 確保導入 HomePage

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // ✅ 隱藏 Debug 標誌
      title: 'My Flutter App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(), // ✅ 設定 HomePage 為主畫面
    );
  }
}
