import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '스웨덴어 단어장',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const WordHomePage(),
    );
  }
}

class WordHomePage extends StatefulWidget {
  const WordHomePage({super.key});

  @override
  State<WordHomePage> createState() => _WordHomePageState();
}

class _WordHomePageState extends State<WordHomePage> {
  final TextEditingController _controller = TextEditingController();
  String _translatedText = '';

  // 바탕화면 위젯 데이터 업데이트
  Future<void> _updateWidget(String word, String meaning) async {
    await HomeWidget.saveWidgetData<String>('widget_word', word);
    await HomeWidget.saveWidgetData<String>('widget_meaning', meaning);
    await HomeWidget.updateWidget(
      name: 'WordWidgetProvider',
      androidName: 'WordWidgetProvider',
    );
  }

  // 구글 번역 API 연동 (스웨덴어 -> 한국어)
  Future<void> _translate(String text) async {
    if (text.trim().isEmpty) return;
    
    final url = Uri.parse(
        'https://translate.googleapis.com/translate_a/single?client=gtx&sl=sv&tl=ko&dt=t&q=${Uri.encodeComponent(text)}');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data[0][0][0];
        
        setState(() {
          _translatedText = result;
        });

        // 번역된 단어를 바탕화면 위젯으로 전송
        await _updateWidget(text, result);
      }
    } catch (e) {
      setState(() {
        _translatedText = '번역 중 오류가 발생했습니다.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('스웨덴어 단어장 & 위젯'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '스웨덴어 단어 입력 (예: Hej)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => _translate(_controller.text),
                child: const Text('번역 & 위젯 업데이트', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  const Text('한국어 뜻', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text(
                    _translatedText.isEmpty ? '단어를 입력하고 버튼을 누르세요' : _translatedText,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
