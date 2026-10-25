import 'receipt_image_quality.dart';
import 'dart:async';
import 'dart:convert';
import 'transaction_date_rules.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'expense_store.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'receipt_parser.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReceiptlyApp());
}

const primary = Color(0xFF173F35);
const ink = Color(0xFF202720);
const canvas = Color(0xFFF3EFE6);
const paper = Color(0xFFFFFCF6);
const muted = Color(0xFF70766F);
const accent = Color(0xFFF07454);
const lime = Color(0xFFD7E8A6);
const line = Color(0xFFE2DDD2);
const categories = [
  'Ăn uống',
  'Mua sắm',
  'Di chuyển',
  'Hóa đơn',
  'Sức khỏe',
  'Khác',
];
const colors = [
  Color(0xFFF07454),
  Color(0xFFE5A73A),
  Color(0xFF4B9986),
  Color(0xFF7567A7),
  Color(0xFF82A85B),
  Color(0xFF8A8F89),
];
final money = NumberFormat.decimalPattern('vi_VN');
String vnd(num v) => '${money.format(v.round())} ₫';

class Expense {
  final String id, merchant, category, note;
  final double amount;
  final DateTime date;
  const Expense({
    required this.id,
    required this.merchant,
    required this.category,
    required this.note,
    required this.amount,
    required this.date,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'merchant': merchant,
    'category': category,
    'note': note,
    'amount': amount,
    'date': date.toIso8601String(),
  };
  factory Expense.fromJson(Map<String, dynamic> v) => Expense(
    id: v['id'].toString(),
    merchant: v['merchant'].toString(),
    category: v['category'].toString(),
    note: (v['note'] ?? '').toString(),
    amount: (v['amount'] as num).toDouble(),
    date: DateTime.parse(v['date'].toString()),
  );
}

class ReceiptlyApp extends StatelessWidget {
  const ReceiptlyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Receiptly',
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
        primary: primary,
        secondary: accent,
        surface: paper,
      ),
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 34,
          height: 1.05,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.2,
          color: ink,
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          height: 1.1,
          fontWeight: FontWeight.w900,
          letterSpacing: -.7,
          color: ink,
        ),
        titleLarge: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: -.25,
          color: ink,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: ink),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: .1,
        ),
      ),
      dividerColor: line,
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF7F3EA),
        labelStyle: const TextStyle(color: muted),
        prefixIconColor: primary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: primary, width: 1.6),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: paper,
        modalBackgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Timer? _dayRefresh;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(_clampSelectedMonth);
    }
  }

  void _clampSelectedMonth() {
    if (TransactionDateRules.isFutureMonth(selectedMonth)) {
      selectedMonth = TransactionDateRules.currentMonth();
    }
  }

  @override
  void dispose() {
    _dayRefresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<Expense> items = [];
  bool loading = true, scanning = false;
  int tab = 0;
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dayRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(_clampSelectedMonth);
    });
    _load();
  }

  final ExpenseStore store = ExpenseStore();
  Future<void> _load() async {
    try {
      await store.initialize();
      final rows = await store.all();
      items = rows.map(Expense.fromJson).toList();
    } catch (error) {
      if (mounted) _toast('Không thể đọc dữ liệu: $error');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _reload() async {
    final rows = await store.all();
    if (mounted) setState(() => items = rows.map(Expense.fromJson).toList());
  }

  Future<void> _exportBackup() async {
    try {
      final records = await store.all();
      final content = jsonEncode({
        'format': 'receiptly-backup',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'expenses': records,
      });
      final folder = await getTemporaryDirectory();
      final file = File(
        '${folder.path}/receiptly-backup-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.json',
      );
      await file.writeAsString(content, flush: true);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Sao lưu Receiptly'),
      );
    } catch (error) {
      _toast('Xuất dữ liệu thất bại: $error');
    }
  }

  Future<void> _importBackup() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final raw = file.bytes == null
          ? await File(file.path!).readAsString()
          : utf8.decode(file.bytes!);
      final obj = jsonDecode(raw);
      if (obj is! Map ||
          obj['format'] != 'receiptly-backup' ||
          obj['version'] != 1 ||
          obj['expenses'] is! List) {
        throw const FormatException('Không đúng định dạng sao lưu Receiptly');
      }
      final parsed = (obj['expenses'] as List)
          .map((e) => Expense.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final invalid = parsed
          .where((expense) => !TransactionDateRules.isValid(expense.date))
          .length;
      if (invalid > 0) {
        throw FormatException(
          'Bản sao lưu có $invalid giao dịch ở tương lai hoặc trước năm 2000. Hãy kiểm tra ngày giao dịch trước khi nhập.',
        );
      }
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nhập bản sao lưu?'),
          content: Text(
            'Tìm thấy ${parsed.length} giao dịch. Giao dịch trùng ID sẽ được cập nhật; dữ liệu hiện tại khác ID được giữ lại.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Nhập'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      await store.importRecords(parsed.map((e) => e.toJson()).toList());
      await _reload();
      _toast('Đã nhập ${parsed.length} giao dịch');
    } catch (error) {
      _toast('Không thể nhập dữ liệu: $error');
    }
  }

  Future<void> _openDataMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 2, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kho dữ liệu',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Dữ liệu nằm trên điện thoại và không cần tài khoản.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 20),
              _scanOption(
                icon: Icons.ios_share_rounded,
                title: 'Xuất bản sao lưu',
                subtitle: 'Tạo tệp JSON để cất giữ',
                onTap: () {
                  Navigator.pop(ctx);
                  _exportBackup();
                },
              ),
              const SizedBox(height: 10),
              _scanOption(
                icon: Icons.file_download_outlined,
                title: 'Khôi phục dữ liệu',
                subtitle: 'Nhập một bản sao lưu JSON',
                onTap: () {
                  Navigator.pop(ctx);
                  _importBackup();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s), behavior: SnackBarBehavior.floating),
      );
    }
  }

  List<Expense> get monthItems =>
      items
          .where(
            (e) =>
                e.date.year == selectedMonth.year &&
                e.date.month == selectedMonth.month,
          )
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
  Future<void> _entry({ReceiptData? parsed, Expense? editing}) async {
    final result = await showModalBottomSheet<Expense>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EntrySheet(parsed: parsed, editing: editing),
    );
    if (result == null) return;
    if (!TransactionDateRules.isValid(result.date)) {
      _toast('Không thể lưu giao dịch trong tương lai.');
      return;
    }
    try {
      await store.upsert(result.toJson());
      await _reload();
      if (mounted) {
        setState(
          () => selectedMonth = DateTime(result.date.year, result.date.month),
        );
      }
      _toast('Đã lưu khoản chi');
    } catch (error) {
      _toast('Không thể lưu dữ liệu: $error');
    }
  }

  Future<void> _scan(ImageSource source) async {
    if (scanning) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1800,
    );
    if (picked == null) return;
    setState(() => scanning = true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final quality = await ReceiptImageQuality.inspect(picked.path);
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(picked.path),
      );
      final positionedLines = <ReceiptOcrLine>[
        for (final block in recognized.blocks)
          for (final line in block.lines)
            ReceiptOcrLine(
              line.text,
              line.boundingBox.left,
              line.boundingBox.top,
              line.boundingBox.width,
              line.boundingBox.height,
            ),
      ];
      final parsed = ReceiptLayoutParser.parse(
        positionedLines,
        fallbackText: recognized.text,
      );
      if (!mounted) return;
      if (recognized.text.trim().isEmpty) {
        _toast('Không tìm thấy chữ. Hãy chụp rõ hơn.');
        return;
      }
      final assessment = ReceiptValidation.evaluate(
        parsed,
        recognizedCharacters: recognized.text.trim().length,
        lineCount: positionedLines.length,
        severelyBlurred: quality.severelyBlurred,
        recognizedText: recognized.text,
      );
      if (!assessment.accepted) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Không nhận diện được hóa đơn'),
            content: Text(assessment.reason),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đã hiểu'),
              ),
            ],
          ),
        );
        return;
      }
      if (assessment.needsReview && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cần kiểm tra kết quả OCR'),
            content: Text(assessment.reason),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Kiểm tra và sửa'),
              ),
            ],
          ),
        );
      }
      if (!mounted) return;
      await _entry(parsed: parsed);
    } catch (e) {
      _toast('Không đọc được hóa đơn: $e');
    } finally {
      await recognizer.close();
      if (mounted) setState(() => scanning = false);
    }
  }

  void _showScanPicker() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 2, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Đưa hóa đơn vào sổ',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Mọi bước nhận diện đều diễn ra trên thiết bị của bạn.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 20),
              _scanOption(
                icon: Icons.photo_camera_outlined,
                title: 'Chụp hóa đơn',
                subtitle: 'Mở máy ảnh và căn thẳng hóa đơn',
                onTap: () {
                  Navigator.pop(context);
                  _scan(ImageSource.camera);
                },
              ),
              const SizedBox(height: 10),
              _scanOption(
                icon: Icons.photo_library_outlined,
                title: 'Chọn từ thư viện',
                subtitle: 'Dùng một ảnh hóa đơn đã có',
                onTap: () {
                  Navigator.pop(context);
                  _scan(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scanOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => Material(
    color: const Color(0xFFF7F3EA),
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: lime,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(color: muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: primary),
          ],
        ),
      ),
    ),
  );
  Future<void> _delete(Expense e) async {
    try {
      await store.delete(e.id);
      await _reload();
      _toast('Đã xóa giao dịch');
    } catch (error) {
      _toast('Xóa thất bại: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = monthItems;
    final total = data.fold<double>(0, (sum, expense) => sum + expense.amount);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Expanded(
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(color: primary),
                    )
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      child: KeyedSubtree(
                        key: ValueKey(tab),
                        child: tab == 0
                            ? _dashboard(data, total)
                            : tab == 1
                            ? _transactions(data)
                            : _insights(data, total),
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _bottomDock(),
    );
  }

  Widget _header() {
    const labels = ['Tổng quan', 'Sổ giao dịch', 'Phân tích'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 14, 10),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RECEIPTLY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  labels[tab],
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          _headerAction(
            Icons.cloud_upload_outlined,
            'Sao lưu / Khôi phục',
            _openDataMenu,
          ),
          const SizedBox(width: 7),
          _headerAction(
            Icons.more_horiz_rounded,
            'Thông tin',
            () => showAboutDialog(
              context: context,
              applicationName: 'Receiptly',
              applicationVersion: '1.1.0',
              children: [
                const Text(
                  'Theo dõi chi tiêu offline • Google ML Kit OCR • dữ liệu lưu trên thiết bị.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerAction(IconData icon, String tooltip, VoidCallback onPressed) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: paper,
          foregroundColor: ink,
          side: const BorderSide(color: line),
        ),
        icon: Icon(icon, size: 20),
      );

  Widget _bottomDock() => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
    child: Container(
      height: 72,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2B173F35),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _navItem(0, Icons.space_dashboard_outlined, 'Tổng quan'),
          _navItem(1, Icons.receipt_long_outlined, 'Giao dịch'),
          _navItem(2, Icons.donut_large_outlined, 'Phân tích'),
          Container(
            width: 1,
            height: 30,
            color: Colors.white24,
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Quét hóa đơn',
              child: InkWell(
                onTap: scanning ? null : _showScanPicker,
                borderRadius: BorderRadius.circular(17),
                child: Container(
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: scanning
                      ? const Padding(
                          padding: EdgeInsets.all(15),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.document_scanner_outlined,
                              color: Colors.white,
                              size: 21,
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Quét',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _navItem(int index, IconData icon, String label) {
    final selected = tab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => tab = index),
        borderRadius: BorderRadius.circular(17),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: double.infinity,
          decoration: BoxDecoration(
            color: selected ? lime : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: selected ? primary : Colors.white70),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? primary : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthControl() {
    final canNext = TransactionDateRules.canGoToNextMonth(selectedMonth);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: line),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Tháng trước',
            onPressed: () => setState(
              () => selectedMonth = DateTime(
                selectedMonth.year,
                selectedMonth.month - 1,
              ),
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 19),
          ),
          const Icon(Icons.calendar_today_outlined, size: 16, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Center(
              child: Text(
                'Tháng ${selectedMonth.month}  •  ${selectedMonth.year}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: canNext ? 'Tháng sau' : 'Không thể xem tháng tương lai',
            onPressed: canNext
                ? () {
                    if (!TransactionDateRules.canGoToNextMonth(selectedMonth)) {
                      return;
                    }
                    setState(
                      () => selectedMonth = DateTime(
                        selectedMonth.year,
                        selectedMonth.month + 1,
                      ),
                    );
                  }
                : null,
            icon: const Icon(Icons.arrow_forward_rounded, size: 19),
          ),
        ],
      ),
    );
  }

  Widget _dashboard(List<Expense> data, double total) {
    final sums = <String, double>{
      for (final category in categories) category: 0,
    };
    for (final expense in data) {
      sums[expense.category] = (sums[expense.category] ?? 0) + expense.amount;
    }
    final top = sums.entries.fold<MapEntry<String, double>?>(
      null,
      (best, item) => best == null || item.value > best.value ? item : best,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
      children: [
        _monthControl(),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          decoration: BoxDecoration(
            color: primary,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x24173F35),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'TỔNG CHI THÁNG NÀY',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.35,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.wallet_outlined,
                      color: lime,
                      size: 21,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  vnd(total),
                  style: const TextStyle(
                    fontSize: 36,
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.2,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _darkMetric('${data.length}', 'Giao dịch')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _darkMetric(
                      top == null || top.value == 0 ? '—' : top.key,
                      'Chi nhiều nhất',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: _quickAction(
                Icons.add_rounded,
                'Ghi khoản chi',
                'Nhập thủ công',
                () => _entry(),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: _quickAction(
                Icons.auto_graph_rounded,
                'Xem phân tích',
                'Theo danh mục',
                () => setState(() => tab = 2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            Text(
              'Mới ghi gần đây',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => tab = 1),
              child: const Text('Mở sổ  →'),
            ),
          ],
        ),
        const SizedBox(height: 7),
        if (data.isEmpty) _empty() else ...data.take(5).map(_tile),
      ],
    );
  }

  Widget _darkMetric(String value, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11.5),
        ),
      ],
    ),
  );

  Widget _quickAction(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => Material(
    color: paper,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(
                color: lime,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: primary, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _empty() => Container(
    padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 22),
    decoration: BoxDecoration(
      color: paper,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: line),
    ),
    child: Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: lime,
            borderRadius: BorderRadius.circular(19),
          ),
          child: const Icon(Icons.note_add_outlined, color: primary, size: 27),
        ),
        const SizedBox(height: 16),
        const Text(
          'Cuốn sổ đang trống',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        const Text(
          'Quét hóa đơn hoặc ghi khoản chi đầu tiên để bắt đầu.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted),
        ),
      ],
    ),
  );

  List<IconData> get _categoryIcons => const [
    Icons.restaurant_rounded,
    Icons.shopping_bag_outlined,
    Icons.directions_car_filled_outlined,
    Icons.bolt_rounded,
    Icons.health_and_safety_outlined,
    Icons.more_horiz_rounded,
  ];

  Widget _tile(Expense e) {
    final found = categories.indexOf(e.category);
    final index = found < 0 ? 5 : found;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: paper,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => _entry(editing: e),
          onLongPress: () => showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Xóa giao dịch?'),
              content: Text('“${e.merchant}” sẽ được xóa khỏi sổ chi tiêu.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _delete(e);
                  },
                  child: const Text('Xóa'),
                ),
              ],
            ),
          ),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 13, 15, 13),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors[index].withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _categoryIcons[index],
                    color: colors[index],
                    size: 22,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.merchant,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${e.category}  ·  ${DateFormat('dd/MM').format(e.date)}',
                        style: const TextStyle(color: muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      vnd(e.amount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Icon(
                      Icons.arrow_outward_rounded,
                      size: 15,
                      color: muted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _transactions(List<Expense> data) {
    final total = data.fold<double>(0, (sum, expense) => sum + expense.amount);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
      children: [
        _monthControl(),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: lime,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${data.length} mục trong sổ',
                      style: const TextStyle(
                        fontSize: 13,
                        color: primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      vnd(total),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: primary,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _entry(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Thêm'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Text(
              'Tất cả giao dịch',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Spacer(),
            const Text(
              'Mới nhất trước',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (data.isEmpty) _empty() else ...data.map(_tile),
        if (data.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Chạm để chỉnh sửa  •  Nhấn giữ để xóa',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _insights(List<Expense> data, double total) {
    final sums = List<double>.filled(categories.length, 0);
    for (final expense in data) {
      final index = categories.indexOf(expense.category);
      sums[index < 0 ? 5 : index] += expense.amount;
    }
    final days = List.generate(
      7,
      (_) => List<double>.filled(categories.length, 0),
    );
    final now = DateTime.now();
    for (final expense in items) {
      final age = DateTime(now.year, now.month, now.day)
          .difference(
            DateTime(expense.date.year, expense.date.month, expense.date.day),
          )
          .inDays;
      if (age >= 0 && age < 7) {
        final index = categories.indexOf(expense.category);
        days[6 - age][index < 0 ? 5 : index] += expense.amount;
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
      children: [
        _monthControl(),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 19, 20, 18),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BỨC TRANH CHI TIÊU',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Nhìn lại thói quen\ncủa bạn',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        height: 1.12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(19),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  color: Colors.white,
                  size: 29,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _panel(
          Column(
            children: [
              Row(
                children: [
                  Text(
                    'Chi theo danh mục',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: lime,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${data.length} mục',
                      style: const TextStyle(
                        color: primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(height: 178, child: AnimatedPieChart(values: sums)),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 10),
              ...List.generate(categories.length, (index) {
                final percent = total == 0
                    ? 0
                    : (sums[index] / total * 100).round();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Container(
                        width: 31,
                        height: 31,
                        decoration: BoxDecoration(
                          color: colors[index].withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _categoryIcons[index],
                          size: 15,
                          color: colors[index],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              categories[index],
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '$percent% tổng chi',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        vnd(sums[index]),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 13),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Nhịp chi 7 ngày',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Container(
                    width: 35,
                    height: 35,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7E4D9),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.bar_chart_rounded,
                      color: accent,
                      size: 19,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              const Text(
                'Mỗi cột là tổng chi trong ngày, chia theo danh mục.',
                style: TextStyle(color: muted, fontSize: 12.5),
              ),
              const SizedBox(height: 20),
              SizedBox(height: 175, child: AnimatedBars(values: days)),
              const SizedBox(height: 10),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '6 ngày trước',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                  Text(
                    'Hôm nay',
                    style: TextStyle(
                      color: muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          color: const Color(0xFFE9E1F3),
        ),
        if (total == 0)
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Text(
              'Thêm giao dịch để các con số bắt đầu kể chuyện.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
          ),
      ],
    );
  }

  Widget _panel(Widget child, {Color color = paper}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
      border: color == paper ? Border.all(color: line) : null,
    ),
    child: child,
  );
}

class EntrySheet extends StatefulWidget {
  final ReceiptData? parsed;
  final Expense? editing;
  const EntrySheet({super.key, this.parsed, this.editing});
  @override
  State<EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<EntrySheet> {
  late final TextEditingController merchant, amount, note;
  late DateTime date;
  String category = categories[0];
  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    merchant = TextEditingController(
      text: e?.merchant ?? widget.parsed?.merchant ?? '',
    );
    amount = TextEditingController(
      text: e != null
          ? e.amount.round().toString()
          : (widget.parsed?.total?.round().toString() ?? ''),
    );
    note = TextEditingController(text: e?.note ?? '');
    date = e?.date ?? widget.parsed?.date ?? DateTime.now();
    category = e?.category ?? categories[0];
  }

  @override
  void dispose() {
    merchant.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final future = TransactionDateRules.isFuture(date);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: lime,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    widget.parsed != null
                        ? Icons.document_scanner_outlined
                        : widget.editing != null
                        ? Icons.edit_note_rounded
                        : Icons.add_card_rounded,
                    color: primary,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SỔ CHI TIÊU',
                        style: TextStyle(
                          color: muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.editing != null
                            ? 'Sửa giao dịch'
                            : widget.parsed != null
                            ? 'Kiểm tra hóa đơn'
                            : 'Ghi khoản chi',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (widget.parsed != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: widget.parsed!.date == null || future
                      ? const Color(0xFFFFE5D9)
                      : const Color(0xFFEAF3D0),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  widget.parsed!.date == null
                      ? 'Không tìm thấy ngày hóa đơn. Hãy chọn đúng ngày trước khi lưu.'
                      : future
                      ? 'Ngày trên hóa đơn nằm trong tương lai. Hãy chọn lại ngày hợp lệ.'
                      : 'OCR đã điền sẵn thông tin. Hãy kiểm tra lại trước khi lưu.',
                  style: TextStyle(
                    color: widget.parsed!.date == null || future
                        ? const Color(0xFF9B3E27)
                        : primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: merchant,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Tên cửa hàng / nội dung',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số tiền (VND)',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(
                labelText: 'Danh mục',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: categories
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => category = value);
              },
            ),
            const SizedBox(height: 12),
            Material(
              color: const Color(0xFFF7F3EA),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () async {
                  final today = TransactionDateRules.today();
                  final initial = date.isAfter(today)
                      ? today
                      : date.isBefore(DateTime(2000))
                      ? DateTime(2000)
                      : date;
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: DateTime(2000),
                    lastDate: today,
                  );
                  if (picked != null && mounted) setState(() => date = picked);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_outlined, color: primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Ngày giao dịch',
                              style: TextStyle(color: muted, fontSize: 11.5),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat('dd/MM/yyyy').format(date),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (future)
                        const Text(
                          'Không hợp lệ',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      const SizedBox(width: 5),
                      const Icon(Icons.chevron_right_rounded, color: muted),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Ghi chú (không bắt buộc)',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: () {
                  final value = double.tryParse(
                    amount.text.trim().replaceAll(RegExp(r'[, .\s₫đ]'), ''),
                  );
                  if (merchant.text.trim().isEmpty ||
                      value == null ||
                      value <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Vui lòng nhập tên và số tiền hợp lệ'),
                      ),
                    );
                    return;
                  }
                  // Check AGAIN on save in case the day changed while this sheet was open.
                  if (!TransactionDateRules.isValid(date)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Không được lưu giao dịch tương lai. Hãy chọn ngày hiện tại hoặc quá khứ.',
                        ),
                      ),
                    );
                    setState(() {});
                    return;
                  }
                  Navigator.pop(
                    context,
                    Expense(
                      id:
                          widget.editing?.id ??
                          DateTime.now().microsecondsSinceEpoch.toString(),
                      merchant: merchant.text.trim(),
                      amount: value,
                      category: category,
                      note: note.text.trim(),
                      date: date,
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Lưu vào sổ'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnimatedPieChart extends StatefulWidget {
  final List<double> values;
  const AnimatedPieChart({super.key, required this.values});
  @override
  State<AnimatedPieChart> createState() => _AnimatedPieChartState();
}

class _AnimatedPieChartState extends State<AnimatedPieChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedPieChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    controller.forward(from: 0);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, child) => CustomPaint(
      painter: PiePainter(widget.values, controller.value),
      child: child,
    ),
    child: const SizedBox.expand(),
  );
}

class PiePainter extends CustomPainter {
  final List<double> values;
  final double progress;
  PiePainter(this.values, this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .40;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final total = values.fold<double>(0, (a, b) => a + b);
    final bg = Paint()
      ..color = line
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, bg);
    if (total > 0) {
      var start = -math.pi / 2;
      for (var i = 0; i < values.length; i++) {
        final angle = 2 * math.pi * values[i] / total * progress;
        canvas.drawArc(
          rect,
          start,
          math.max(0, angle - .025),
          false,
          Paint()
            ..color = colors[i]
            ..strokeWidth = 22
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
        start += angle;
      }
    }
    final label = total <= 0 ? 'CHƯA CÓ' : 'TỔNG CƠ CẤU';
    final value = total <= 0 ? '—' : '${(progress * 100).round()}%';
    final valuePainter = TextPainter(
      text: TextSpan(
        text: value,
        style: const TextStyle(
          color: ink,
          fontSize: 27,
          fontWeight: FontWeight.w900,
          letterSpacing: -.6,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: muted,
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    valuePainter.paint(
      canvas,
      center - Offset(valuePainter.width / 2, valuePainter.height / 2 + 5),
    );
    labelPainter.paint(canvas, center + Offset(-labelPainter.width / 2, 17));
  }

  @override
  bool shouldRepaint(covariant PiePainter old) =>
      old.progress != progress || old.values != values;
}

class AnimatedBars extends StatefulWidget {
  final List<List<double>> values; // 7 days x categories
  const AnimatedBars({super.key, required this.values});
  @override
  State<AnimatedBars> createState() => _AnimatedBarsState();
}

class _AnimatedBarsState extends State<AnimatedBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    controller.forward(from: 0);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, child) => CustomPaint(
      painter: BarsPainter(widget.values, controller.value),
      child: const SizedBox.expand(),
    ),
  );
}

class BarsPainter extends CustomPainter {
  final List<List<double>> values;
  final double progress;
  BarsPainter(this.values, this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final totals = values
        .map((day) => day.fold<double>(0, (a, b) => a + b))
        .toList();
    final maxTotal = totals.fold<double>(0, (a, b) => math.max(a, b));
    final width = size.width / values.length;
    final plotHeight = size.height - 10;
    for (var day = 0; day < values.length; day++) {
      var bottom = size.height;
      for (var category = 0; category < values[day].length; category++) {
        final value = values[day][category];
        if (value <= 0 || maxTotal <= 0) continue;
        final height = value / maxTotal * plotHeight * progress;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            day * width + width * .20,
            bottom - height,
            width * .60,
            height,
          ),
          const Radius.circular(3),
        );
        canvas.drawRRect(
          rect,
          Paint()
            ..color =
                colors[category < colors.length ? category : colors.length - 1],
        );
        bottom -= height;
      }
    }
  }

  @override
  bool shouldRepaint(covariant BarsPainter old) =>
      old.progress != progress || old.values != values;
}
