import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const WordMainPage(),
    );
  }
}

// 1. 단어 데이터 모델
class WordItem {
  final int? id;
  final String word;
  final String meaning;

  WordItem({this.id, required this.word, required this.meaning});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'word': word,
      'meaning': meaning,
    };
  }

  factory WordItem.fromMap(Map<String, dynamic> map) {
    return WordItem(
      id: map['id'] as int?,
      word: map['word'] as String,
      meaning: map['meaning'] as String,
    );
  }
}

// 2. sqflite 로컬 데이터베이스 헬퍼
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('words.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final pathString = p.join(dbPath, filePath);

    return await openDatabase(
      pathString,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE words (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word TEXT NOT NULL,
        meaning TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertWord(WordItem wordItem) async {
    final db = await instance.database;
    return await db.insert('words', wordItem.toMap());
  }

  Future<List<WordItem>> getAllWords() async {
    final db = await instance.database;
    final result = await db.query('words', orderBy: 'id DESC');
    return result.map((json) => WordItem.fromMap(json)).toList();
  }

  Future<int> deleteWord(int id) async {
    final db = await instance.database;
    return await db.delete('words', where: 'id = ?', whereArgs: [id]);
  }
}

// 3. 메인 화면 (번역 + 단어장 + 위젯)
class WordMainPage extends StatefulWidget {
  const WordMainPage({super.key});

  @override
  State<WordMainPage> createState() => _WordMainPageState();
}

class _WordMainPageState extends State<WordMainPage> {
  final TextEditingController _controller = TextEditingController();
  String _translatedText = '';
  List<WordItem> _wordList = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadWordList();
  }

  // DB에서 저장된 단어장 목록 불러오기
  Future<void> _loadWordList() async {
    final list = await DatabaseHelper.instance.getAllWords();
    setState(() {
      _wordList = list;
    });
  }

  // 안드로이드 바탕화면 위젯 업데이트
  Future<void> _updateWidget(String word, String meaning) async {
    await HomeWidget.saveWidgetData<String>('widget_word', word);
    await HomeWidget.saveWidgetData<String>('widget_meaning', meaning);
    await HomeWidget.updateWidget(
      name: 'WordWidgetProvider',
      androidName: 'WordWidgetProvider',
    );
  }

  // 구글 번역 API 호출 및 DB 저장
  Future<void> _translateAndSave() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    final url = Uri.parse(
        'https://translate.googleapis.com/translate_a/single?client=gtx&sl=sv&tl=ko&dt=t&q=${Uri.encodeComponent(text)}');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data[0][0][0] as String;

        setState(() {
          _translatedText = result;
        });

        // 1) sqflite DB에 저장
        await DatabaseHelper.instance.insertWord(
          WordItem(word: text, meaning: result),
        );

        // 2) 바탕화면 위젯 업데이트
        await _updateWidget(text, result);

        // 3) 단어장 목록 업데이트
        await _loadWordList();

        _controller.clear();
      }
    } catch (e) {
      setState(() {
        _translatedText = '번역 중 오류가 발생했습니다.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 단어 삭제
  Future<void> _deleteWord(int id) async {
    await DatabaseHelper.instance.deleteWord(id);
    await _loadWordList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('스웨덴어 단어장 & 번역기'),
        centerTitle: true,
        backgroundColor: Colors.blue.shade100,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAlignment.start,
          children: [
            // 번역 및 저장 입력 영역
            const Text(
              '스웨덴어 단어 번역 & 단어장 저장',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: '스웨덴어 단어 입력 (예: Hej, Tack)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onSubmitted: (_) => _translateAndSave(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _translateAndSave,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('번역 & 저장'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 번역 결과 영역
            if (_translatedText.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  children: [
                    const Text('최근 번역 결과 (위젯에 등록됨)',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      _translatedText,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            const Divider(height: 32),

            // sqflite 단어장 목록
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '내 단어장 목록 (${_wordList.length}개)',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadWordList,
                  tooltip: '목록 새로고침',
                ),
              ],
            ),
            const SizedBox(height: 8),

            _wordList.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text('저장된 단어가 없습니다.\n위에서 단어를 입력하여 저장해 보세요!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _wordList.length,
                    itemBuilder: (context, index) {
                      final item = _wordList[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text(
                            item.word,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            item.meaning,
                            style: const TextStyle(fontSize: 16, color: Colors.black87),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.widgets_outlined, color: Colors.blue),
                                tooltip: '위젯으로 설정',
                                onPressed: () async {
                                  await _updateWidget(item.word, item.meaning);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('\'${item.word}\' 단어가 바탕화면 위젯에 설정되었습니다.')),
                                    );
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                tooltip: '삭제',
                                onPressed: () => _deleteWord(item.id!),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
