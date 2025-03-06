import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class Page4 extends StatefulWidget {
  const Page4({Key? key}) : super(key: key);

  @override
  State<Page4> createState() => _Page4State();
}

class _Page4State extends State<Page4> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Page 4"),
        backgroundColor: Colors.blueAccent,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ✅ 大標題
          const Center(
            child: Text(
              "This is Page 4",
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

          // ✅ 折線圖 (Line Chart)
          const Text("Line Chart", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildLineChart(),
            ),
          ),

          const SizedBox(height: 40),

          // ✅ 圓餅圖 (Pie Chart)
          const Text("Pie Chart", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: _buildPieChart(),
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

  /// **折線圖 (Line Chart)**
  Widget _buildLineChart() {
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.blueAccent, width: 2),
        ),
        minX: 0,
        maxX: 6,
        minY: 0,
        maxY: 10,
        lineBarsData: [
          LineChartBarData(
            spots: const [
              FlSpot(0, 2),
              FlSpot(1, 5),
              FlSpot(2, 3),
              FlSpot(3, 7),
              FlSpot(4, 6),
              FlSpot(5, 9),
              FlSpot(6, 4),
            ],
            isCurved: true,
            color: Colors.blueAccent,
            barWidth: 4,
            isStrokeCapRound: true,
            belowBarData: BarAreaData(show: false),
          ),
        ],
      ),
    );
  }

  /// **圓餅圖 (Pie Chart)**
  Widget _buildPieChart() {
    return PieChart(
      PieChartData(
        sections: [
          PieChartSectionData(
            value: 40,
            color: Colors.blueAccent,
            title: '40%',
            radius: 50,
          ),
          PieChartSectionData(
            value: 30,
            color: Colors.green,
            title: '30%',
            radius: 50,
          ),
          PieChartSectionData(
            value: 20,
            color: Colors.orange,
            title: '20%',
            radius: 50,
          ),
          PieChartSectionData(
            value: 10,
            color: Colors.red,
            title: '10%',
            radius: 50,
          ),
        ],
        sectionsSpace: 2,
        centerSpaceRadius: 30,
      ),
    );
  }
}
