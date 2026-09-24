import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
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
      title: '스웨덴어 학습 & 위젯',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainNavigationPage(),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. 공통 발음 듣기 (TTS) 헬퍼
// ---------------------------------------------------------------------------
class TtsService {
  static final FlutterTts _tts = FlutterTts();

  static Future<void> speak(String text) async {
    await _tts.setLanguage("sv-SE"); // 스웨덴어 언어 설정
    await _tts.setSpeechRate(0.45);  // 약간 천천히 읽기
    await _tts.setPitch(1.0);
    await _tts.speak(text);
  }
}

// ---------------------------------------------------------------------------
// 2. 단어 데이터 모델 & DB 헬퍼
// ---------------------------------------------------------------------------
class WordItem {
  final int? id;
  final String word;    // 한국어
  final String meaning; // 스웨덴어

  WordItem({this.id, required this.word, required this.meaning});

  Map<String, dynamic> toMap() => {'id': id, 'word': word, 'meaning': meaning};

  factory WordItem.fromMap(Map<String, dynamic> map) {
    return WordItem(
      id: map['id'] as int?,
      word: map['word'] as String,
      meaning: map['meaning'] as String,
    );
  }
}

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
    return await openDatabase(pathString, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE words (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          word TEXT NOT NULL,
          meaning TEXT NOT NULL
        )
      ''');
    });
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

// ---------------------------------------------------------------------------
// 3. 네비게이션 메인 페이지 (하단 2개 탭 구성)
// ---------------------------------------------------------------------------
class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    WordMainPage(),
    GrammarPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.translate),
            label: '번역 & 단어장',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book),
            label: '스웨덴어 문법',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 탭 1: 한국어 ➔ 스웨덴어 번역 & 단어장 & 위젯 연동
// ---------------------------------------------------------------------------
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

  Future<void> _loadWordList() async {
    final list = await DatabaseHelper.instance.getAllWords();
    setState(() {
      _wordList = list;
    });
  }

  Future<void> _updateWidget(String korean, String swedish) async {
    await HomeWidget.saveWidgetData<String>('widget_word', swedish);
    await HomeWidget.saveWidgetData<String>('widget_meaning', korean);
    await HomeWidget.updateWidget(
      name: 'WordWidgetProvider',
      androidName: 'WordWidgetProvider',
    );
  }

  Future<void> _translateAndSave() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    final url = Uri.parse(
        'https://translate.googleapis.com/translate_a/single?client=gtx&sl=ko&tl=sv&dt=t&q=${Uri.encodeComponent(text)}');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data[0][0][0] as String;

        setState(() {
          _translatedText = result;
        });

        await DatabaseHelper.instance.insertWord(
          WordItem(word: text, meaning: result),
        );

        await _updateWidget(text, result);
        await _loadWordList();

        // 번역 직후 발음 재생
        await TtsService.speak(result);

        _controller.clear();
      }
    } catch (e) {
      setState(() {
        _translatedText = '번역 오류가 발생했습니다.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteWord(int id) async {
    await DatabaseHelper.instance.deleteWord(id);
    await _loadWordList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('한국어 ➔ 스웨덴어 번역 & 위젯'),
        centerTitle: true,
        backgroundColor: Colors.blue.shade100,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '한국어 입력 (위젯에 스웨덴어로 표시)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: '한국어 입력 (예: 안녕하세요)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onSubmitted: (_) => _translateAndSave(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _translateAndSave,
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
            if (_translatedText.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('스웨덴어 번역 결과',
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
                    IconButton(
                      icon: const Icon(Icons.volume_up, color: Colors.blue, size: 30),
                      onPressed: () => TtsService.speak(_translatedText),
                      tooltip: '발음 듣기',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '저장된 단어장 (${_wordList.length}개)',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadWordList,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _wordList.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text('저장된 단어가 없습니다.',
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
                            item.meaning, // 스웨덴어
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            item.word, // 한국어
                            style: const TextStyle(fontSize: 15, color: Colors.black54),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.volume_up, color: Colors.blue),
                                tooltip: '발음 듣기',
                                onPressed: () => TtsService.speak(item.meaning),
                              ),
                              IconButton(
                                icon: const Icon(Icons.widgets_outlined, color: Colors.indigo),
                                tooltip: '위젯으로 설정',
                                onPressed: () async {
                                  await _updateWidget(item.word, item.meaning);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('\'${item.meaning}\' 단어가 위젯에 설정되었습니다.')),
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

// ---------------------------------------------------------------------------
// 탭 2: 스웨덴어 기초 문법 가이드 (발음 재생 기능 지원)
// ---------------------------------------------------------------------------
class GrammarPage extends StatelessWidget {
  const GrammarPage({super.key});

  Widget _buildGrammarCard({
    required String title,
    required String description,
    required List<Map<String, String>> examples,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
            const SizedBox(height: 6),
            Text(description, style: const TextStyle(fontSize: 14, color: Colors.black87)),
            const Divider(height: 20),
            Column(
              children: examples.map((ex) {
                final swedish = ex['sv'] ?? '';
                final korean = ex['ko'] ?? '';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(swedish,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600)),
                            Text(korean,
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.grey)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.volume_up, color: Colors.blue),
                        onPressed: () => TtsService.speak(swedish),
                        tooltip: '발음 듣기',
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('스웨덴어 기초 문법 학습'),
        centerTitle: true,
        backgroundColor: Colors.blue.shade100,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildGrammarCard(
            title: '1. 인칭 독립 동사 (현재형)',
            description: '주어(나, 너, 그)에 따라 동사가 변하지 않으며, 현재형은 원형 끝에 -r 또는 -er을 붙입니다.',
            examples: [
              {'sv': 'Jag talar svenska.', 'ko': '나는 스웨덴어를 말한다.'},
              {'sv': 'Du äter ett äpple.', 'ko': '너는 사과를 먹는다.'},
              {'sv': 'Han dricker kaffe.', 'ko': '그는 커피를 마신다.'},
            ],
          ),
          _buildGrammarCard(
            title: '2. V2 어순 법칙 (동사는 2번째)',
            description: '문두에 시간/장소가 먼저 오면 동사(V)가 무조건 2번째 자리를 유지하고 주어와 위치가 바뀝니다.',
            examples: [
              {'sv': 'Jag studerar idag.', 'ko': '나는 오늘 공부한다. (기본어순)'},
              {'sv': 'Idag studerar jag.', 'ko': '오늘 나는 공부한다. (동사 studerar가 2번째)'},
            ],
          ),
          _buildGrammarCard(
            title: '3. 명사의 성별 (en / ett)',
            description: '명사는 en(80%)과 ett(20%)로 나뉘며, 정관사(~그)는 단어 뒤에 붙습니다.',
            examples: [
              {'sv': 'en hund -> hunden', 'ko': '개 한 마리 -> 그 개'},
              {'sv': 'ett hus -> huset', 'ko': '집 한 채 -> 그 집'},
            ],
          ),
          _buildGrammarCard(
            title: '4. 필수 일상 회화 표현',
            description: '자주 쓰이는 기본 인사와 필수 회화 표현입니다.',
            examples: [
              {'sv': 'Hej!', 'ko': '안녕하세요!'},
              {'sv': 'Tack så mycket.', 'ko': '정말 감사합니다.'},
              {'sv': 'Vad heter du?', 'ko': '이름이 무엇인가요?'},
              {'sv': 'Jag heter Anna.', 'ko': '제 이름은 안나입니다.'},
              {'sv': 'Ja / Nej', 'ko': '네 / 아니요'},
            ],
          ),
        ],
      ),
    );
  }
}
