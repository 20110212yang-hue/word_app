import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' hide Context, context;
import 'package:sqflite/sqflite.dart';

void main() {
  runApp(const WordApp());
}

enum SearchLanguage { swedish, korean, unknown }

class Word {
  final int? id;
  final String word;
  final String meaning;

  const Word({
    this.id,
    required this.word,
    required this.meaning,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'word': word,
        'meaning': meaning,
      };

  factory Word.fromMap(Map<String, dynamic> map) => Word(
        id: map['id'] as int?,
        word: map['word'] as String,
        meaning: map['meaning'] as String,
      );
}

class TranslationResult {
  final String word;
  final String meaning;
  final SearchLanguage sourceLanguage;

  const TranslationResult({
    required this.word,
    required this.meaning,
    required this.sourceLanguage,
  });
}

class TranslationApiService {
  static const _baseUrl = 'https://api.mymemory.translated.net/get';

  static Future<String> _translate(String text, String langPair) async {
    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'q': text,
        'langpair': langPair,
      },
    );

    final response = await http.get(uri).timeout(
      const Duration(seconds: 10),
    );

    if (response.statusCode != 200) {
      throw Exception('서버 오류 (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final status = data['responseStatus'] as int? ?? 0;

    if (status != 200) {
      throw Exception('번역 결과를 찾을 수 없습니다.');
    }

    final responseData = data['responseData'] as Map<String, dynamic>?;
    final translatedText =
        responseData?['translatedText'] as String? ?? '';

    if (translatedText.isEmpty) {
      throw Exception('번역 결과가 비어 있습니다.');
    }

    return translatedText.trim();
  }

  static Future<TranslationResult> translate(
    String query,
    SearchLanguage sourceLanguage,
  ) async {
    switch (sourceLanguage) {
      case SearchLanguage.korean:
        final swedish = await _translate(query, 'ko|sv');
        return TranslationResult(
          word: swedish,
          meaning: query,
          sourceLanguage: SearchLanguage.korean,
        );
      case SearchLanguage.swedish:
        final korean = await _translate(query, 'sv|ko');
        return TranslationResult(
          word: query,
          meaning: korean,
          sourceLanguage: SearchLanguage.swedish,
        );
      case SearchLanguage.unknown:
        throw Exception('지원하지 않는 검색어입니다.');
    }
  }
}

class WordDatabase {
  static Database? _database;

  static const List<Word> sampleWords = [
    Word(word: 'Hej', meaning: '안녕하세요'),
    Word(word: 'Tack', meaning: '감사합니다'),
    Word(word: 'Ja', meaning: '네'),
    Word(word: 'Nej', meaning: '아니요'),
    Word(word: 'Ett äpple', meaning: '사과'),
    Word(word: 'En bok', meaning: '책'),
  ];

  static Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'words.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE words (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            word TEXT NOT NULL,
            meaning TEXT NOT NULL
          )
        ''');
      },
    );
  }

  static Future<void> seedSampleWordsIfEmpty() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM words'),
    );

    if (count != null && count > 0) return;

    for (final word in sampleWords) {
      await db.insert('words', word.toMap());
    }
  }

  static Future<List<Word>> getWords() async {
    final db = await database;
    final maps = await db.query('words', orderBy: 'id ASC');
    return maps.map(Word.fromMap).toList();
  }

  static Future<bool> wordExists(String word) async {
    final db = await database;
    final maps = await db.query(
      'words',
      where: 'LOWER(word) = ?',
      whereArgs: [word.toLowerCase()],
      limit: 1,
    );
    return maps.isNotEmpty;
  }

  static Future<int> insertWord(Word word) async {
    final db = await database;
    return db.insert('words', word.toMap());
  }

  static Future<int> deleteWord(int id) async {
    final db = await database;
    return db.delete('words', where: 'id = ?', whereArgs: [id]);
  }
}

class WordApp extends StatelessWidget {
  const WordApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '스웨덴어 단어장',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const WordListPage(),
    );
  }
}

class WordListPage extends StatefulWidget {
  const WordListPage({super.key});

  @override
  State<WordListPage> createState() => _WordListPageState();
}

class _WordListPageState extends State<WordListPage> {
  List<Word> _words = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  TranslationResult? _apiResult;
  bool _isApiLoading = false;
  String? _apiError;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  SearchLanguage _detectLanguage(String text) {
    final hasKorean = RegExp(r'[가-힣]').hasMatch(text);
    final hasLatin = RegExp(r'[a-zA-ZåäöÅÄÖ]').hasMatch(text);

    if (hasKorean && !hasLatin) return SearchLanguage.korean;
    if (hasLatin && !hasKorean) return SearchLanguage.swedish;
    if (hasKorean) return SearchLanguage.korean;
    if (hasLatin) return SearchLanguage.swedish;
    return SearchLanguage.unknown;
  }

  List<Word> get _filteredWords {
    if (_searchQuery.isEmpty) return _words;

    final query = _searchQuery.toLowerCase();
    return _words.where((word) {
      return word.word.toLowerCase().contains(query) ||
          word.meaning.toLowerCase().contains(query);
    }).toList();
  }

  bool get _shouldFetchFromApi {
    if (_searchQuery.length < 2) return false;
    if (_detectLanguage(_searchQuery) == SearchLanguage.unknown) return false;
    return _filteredWords.isEmpty;
  }

  Future<void> _loadWords() async {
    setState(() => _isLoading = true);
    await WordDatabase.seedSampleWordsIfEmpty();
    final words = await WordDatabase.getWords();
    setState(() {
      _words = words;
      _isLoading = false;
    });
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    setState(() {
      _searchQuery = query;
      _apiResult = null;
      _apiError = null;
    });

    _debounceTimer?.cancel();

    if (!_shouldFetchFromApi) {
      setState(() => _isApiLoading = false);
      return;
    }

    setState(() => _isApiLoading = true);

    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      _fetchTranslation(query);
    });
  }

  Future<void> _fetchTranslation(String query) async {
    final language = _detectLanguage(query);

    try {
      final result = await TranslationApiService.translate(query, language);
      if (!mounted || _searchQuery != query) return;

      setState(() {
        _apiResult = result;
        _apiError = null;
        _isApiLoading = false;
      });
    } catch (e) {
      if (!mounted || _searchQuery != query) return;

      setState(() {
        _apiResult = null;
        _apiError = e.toString().replaceFirst('Exception: ', '');
        _isApiLoading = false;
      });
    }
  }

  void _clearSearch() {
    _debounceTimer?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _apiResult = null;
      _apiError = null;
      _isApiLoading = false;
    });
  }

  Future<void> _addApiResultToDatabase() async {
    if (_apiResult == null) return;

    final exists = await WordDatabase.wordExists(_apiResult!.word);
    if (exists) {
      _showSnackBar('이미 단어장에 등록된 단어입니다.');
      return;
    }

    await WordDatabase.insertWord(
      Word(word: _apiResult!.word, meaning: _apiResult!.meaning),
    );
    await _loadWords();
    _showSnackBar('"${_apiResult!.word}" 단어가 단어장에 저장되었습니다.');
  }

  Future<void> _showAddWordDialog() async {
    final wordController = TextEditingController();
    final meaningController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('스웨덴어 단어 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: wordController,
              decoration: const InputDecoration(
                labelText: '스웨덴어 단어',
                hintText: '예: Hej, Tack, äpple (å, ä, ö 입력 가능)',
                helperText: '스웨덴어 특수문자 å, ä, ö 를 사용할 수 있습니다.',
              ),
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.text,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: meaningController,
              decoration: const InputDecoration(
                labelText: '한국어 뜻',
                hintText: '예: 안녕하세요',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('추가'),
          ),
        ],
      ),
    );

    if (result != true) return;

    final word = wordController.text.trim();
    final meaning = meaningController.text.trim();

    if (word.isEmpty || meaning.isEmpty) {
      _showSnackBar('스웨덴어 단어와 한국어 뜻을 모두 입력해 주세요.');
      return;
    }

    final exists = await WordDatabase.wordExists(word);
    if (exists) {
      _showSnackBar('이미 단어장에 등록된 단어입니다.');
      return;
    }

    await WordDatabase.insertWord(Word(word: word, meaning: meaning));
    await _loadWords();
    _showSnackBar('단어가 추가되었습니다.');
  }

  Future<void> _showDeleteDialog(Word word) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('단어 삭제'),
        content: Text('"${word.word}" 단어를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (result != true || word.id == null) return;

    await WordDatabase.deleteWord(word.id!);
    await _loadWords();
    _showSnackBar('단어가 삭제되었습니다.');
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _translationDirectionLabel(SearchLanguage source) {
    return source == SearchLanguage.korean
        ? '한국어 → 스웨덴어'
        : '스웨덴어 → 한국어';
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SearchBar(
        controller: _searchController,
        hintText: '스웨덴어 또는 한국어 검색 (양방향)',
        leading: const Icon(Icons.search),
        trailing: [
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearSearch,
              tooltip: '검색어 지우기',
            ),
        ],
        onChanged: _onSearchChanged,
        elevation: WidgetStateProperty.all(1),
      ),
    );
  }

  Widget _buildApiResultCard() {
    if (!_shouldFetchFromApi && !_isApiLoading && _apiError == null) {
      return const SizedBox.shrink();
    }

    if (_isApiLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    '"$_searchQuery" 번역 중...',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_apiError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _apiError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_apiResult == null) return const SizedBox.shrink();

    final alreadyExists = _words.any(
      (w) => w.word.toLowerCase() == _apiResult!.word.toLowerCase(),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.translate,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'API 번역 결과 (${_translationDirectionLabel(_apiResult!.sourceLanguage)})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _apiResult!.word,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _apiResult!.meaning,
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: alreadyExists ? null : _addApiResultToDatabase,
                  icon: Icon(alreadyExists ? Icons.check : Icons.bookmark_add),
                  label: Text(
                    alreadyExists ? '이미 단어장에 있음' : '내 단어장에 저장',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyBody() {
    if (_words.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '등록된 단어가 없습니다.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              '검색창에 단어를 입력하거나 + 버튼으로 추가해 보세요.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            '"$_searchQuery" 검색 결과가 없습니다.',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            '단어장에 없는 단어는 API로 자동 번역합니다.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _clearSearch,
            child: const Text('검색어 지우기'),
          ),
        ],
      ),
    );
  }

  Widget _buildWordList() {
    final filteredWords = _filteredWords;
    final showApiSection = _shouldFetchFromApi || _isApiLoading || _apiError != null;

    return Column(
      children: [
        _buildSearchBar(),
        if (showApiSection) _buildApiResultCard(),
        if (_searchQuery.isNotEmpty && filteredWords.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '내 단어장 (${filteredWords.length}개)',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        Expanded(
          child: filteredWords.isEmpty && !showApiSection
              ? _buildEmptyBody()
              : filteredWords.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: filteredWords.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final word = filteredWords[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            child: Text(
                              word.word.isNotEmpty
                                  ? word.word[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                            ),
                          ),
                          title: Text(
                            word.word,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(word.meaning),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            color: Theme.of(context).colorScheme.error,
                            onPressed: () => _showDeleteDialog(word),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('스웨덴어 단어장'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildWordList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddWordDialog,
        icon: const Icon(Icons.add),
        label: const Text('단어 추가'),
      ),
    );
  }
}
