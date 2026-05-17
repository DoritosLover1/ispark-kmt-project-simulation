import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint(".env file not found, loading defaults.");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'İSPARK Akıllı Geçiş & Gişe Sistemi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xff0a0e1b),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xff00e6ff),
          secondary: Color(0xff00ff87),
          surface: Color(0xff141a2e),
          error: Color(0xffff0055),
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
      ),
      home: const MainGateScreen(),
    );
  }
}

class SystemLog {
  final DateTime timestamp;
  final String source;
  final String message;
  final String type;

  SystemLog({
    required this.timestamp,
    required this.source,
    required this.message,
    required this.type,
  });
}

class MainGateScreen extends StatefulWidget {
  const MainGateScreen({super.key});

  @override
  State<MainGateScreen> createState() => _MainGateScreenState();
}

class _MainGateScreenState extends State<MainGateScreen> {
  String _sbUrl = '';
  String _sbKey = '';
  String _sbFunction = 'ispark-rezervasyon-onayla-handler';
  String _otoparkId = '1';
  String _secretKey = '';
  bool _isSupabaseConfigured = false;

  final TextEditingController _plateController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  String _timeString = '00:00:00';
  late Timer _clockTimer;
  final List<SystemLog> _logs = [];
  bool _isScanning = false;
  bool _showPlateHighlight = false;
  bool _isButtonLoading = false;

  final List<Map<String, dynamic>> _recentArrivals = [];

  bool _barrierOpened = false;
  double _carPositionLeft = -100;

  final List<String> _mockPlates = [
    '34 ISP 3400',
    '34 TURK 1923',
    '34 ABC 123',
    '06 ANK 0606',
    '35 IZM 3535',
    '34 GISE 2026',
    '34 EKRN 77',
  ];

  @override
  void initState() {
    super.initState();
    _startClock();
    _loadConfig();
    _addLog(
      'system',
      'Akıllı Gişe İşletim Sistemi (Flutter v2.0) başlatıldı.',
      'system',
    );
    _addLog(
      'system',
      'Donanım sensörleri ve ANPR Kamera-04 bağlantısı aktif.',
      'system',
    );
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _plateController.dispose();
    for (var c in _otpControllers) {
      c.dispose();
    }
    for (var f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      final now = DateTime.now();
      setState(() {
        _timeString =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      });
    });
  }

  void _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();

    final envUrl = dotenv.env['SUPABASE_URL'] ?? '';
    final envKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
    final envOtoparkId =
        dotenv.env['OTOPARK_ID'] ?? dotenv.env['PARK_ID'] ?? '';
    final envSecretKey =
        dotenv.env['ACCPT_SECRET_KEY'] ??
        dotenv.env['X_SECRET_KEY'] ??
        dotenv.env['SECRET_KEY'] ??
        '';

    setState(() {
      _sbUrl = prefs.getString('ispark_sb_url') ?? envUrl;
      _sbKey = prefs.getString('ispark_sb_key') ?? envKey;
      _sbFunction =
          prefs.getString('ispark_sb_function') ??
          'ispark-rezervasyon-onayla-handler';
      _otoparkId =
          prefs.getString('ispark_sb_otopark_id') ??
          (envOtoparkId.isNotEmpty ? envOtoparkId : '1');
      _secretKey = prefs.getString('ispark_sb_secret_key') ?? envSecretKey;
    });

    _initializeSupabase();

    if (envUrl.isNotEmpty && envKey.isNotEmpty) {
      _addLog(
        'supabase',
        '.env dosyası algılandı ve API bağlantı anahtarları başarıyla yüklendi.',
        'supabase',
      );
    }

    if (_isSupabaseConfigured) {
      _addLog(
        'supabase',
        'Supabase bağlantısı yapılandırıldı. API tetikleme modu: AKTİF',
        'supabase',
      );
      _addLog(
        'supabase',
        'Edge Function Hedefi: "$_sbFunction" (Otopark: $_otoparkId)',
        'supabase',
      );
    } else {
      _addLog(
        'system',
        'Supabase bağlantısı henüz yapılandırılmadı.',
        'system',
      );
      _addLog(
        'system',
        'Not: Bağlantıyı kurmak için sağ üstteki Ayarlar (Çark) menüsünü kullanabilir veya kök dizine .env dosyası ekleyebilirsiniz.',
        'system',
      );
    }
  }

  void _initializeSupabase() {
    if (_sbUrl.isNotEmpty && _sbKey.isNotEmpty) {
      try {
        Supabase.initialize(
          url: _sbUrl.trim(),
          anonKey: _sbKey.trim(),
          authOptions: const FlutterAuthClientOptions(
            authFlowType: AuthFlowType.pkce,
          ),
        );
        setState(() {
          _isSupabaseConfigured = true;
        });
      } catch (e) {
        setState(() {
          _isSupabaseConfigured = true;
        });
      }
    } else {
      setState(() {
        _isSupabaseConfigured = false;
      });
    }
  }

  void _saveConfig(
    String url,
    String key,
    String func,
    String otoparkId,
    String secretKey,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ispark_sb_url', url.trim());
    await prefs.setString('ispark_sb_key', key.trim());
    await prefs.setString('ispark_sb_function', func.trim());
    await prefs.setString('ispark_sb_otopark_id', otoparkId.trim());
    await prefs.setString('ispark_sb_secret_key', secretKey.trim());

    setState(() {
      _sbUrl = url.trim();
      _sbKey = key.trim();
      _sbFunction = func.trim();
      _otoparkId = otoparkId.trim();
      _secretKey = secretKey.trim();
    });

    _initializeSupabase();

    _addLog('supabase', 'Bağlantı ayarları başarıyla güncellendi.', 'supabase');
    if (_isSupabaseConfigured) {
      _addLog(
        'supabase',
        'Supabase bağlantısı başarıyla kuruldu. Hedef: "$_sbFunction"',
        'supabase',
      );
    }
  }

  void _resetConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    setState(() {
      _sbUrl = '';
      _sbKey = '';
      _sbFunction = 'ispark-rezervasyon-onayla-handler';
      _otoparkId = '1';
      _secretKey = '';
      _isSupabaseConfigured = false;
    });
    _addLog('system', 'Tüm bağlantı ayarları sıfırlandı.', 'system');
  }

  void _addLog(String source, String message, String type) {
    setState(() {
      _logs.insert(
        0,
        SystemLog(
          timestamp: DateTime.now(),
          source: source.toUpperCase(),
          message: message,
          type: type,
        ),
      );
    });
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
    _addLog('system', 'Konsol kayıtları temizlendi.', 'system');
  }

  void _simulateANPRScan() {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _showPlateHighlight = false;
      _carPositionLeft = -100;
    });
    _addLog(
      'sensor',
      'ANPR Plaka tarama tetiklendi. Görüntü işleniyor...',
      'sensor',
    );

    Timer(const Duration(milliseconds: 1500), () {
      setState(() {
        _isScanning = false;
        _showPlateHighlight = true;
        _carPositionLeft = 120;

        final randomIdx = DateTime.now().millisecond % _mockPlates.length;
        final pickedPlate = _mockPlates[randomIdx];
        _plateController.text = pickedPlate;
      });

      _addLog(
        'sensor',
        'Araç algılandı! Okunan Plaka: "${_plateController.text}" (Güven: %${(95 + (DateTime.now().microsecond % 49) / 10).toStringAsFixed(1)})',
        'sensor',
      );
    });
  }

  void _verifyAndTrigger() async {
    final plateValue = _plateController.text.replaceAll(' ', '').trim();

    String otpValue = '';
    for (var c in _otpControllers) {
      otpValue += c.text.trim();
    }

    if (plateValue.isEmpty) {
      _addLog('system', 'HATA: Lütfen bir plaka bilgisi giriniz!', 'error');
      _showErrorDialog(
        'Lütfen plaka bilgisini giriniz (Elle girin veya sensörden okutun).',
      );
      return;
    }

    if (otpValue.length < 6) {
      _addLog(
        'system',
        'HATA: Eksik OTP kodu! Girilen hane sayısı: ${otpValue.length}/6',
        'error',
      );
      _showErrorDialog(
        'Lütfen 6 haneli OTP doğrulama kodunu eksiksiz giriniz.',
      );
      return;
    }

    setState(() {
      _isButtonLoading = true;
    });

    _addLog(
      'system',
      'Geçiş talebi başlatıldı. Plaka: "$plateValue", OTP: "$otpValue"',
      'system',
    );

    if (!_isSupabaseConfigured) {
      _addLog('error', 'HATA: Supabase bağlantısı yapılandırılmamış!', 'error');
      _showErrorDialog(
        'Supabase bağlantı bilgileri (URL, Anon Key) eksik veya hatalı!\n\nLütfen sağ üstteki Çark simgesine tıklayarak bağlantı ayarlarını yapınız veya .env dosyasını kontrol ediniz.',
      );
      setState(() {
        _isButtonLoading = false;
      });
      return;
    }

    _addLog(
      'supabase',
      'Supabase Edge Function tetikleniyor... [API: $_sbFunction]',
      'supabase',
    );

    try {
      final client = Supabase.instance.client;
      final response = await client.functions.invoke(
        _sbFunction,
        headers: {'x-secret-key': _secretKey},
        body: {'plaka': plateValue, 'otopark_id': _otoparkId, 'otp': otpValue},
      );

      final data = response.data;
      _addLog(
        'supabase',
        'API Yanıtı başarıyla alındı: ${jsonEncode(data)}',
        'supabase',
      );

      bool isApproved = false;
      String responseMsg = 'Giriş Onaylandı!';
      num currentPrice = 0;

      if (data is bool) {
        isApproved = data;
        responseMsg = isApproved
            ? 'Geçiş Onaylandı!'
            : 'Geçersiz OTP kodu veya plaka eşleşmesi.';
      } else if (data is Map) {
        isApproved =
            data['success'] == true ||
            data['status'] == 'success' ||
            data['approved'] == true ||
            data['ok'] == true;
        responseMsg =
            data['message'] ??
            data['error'] ??
            (isApproved ? 'Giriş Onaylandı!' : 'Geçiş Reddedildi!');

        if (data['price'] != null) {
          currentPrice = data['price'] is num
              ? data['price']
              : num.tryParse(data['price'].toString()) ?? 0;
        }
      }

      if (isApproved) {
        setState(() {
          _recentArrivals.insert(0, {
            'plaka': plateValue,
            'price': currentPrice,
          });
          if (_recentArrivals.length > 15) _recentArrivals.removeLast();
        });
        _addLog(
          'supabase',
          'Supabase Onayı: $responseMsg (Ücret: $currentPrice TL)',
          'success',
        );
        _openBarrier();
        _clearOtpInputs();
      } else {
        _addLog('supabase', 'Supabase RED: $responseMsg', 'error');
        _showErrorDialog('Giriş Reddedildi!\nAçıklama: $responseMsg');
        _clearOtpInputs();
        _otpFocusNodes[0].requestFocus();
      }
    } catch (err) {
      String errorMsg = err.toString();

      if (err is FunctionException) {
        try {
          final parsed = jsonDecode(err.details.toString());
          if (parsed != null &&
              (parsed['error'] != null || parsed['message'] != null)) {
            errorMsg = parsed['error'] ?? parsed['message'];
          }
        } catch (_) {}
      }

      debugPrint('Supabase Edge Function Error: $err');
      _addLog('error', 'Supabase Bağlantı Hatası: $errorMsg', 'error');
      _showErrorDialog(
        'Supabase Edge Function API Çalıştırılamadı!\n\nDetay: $errorMsg\n\nLütfen bağlantı bilgilerinizi veya API adını kontrol ediniz.',
      );
    } finally {
      setState(() {
        _isButtonLoading = false;
      });
    }
  }

  void _openBarrier() {
    setState(() {
      _barrierOpened = true;
    });
    _addLog('system', 'Bariyer AÇILDI. Güvenlik LED: YEŞİL.', 'success');

    Timer(const Duration(milliseconds: 1000), () {
      setState(() {
        _carPositionLeft = 500;
      });
      _addLog(
        'sensor',
        'Araç geçiş sensörü tetiklendi. Araç geçiyor...',
        'sensor',
      );

      Timer(const Duration(milliseconds: 4000), () {
        _closeBarrier();
      });
    });
  }

  void _closeBarrier() {
    setState(() {
      _barrierOpened = false;
    });
    _addLog(
      'system',
      'Bariyer geri kapatıldı. Güvenlik LED: KIRMIZI.',
      'system',
    );

    Timer(const Duration(milliseconds: 1500), () {
      setState(() {
        _carPositionLeft = -100;
        _showPlateHighlight = false;
      });
    });
  }

  void _clearOtpInputs() {
    for (var c in _otpControllers) {
      c.clear();
    }
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xffff0055)),
            SizedBox(width: 10),
            Text('Sistem Bildirimi'),
          ],
        ),
        content: Text(msg, style: const TextStyle(fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Tamam',
              style: TextStyle(color: Color(0xff00e6ff)),
            ),
          ),
        ],
      ),
    );
  }

  void _openSettingsDialog() {
    final urlController = TextEditingController(text: _sbUrl);
    final keyController = TextEditingController(text: _sbKey);
    final funcController = TextEditingController(text: _sbFunction);
    final otoparkIdController = TextEditingController(text: _otoparkId);
    final secretKeyController = TextEditingController(text: _secretKey);
    bool obscureSecret = true;
    bool obscureAnon = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xff121829),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: const [
              Icon(Icons.settings, color: Color(0xff00e6ff)),
              SizedBox(width: 10),
              Text('Supabase Entegrasyon Ayarları'),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bağlantı parametrelerinizi giriniz. Boş bırakıldığında simülasyon moduna geçer.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 15),

                  TextField(
                    controller: urlController,
                    decoration: const InputDecoration(
                      labelText: 'Supabase Project URL',
                      hintText: 'https://xxx.supabase.co',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: keyController,
                    obscureText: obscureAnon,
                    decoration: InputDecoration(
                      labelText: 'Supabase Anon Key',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureAnon ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () =>
                            setModalState(() => obscureAnon = !obscureAnon),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: funcController,
                    decoration: const InputDecoration(
                      labelText: 'Tetiklenecek API Fonksiyon Adı',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: otoparkIdController,
                          decoration: const InputDecoration(
                            labelText: 'Otopark ID',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: secretKeyController,
                          obscureText: obscureSecret,
                          decoration: InputDecoration(
                            labelText: 'X-Secret-Key',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureSecret
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () => setModalState(
                                () => obscureSecret = !obscureSecret,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _resetConfig();
                Navigator.of(ctx).pop();
              },
              child: const Text(
                'Sıfırla',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'İptal',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff00e6ff),
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                _saveConfig(
                  urlController.text,
                  keyController.text,
                  funcController.text,
                  otoparkIdController.text,
                  secretKeyController.text,
                );
                Navigator.of(ctx).pop();
              },
              child: const Text(
                'Ayarları Kaydet',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 950;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xff070a13), Color(0xff0d1326)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: isDesktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 3, child: _buildPricingList()),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 4,
                              child: SingleChildScrollView(
                                child: _buildFormColumn(),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(flex: 4, child: _buildSimulatorColumn()),
                          ],
                        )
                      : SingleChildScrollView(
                          child: Column(
                            children: [
                              _buildFormColumn(),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 850,
                                child: _buildSimulatorColumn(),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: const BoxDecoration(
        color: Color(0xff0f152d),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'İSPARK',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Akıllı Geçiş & Gişe Sistemi',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Operatör Kontrol Paneli',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 16,
                      color: Color(0xff00e6ff),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _timeString,
                      style: GoogleFonts.shareTechMono(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xff1b223d),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.settings, color: Colors.white),
                onPressed: _openSettingsDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '🚗 HIZLI GEÇİŞ DOĞRULAMA',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Plaka tanıma sensörü veya OTP doğrulama kodu kullanarak geçişi tetikleyin.',
          style: TextStyle(fontSize: 13, color: Colors.white54),
        ),
        const SizedBox(height: 16),

        _buildCard(
          title: '1. Giriş: Araç Plaka & Otopark Bilgisi',
          badgeText: 'Sensör Destekli',
          badgeColor: const Color(0xff00e6ff),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.local_parking_rounded,
                          color: Color(0xff00e6ff),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Aktif Otopark ID:',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      width: 80,
                      height: 35,
                      child: TextField(
                        textAlign: TextAlign.center,
                        style: GoogleFonts.shareTechMono(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          hintText: '1',
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                          filled: true,
                          fillColor: Colors.black26,
                          enabledBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.white24),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(
                              color: Color(0xff00e6ff),
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _otoparkId = val.trim();
                          });
                          SharedPreferences.getInstance().then((prefs) {
                            prefs.setString('ispark_sb_otopark_id', _otoparkId);
                          });
                        },
                        controller: TextEditingController()
                          ..text = _otoparkId
                          ..selection = TextSelection.fromPosition(
                            TextPosition(offset: _otoparkId.length),
                          ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isScanning
                        ? const Color(0xff00e6ff)
                        : Colors.white12,
                    width: _isScanning ? 2 : 1,
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.antiAlias,
                  children: [
                    _buildCornerDecoration(Alignment.topLeft),
                    _buildCornerDecoration(Alignment.topRight),
                    _buildCornerDecoration(Alignment.bottomLeft),
                    _buildCornerDecoration(Alignment.bottomRight),

                    if (_isScanning) const ScanLaserLine(),

                    Center(
                      child: _isScanning
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(
                                  width: 25,
                                  height: 25,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Color(0xff00e6ff),
                                  ),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'PLAKA OKUNUYOR...',
                                  style: TextStyle(
                                    color: Color(0xff00e6ff),
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            )
                          : _showPlateHighlight
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: const Color(0xff00ff87),
                                      width: 1.5,
                                    ),
                                    color: Colors.green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'PLAKA OKUNDU',
                                    style: TextStyle(
                                      color: Color(0xff00ff87),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _plateController.text,
                                  style: GoogleFonts.shareTechMono(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.videocam_off_outlined,
                                  color: Colors.white30,
                                  size: 36,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Sensör Kamerası Beklemede',
                                  style: TextStyle(
                                    color: Colors.white30,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                    ),

                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        color: Colors.black45,
                        child: const Text(
                          'LIVE • CAM_ANPR_04',
                          style: TextStyle(
                            fontSize: 9,
                            fontFamily: 'monospace',
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff1c233f),
                  foregroundColor: const Color(0xff00e6ff),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Colors.white10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text(
                  'Sensörden Oku (Plaka Algıla)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: _isScanning ? null : _simulateANPRScan,
              ),
              const SizedBox(height: 16),

              const Text(
                'Plaka (Elle Giriş / Düzeltme)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey, width: 2),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: double.infinity,
                      decoration: const BoxDecoration(
                        color: Color(0xff003399),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(6),
                          bottomLeft: Radius.circular(6),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'TR',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              fontFamily: 'sans-serif',
                            ),
                          ),
                          SizedBox(height: 6),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15.0),
                        child: TextField(
                          controller: _plateController,
                          style: GoogleFonts.shareTechMono(
                            color: Colors.black,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: '34 ISP 3400',
                            hintStyle: TextStyle(color: Colors.black26),
                          ),
                          inputFormatters: [
                            UpperCaseTextFormatter(),
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Z0-9\s]'),
                            ),
                          ],
                          onChanged: (_) {
                            setState(() {
                              _showPlateHighlight = true;
                              _carPositionLeft = 120;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Boşluklu veya boşluksuz yazabilirsiniz (Örn: 34ABC123 veya 34 ABC 123)',
                style: TextStyle(fontSize: 11, color: Colors.white30),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _buildCard(
          title: '2. Giriş: Tek Kullanımlık Şifre (OTP)',
          badgeText: 'Zorunlu',
          badgeColor: const Color(0xffff0055),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Mobil uygulamadan veya SMS ile gelen 6 haneli geçiş doğrulama kodunu giriniz.',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 14),

              _buildOtpInputs(),

              const SizedBox(height: 24),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff00e6ff),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _isButtonLoading ? null : _verifyAndTrigger,
                child: _isButtonLoading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Supabase Edge API Çalıştırılıyor...',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.check_circle_outline, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Doğrula ve Bariyeri Aç',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCornerDecoration(Alignment align) {
    const size = 12.0;
    const border = BorderSide(color: Colors.white30, width: 2);

    Border? customBorder;
    if (align == Alignment.topLeft) {
      customBorder = const Border(top: border, left: border);
    } else if (align == Alignment.topRight) {
      customBorder = const Border(top: border, right: border);
    } else if (align == Alignment.bottomLeft) {
      customBorder = const Border(bottom: border, left: border);
    } else if (align == Alignment.bottomRight) {
      customBorder = const Border(bottom: border, right: border);
    }

    return Align(
      alignment: align,
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(border: customBorder),
      ),
    );
  }

  Widget _buildOtpInputs() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (index) {
        return SizedBox(
          width: 46,
          height: 56,
          child: TextField(
            controller: _otpControllers[index],
            focusNode: _otpFocusNodes[index],
            textAlign: TextAlign.center,
            style: GoogleFonts.shareTechMono(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            maxLength: 1,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: Colors.black26,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: _otpControllers[index].text.isNotEmpty
                      ? const Color(0xff00e6ff)
                      : Colors.white12,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(
                  color: Color(0xff00e6ff),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) {
              setState(() {});
              if (value.isNotEmpty) {
                if (index < 5) {
                  _otpFocusNodes[index + 1].requestFocus();
                } else {
                  _otpFocusNodes[index].unfocus();
                }
              } else {
                if (index > 0) {
                  _otpFocusNodes[index - 1].requestFocus();
                }
              }
            },
          ),
        );
      }),
    );
  }

  Widget _buildSimulatorColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 4,
          child: _buildCard(
            title: 'Fiziksel Bariyer Durumu',
            child: Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: ClipRect(
                        child: Stack(
                          children: [
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xff12182c),
                                    Color(0xff19223e),
                                  ],
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                height: 75,
                                color: const Color(0xff1d2335),
                                child: Stack(
                                  children: [
                                    Center(
                                      child: Container(
                                        height: 2,
                                        width: double.infinity,
                                        color: Colors.white24,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            Positioned(
                              bottom: 50,
                              left: 220,
                              child: Stack(
                                alignment: Alignment.bottomCenter,
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned(
                                    bottom: 70,
                                    child: Container(
                                      width: 24,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[700],
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 18,
                                    height: 70,
                                    color: Colors.grey[800],
                                  ),
                                  Positioned(
                                    bottom: 40,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: _barrierOpened
                                            ? const Color(0xff00ff87)
                                            : const Color(0xffff0055),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: _barrierOpened
                                                ? const Color(0xff00ff87)
                                                : const Color(0xffff0055),
                                            blurRadius: 10,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  Positioned(
                                    bottom: 50,
                                    left: 9,
                                    child: AnimatedRotation(
                                      turns: _barrierOpened ? -0.22 : 0.0,
                                      duration: const Duration(
                                        milliseconds: 1200,
                                      ),
                                      curve: Curves.easeInOutCubic,
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        width: 150,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Row(
                                          children: List.generate(6, (idx) {
                                            return Expanded(
                                              child: Container(
                                                color: idx % 2 == 0
                                                    ? Colors.red
                                                    : Colors.white,
                                              ),
                                            );
                                          }),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            AnimatedPositioned(
                              left: _carPositionLeft,
                              bottom: 30,
                              duration: Duration(
                                milliseconds: _carPositionLeft == 500
                                    ? 2000
                                    : 1200,
                              ),
                              curve: Curves.easeInOutQuad,
                              child: const Icon(
                                Icons.directions_car_filled_rounded,
                                size: 55,
                                color: Color(0xff00e6ff),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white12),
                        foregroundColor: Colors.white70,
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Bariyeri Kapat'),
                      onPressed: _closeBarrier,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        Expanded(
          flex: 6,
          child: _buildCard(
            title: 'Gişe Olay Konsolu',
            headerActions: [
              IconButton(
                icon: const Icon(
                  Icons.delete_sweep_outlined,
                  size: 18,
                  color: Colors.white70,
                ),
                tooltip: 'Konsolu Temizle',
                onPressed: _clearLogs,
              ),
            ],
            child: Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.03),
                  ),
                ),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, idx) {
                    final log = _logs[idx];

                    Color logColor = Colors.white70;
                    IconData icon = Icons.info_outline;
                    if (log.type == 'error') {
                      logColor = const Color(0xffff0055);
                      icon = Icons.error_outline;
                    } else if (log.type == 'success') {
                      logColor = const Color(0xff00ff87);
                      icon = Icons.check_circle_outline;
                    } else if (log.type == 'supabase') {
                      logColor = const Color(0xff00e6ff);
                      icon = Icons.cloud_queue_rounded;
                    } else if (log.type == 'sensor') {
                      logColor = const Color(0xffffd700);
                      icon = Icons.camera_alt_outlined;
                    }

                    final timeStr =
                        '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '[$timeStr] ',
                            style: GoogleFonts.shareTechMono(
                              color: Colors.white30,
                              fontSize: 13,
                            ),
                          ),
                          Icon(icon, size: 14, color: logColor),
                          const SizedBox(width: 4),
                          Text(
                            '${log.source}: ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: logColor,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              log.message,
                              style: TextStyle(fontSize: 13, color: logColor),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard({
    required String title,
    String? badgeText,
    Color? badgeColor,
    List<Widget>? headerActions,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  if (badgeText != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color:
                            badgeColor?.withValues(alpha: 0.12) ??
                            Colors.blue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color:
                              badgeColor?.withValues(alpha: 0.3) ?? Colors.blue,
                        ),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          color: badgeColor ?? Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (headerActions != null) Row(children: headerActions),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildPricingList() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff0f152d),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Son Geçişler ve Ücretler',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _recentArrivals.isEmpty
                ? const Center(
                    child: Text(
                      'Henüz geçiş yapan araç yok.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.separated(
                    itemCount: _recentArrivals.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10),
                    itemBuilder: (context, index) {
                      final item = _recentArrivals[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xff00e6ff,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.directions_car,
                            color: Color(0xff00e6ff),
                          ),
                        ),
                        title: Text(
                          item['plaka'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        trailing: Text(
                          '${item['price']} TL / Saatlik',
                          style: const TextStyle(
                            color: Color(0xff00ff88),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class ScanLaserLine extends StatefulWidget {
  const ScanLaserLine({super.key});

  @override
  State<ScanLaserLine> createState() => _ScanLaserLineState();
}

class _ScanLaserLineState extends State<ScanLaserLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: 0.05,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Align(
          alignment: Alignment(0.0, -1.0 + (_animation.value * 2)),
          child: Container(
            height: 2,
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xff00e6ff),
              boxShadow: [
                BoxShadow(
                  color: Color(0xff00e6ff),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
