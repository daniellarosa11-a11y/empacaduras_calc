// == main.dart (full app: Dashboard + Calculator + Orders + Presets) ==
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:shared_preferences/shared_preferences.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// PDF/Print
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

// Imágenes
import 'package:image_picker/image_picker.dart';

// Compartir CSV/imagen
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

// Web notifications (solo web)
/// Se usa en web para mostrar "Código listo ✨" al arrancar.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:html' as html;

// ---------- MODELOS BÁSICOS ----------
class ThicknessOption {
  String label; // "1.2 mm" o "1/32"
  double costPerSheetUSD; // costo de la lámina
  double profitPct; // % ganancia sobre SUBTOTAL
  double wastePct; // % merma sobre área
  double minPriceUSD; // precio mínimo por pieza

  ThicknessOption({
    required this.label,
    required this.costPerSheetUSD,
    this.profitPct = 0.0,
    this.wastePct = 0.0,
    this.minPriceUSD = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'costPerSheetUSD': costPerSheetUSD,
    'profitPct': profitPct,
    'wastePct': wastePct,
    'minPriceUSD': minPriceUSD,
  };

  factory ThicknessOption.fromJson(Map<String, dynamic> j) => ThicknessOption(
    label: j['label'] as String,
    costPerSheetUSD: (j['costPerSheetUSD'] as num).toDouble(),
    profitPct: j['profitPct'] == null
        ? 0.0
        : (j['profitPct'] as num).toDouble(),
    wastePct: j['wastePct'] == null ? 0.0 : (j['wastePct'] as num).toDouble(),
    minPriceUSD: j['minPriceUSD'] == null
        ? 0.0
        : (j['minPriceUSD'] as num).toDouble(),
  );
}

class MaterialConfig {
  String id; // "camara", "amianto", etc.
  String name; // visible
  double sheetWidthCm; // ancho lámina (cm)
  double sheetHeightCm; // alto lámina (cm)
  List<ThicknessOption> options;

  MaterialConfig({
    required this.id,
    required this.name,
    required this.sheetWidthCm,
    required this.sheetHeightCm,
    required this.options,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sheetWidthCm': sheetWidthCm,
    'sheetHeightCm': sheetHeightCm,
    'options': options.map((e) => e.toJson()).toList(),
  };

  factory MaterialConfig.fromJson(Map<String, dynamic> j) => MaterialConfig(
    id: j['id'] as String,
    name: j['name'] as String,
    sheetWidthCm: (j['sheetWidthCm'] as num).toDouble(),
    sheetHeightCm: (j['sheetHeightCm'] as num).toDouble(),
    options: (j['options'] as List)
        .map((e) => ThicknessOption.fromJson(e))
        .toList(),
  );
}

/// Preset de pieza con metadatos y foto
class PiecePreset {
  String name;
  double widthCm;
  double heightCm;

  String? brand; // Marca de motor
  String? enginePlace; // Lugar del motor
  String? ringSize; // Tamaño del anillo (si aplica)
  String? notes; // Notas
  String? imageB64; // Foto en base64 (opcional)

  PiecePreset({
    required this.name,
    required this.widthCm,
    required this.heightCm,
    this.brand,
    this.enginePlace,
    this.ringSize,
    this.notes,
    this.imageB64,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'widthCm': widthCm,
    'heightCm': heightCm,
    'brand': brand,
    'enginePlace': enginePlace,
    'ringSize': ringSize,
    'notes': notes,
    'imageB64': imageB64,
  };

  factory PiecePreset.fromJson(Map<String, dynamic> j) => PiecePreset(
    name: j['name'] as String,
    widthCm: (j['widthCm'] as num).toDouble(),
    heightCm: (j['heightCm'] as num).toDouble(),
    brand: j['brand'] as String?,
    enginePlace: j['enginePlace'] as String?,
    ringSize: j['ringSize'] as String?,
    notes: j['notes'] as String?,
    imageB64: j['imageB64'] as String?,
  );
}

/// Registro simple para el historial de cotizaciones
class QuoteRecord {
  String material;
  String thickness;
  double widthCm;
  double heightCm;
  double hours;
  double total;
  String timestamp; // ISO8601

  QuoteRecord({
    required this.material,
    required this.thickness,
    required this.widthCm,
    required this.heightCm,
    required this.hours,
    required this.total,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'material': material,
    'thickness': thickness,
    'widthCm': widthCm,
    'heightCm': heightCm,
    'hours': hours,
    'total': total,
    'timestamp': timestamp,
  };

  factory QuoteRecord.fromJson(Map<String, dynamic> j) => QuoteRecord(
    material: j['material'] as String,
    thickness: j['thickness'] as String,
    widthCm: (j['widthCm'] as num).toDouble(),
    heightCm: (j['heightCm'] as num).toDouble(),
    hours: (j['hours'] as num).toDouble(),
    total: (j['total'] as num).toDouble(),
    timestamp: j['timestamp'] as String,
  );
}

// --------- ÓRDENES ----------
enum PaymentMethod {
  usd, // efectivo USD
  eur, // efectivo EUR
  pagomovil, // requiere referencia
  transferencia, // requiere referencia
  bs, // bolívares en efectivo
  other, // texto libre
}

class WorkOrder {
  String id; // simple uuid
  String clientName;
  String phone;
  String cedula;
  String description;
  String material;
  String thickness;
  double price;
  double abono;
  String paymentRef; // referencia o nota
  PaymentMethod method;
  String photoB64; // de la pieza entregada
  String createdBy;
  String timestamp; // ISO-8601 (America/Caracas deseado)

  WorkOrder({
    required this.id,
    required this.clientName,
    required this.phone,
    required this.cedula,
    required this.description,
    required this.material,
    required this.thickness,
    required this.price,
    required this.abono,
    required this.paymentRef,
    required this.method,
    required this.photoB64,
    required this.createdBy,
    required this.timestamp,
  });

  double get due => math.max(0, (price - abono));

  bool get isPaid => due <= 0.000001;

  Map<String, dynamic> toJson() => {
    'id': id,
    'clientName': clientName,
    'phone': phone,
    'cedula': cedula,
    'description': description,
    'material': material,
    'thickness': thickness,
    'price': price,
    'abono': abono,
    'paymentRef': paymentRef,
    'method': method.name,
    'photoB64': photoB64,
    'createdBy': createdBy,
    'timestamp': timestamp,
  };

  factory WorkOrder.fromJson(Map<String, dynamic> j) => WorkOrder(
    id: j['id'] as String,
    clientName: j['clientName'] as String,
    phone: j['phone'] as String,
    cedula: j['cedula'] as String,
    description: j['description'] as String,
    material: j['material'] as String,
    thickness: j['thickness'] as String,
    price: (j['price'] as num).toDouble(),
    abono: (j['abono'] as num).toDouble(),
    paymentRef: j['paymentRef'] as String,
    method: PaymentMethod.values.firstWhere(
      (e) => e.name == (j['method'] as String),
      orElse: () => PaymentMethod.usd,
    ),
    photoB64: j['photoB64'] as String? ?? '',
    createdBy: j['createdBy'] as String? ?? '',
    timestamp: j['timestamp'] as String,
  );
}

// ---------- APP ----------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Notificación al cargar (web)
  _notifyWeb('Código listo ✨', 'La app está lista. Puedes continuar.');
  runApp(const MyApp());
}

Future<void> _notifyWeb(String title, String body) async {
  if (!kIsWeb) return;
  try {
    if (html.Notification.supported) {
      var permission =
          html.Notification.permission; // "default" | "granted" | "denied"
      if (permission != 'granted') {
        permission = await html.Notification.requestPermission();
      }
      if (permission == 'granted') {
        html.Notification(title, body: body);
      }
    }
  } catch (_) {}
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Empacaduras',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const DashboardHome(),
    );
  }
}

// ================= DASHBOARD =================
class DashboardHome extends StatefulWidget {
  const DashboardHome({super.key});
  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome> {
  // Estado de admin para toda la app (simple)
  bool _isAdminAuthed = false;
  String _adminUser = 'admin';
  String _adminPassEnc = base64.encode(utf8.encode('1234'));

  @override
  void initState() {
    super.initState();
    _loadCreds();
  }

  Future<void> _loadCreds() async {
    final prefs = await SharedPreferences.getInstance();
    _adminUser = prefs.getString('adminUser') ?? 'admin';
    _adminPassEnc =
        prefs.getString('adminPassEnc') ?? base64.encode(utf8.encode('1234'));
    setState(() {});
  }

  Future<void> _pingFirebase(BuildContext context) async {
    try {
      final col = FirebaseFirestore.instance.collection('_diagnostics');
      final ref = await col.add({
        'createdAt': FieldValue.serverTimestamp(),
        'platform': kIsWeb ? 'web' : 'android',
        'app': 'empacaduras_calc',
      });
      final snap = await ref.get();
      final serverTime = snap.data()?['createdAt'];
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Firebase OK ✅ (ts=$serverTime)')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Firebase ERROR: $e')));
    }
  }

  Future<bool> _promptAdminLogin() async {
    final uCtrl = TextEditingController();
    final pCtrl = TextEditingController();
    bool ok = false;
    if (!mounted) return false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Iniciar sesión (administrador)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: uCtrl,
              decoration: const InputDecoration(labelText: 'Usuario'),
            ),
            TextField(
              controller: pCtrl,
              decoration: const InputDecoration(labelText: 'Contraseña'),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            const Text(
              'Usuario por defecto "admin" y clave "1234".',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final userOk = uCtrl.text.trim() == _adminUser;
              final passOk =
                  base64.encode(utf8.encode(pCtrl.text.trim())) ==
                  _adminPassEnc;
              if (!userOk || !passOk) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Usuario o contraseña incorrectos'),
                  ),
                );
                return;
              }
              ok = true;
              Navigator.pop(ctx);
            },
            child: const Text('Entrar'),
          ),
        ],
      ),
    );
    if (ok) setState(() => _isAdminAuthed = true);
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      _dashCard(
        context,
        title: 'Calculadora de precios',
        icon: Icons.calculate,
        color: Colors.teal,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PriceCalculatorPage(
              isAdminAuthed: _isAdminAuthed,
              onRequestAdmin: _promptAdminLogin,
            ),
          ),
        ),
      ),
      _dashCard(
        context,
        title: 'Órdenes de trabajo',
        icon: Icons.assignment_rounded,
        color: Colors.indigo,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrdersPage(
              currentUser: _isAdminAuthed ? _adminUser : 'Operador',
            ),
          ),
        ),
      ),
      _dashCard(
        context,
        title: 'Presets',
        icon: Icons.bookmarks_outlined,
        color: Colors.orange,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PresetsStandalonePage(
              isAdmin: _isAdminAuthed,
              onRequestAdmin: _promptAdminLogin,
            ),
          ),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Empacaduras'),
        actions: [
          IconButton(
            tooltip: 'Ping Firebase',
            onPressed: () => _pingFirebase(context),
            icon: const Icon(Icons.cloud_done),
          ),
          if (_isAdminAuthed)
            IconButton(
              tooltip: 'Cerrar sesión admin',
              onPressed: () => setState(() => _isAdminAuthed = false),
              icon: const Icon(Icons.lock_open),
            )
          else
            IconButton(
              tooltip: 'Iniciar sesión admin',
              onPressed: _promptAdminLogin,
              icon: const Icon(Icons.lock_outline),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (ctx, c) {
          final isWide = c.maxWidth >= 720;
          return GridView.count(
            padding: const EdgeInsets.all(16),
            crossAxisCount: isWide ? 3 : 1,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            children: cards,
          );
        },
      ),
    );
  }

  Widget _dashCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 44, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= CALCULADORA =================
class PriceCalculatorPage extends StatefulWidget {
  final bool isAdminAuthed;
  final Future<bool> Function() onRequestAdmin;

  const PriceCalculatorPage({
    super.key,
    required this.isAdminAuthed,
    required this.onRequestAdmin,
  });

  @override
  State<PriceCalculatorPage> createState() => _PriceCalculatorPageState();
}

class _PriceCalculatorPageState extends State<PriceCalculatorPage> {
  final _formKey = GlobalKey<FormState>();

  final _widthCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController(text: '0');

  List<MaterialConfig> _materials = [];
  String? _selectedMaterialId;
  int _selectedThicknessIndex = 0;
  double _hourlyRate = 6.0; // USD/h

  // Redondeo global (0 = desactivado)
  double _roundingStepUSD = 0.0;

  // Auth (usa el del dashboard)
  bool get _isAdminAuthed => widget.isAdminAuthed;

  // Resultados
  double? _areaBaseCm2;
  double? _areaWithWasteCm2;
  double? _pricePerCm2;
  double? _materialCost;
  double? _laborCost;
  double? _total;
  bool _appliedMin = false;
  bool _appliedRounding = false;

  // Historial
  List<QuoteRecord> _history = [];

  // Presets
  List<PiecePreset> _presets = [];
  int _selectedPresetIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _hoursCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString('materialsData');
    final savedRate = prefs.getDouble('hourlyRate');
    final savedStep = prefs.getDouble('roundingStepUSD');
    final histRaw = prefs.getString('quotesHistory');
    final presetsRaw = prefs.getString('piecePresets');

    if (savedRate != null) _hourlyRate = savedRate;
    if (savedStep != null) _roundingStepUSD = savedStep;

    if (raw == null) {
      _materials = _defaultMaterials();
      await prefs.setString(
        'materialsData',
        jsonEncode(_materials.map((m) => m.toJson()).toList()),
      );
    } else {
      try {
        final list = jsonDecode(raw) as List;
        _materials = list.map((e) => MaterialConfig.fromJson(e)).toList();
      } catch (_) {
        _materials = _defaultMaterials();
      }
    }

    // Historial
    if (histRaw != null) {
      try {
        final list = jsonDecode(histRaw) as List;
        _history = list.map((e) => QuoteRecord.fromJson(e)).toList();
      } catch (_) {
        _history = [];
      }
    }

    // Presets
    if (presetsRaw != null) {
      try {
        final list = jsonDecode(presetsRaw) as List;
        _presets = list.map((e) => PiecePreset.fromJson(e)).toList();
      } catch (_) {
        _presets = _defaultPresets();
      }
    } else {
      _presets = _defaultPresets();
    }

    _selectedMaterialId = _materials.first.id;
    _selectedThicknessIndex = 0;
    setState(() {});
  }

  List<PiecePreset> _defaultPresets() => [
    PiecePreset(name: '10 x 10 cm', widthCm: 10, heightCm: 10),
    PiecePreset(name: '15 x 20 cm', widthCm: 15, heightCm: 20),
    PiecePreset(name: '20 x 30 cm', widthCm: 20, heightCm: 30),
  ];

  Future<void> _savePresets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'piecePresets',
      jsonEncode(_presets.map((e) => e.toJson()).toList()),
    );
  }

  List<MaterialConfig> _defaultMaterials() {
    return [
      MaterialConfig(
        id: 'camara',
        name: 'Cámara',
        sheetWidthCm: 50,
        sheetHeightCm: 120,
        options: [
          ThicknessOption(label: '1.2 mm', costPerSheetUSD: 15.0),
          ThicknessOption(label: '1.6 mm', costPerSheetUSD: 17.5),
          ThicknessOption(label: '2.0 mm', costPerSheetUSD: 19.0),
          ThicknessOption(label: '2.5 mm', costPerSheetUSD: 20.0),
          ThicknessOption(label: '3.0 mm', costPerSheetUSD: 38.7),
          ThicknessOption(label: '3.5 mm', costPerSheetUSD: 44.0),
          ThicknessOption(label: '4.0 mm', costPerSheetUSD: 68.0),
          ThicknessOption(label: '4.5 mm', costPerSheetUSD: 92.0),
        ],
      ),
      MaterialConfig(
        id: 'amianto',
        name: 'Amianto',
        sheetWidthCm: 150,
        sheetHeightCm: 150,
        options: [
          ThicknessOption(label: '1/64', costPerSheetUSD: 0.0),
          ThicknessOption(label: '1/32', costPerSheetUSD: 0.0),
          ThicknessOption(label: '1/16', costPerSheetUSD: 0.0),
          ThicknessOption(label: '1/8', costPerSheetUSD: 0.0),
          ThicknessOption(label: '3/32', costPerSheetUSD: 0.0),
          ThicknessOption(label: '1/4', costPerSheetUSD: 0.0),
        ],
      ),
      MaterialConfig(
        id: 'velumoide',
        name: 'Velumoide',
        sheetWidthCm: 100,
        sheetHeightCm: 100,
        options: [
          ThicknessOption(label: '1/64', costPerSheetUSD: 0.0),
          ThicknessOption(label: '1/32', costPerSheetUSD: 0.0),
          ThicknessOption(label: '1/16', costPerSheetUSD: 0.0),
        ],
      ),
      MaterialConfig(
        id: 'corcho',
        name: 'Corcho',
        sheetWidthCm: 100,
        sheetHeightCm: 100,
        options: [
          ThicknessOption(label: '2 mm', costPerSheetUSD: 0.0),
          ThicknessOption(label: '4 mm', costPerSheetUSD: 0.0),
        ],
      ),
    ];
  }

  MaterialConfig get _currentMaterial =>
      _materials.firstWhere((m) => m.id == _selectedMaterialId);

  ThicknessOption? get _currentThicknessOption {
    final opts = _currentMaterial.options;
    if (opts.isEmpty) return null;
    if (_selectedThicknessIndex < 0 || _selectedThicknessIndex >= opts.length) {
      return null;
    }
    return opts[_selectedThicknessIndex];
  }

  bool get _isConfigReady {
    final m = _currentMaterial;
    final th = _currentThicknessOption;
    return m.sheetWidthCm > 0 &&
        m.sheetHeightCm > 0 &&
        th != null &&
        th.costPerSheetUSD > 0;
  }

  double _parseNum(TextEditingController c) {
    final s = c.text.trim().replaceAll(',', '.');
    if (s.isEmpty) return 0.0;
    return double.tryParse(s) ?? 0.0;
  }

  double _parseFromDialog(String s) {
    return double.tryParse(s.trim().replaceAll(',', '.')) ?? 0.0;
  }

  void _calculate() {
    if (!_formKey.currentState!.validate()) return;

    final mat = _currentMaterial;
    final th = _currentThicknessOption;

    if (mat.sheetWidthCm <= 0 || mat.sheetHeightCm <= 0) {
      _showSnack('Configura el tamaño de la lámina para ${mat.name}.');
      return;
    }
    if (th == null || th.costPerSheetUSD <= 0) {
      _showSnack('Configura el costo de lámina para el espesor seleccionado.');
      return;
    }

    final width = _parseNum(_widthCtrl);
    final height = _parseNum(_heightCtrl);
    final hours = _parseNum(_hoursCtrl);

    if (width <= 0 || height <= 0) {
      _showSnack('Ancho y Largo deben ser mayores que 0.');
      return;
    }

    final areaBaseCm2 = width * height;
    final sheetAreaCm2 = mat.sheetWidthCm * mat.sheetHeightCm;
    final pricePerCm2 = th.costPerSheetUSD / sheetAreaCm2;

    final areaWithWasteCm2 = areaBaseCm2 * (1 + (th.wastePct / 100.0));
    final materialCost = areaWithWasteCm2 * pricePerCm2;
    final laborCost = hours * _hourlyRate;

    final subtotal = materialCost + laborCost;
    final totalRaw = subtotal * (1 + (th.profitPct / 100.0));

    double total = totalRaw;
    _appliedMin = false;
    _appliedRounding = false;

    if (th.minPriceUSD > 0 && total < th.minPriceUSD) {
      total = th.minPriceUSD;
      _appliedMin = true;
    }
    if (_roundingStepUSD > 0) {
      total = _roundToStep(total, _roundingStepUSD);
      _appliedRounding = true;
    }

    setState(() {
      _areaBaseCm2 = areaBaseCm2;
      _areaWithWasteCm2 = areaWithWasteCm2;
      _pricePerCm2 = pricePerCm2;
      _materialCost = materialCost;
      _laborCost = laborCost;
      _total = total;
    });

    // Historial (máx 100)
    final rec = QuoteRecord(
      material: mat.name,
      thickness: th.label,
      widthCm: width,
      heightCm: height,
      hours: hours,
      total: total,
      timestamp: DateTime.now().toIso8601String(),
    );
    _history.insert(0, rec);
    if (_history.length > 100) {
      _history = _history.sublist(0, 100);
    }
    _saveHistory();
  }

  double _roundToStep(double value, double step) {
    if (step <= 0) return value;
    return (value / step).round() * step;
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'quotesHistory',
      jsonEncode(_history.map((e) => e.toJson()).toList()),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ====== EDITOR DE MATERIAL ======
  Future<void> _openMaterialEditor() async {
    final mat = _currentMaterial;

    final widthCtrl = TextEditingController(text: _fmt(mat.sheetWidthCm));
    final heightCtrl = TextEditingController(text: _fmt(mat.sheetHeightCm));

    // Controllers por espesor
    final costCtrls = [
      for (final o in mat.options)
        TextEditingController(text: _fmt(o.costPerSheetUSD)),
    ];
    final profitCtrls = [
      for (final o in mat.options)
        TextEditingController(text: _fmt(o.profitPct)),
    ];
    final wasteCtrls = [
      for (final o in mat.options)
        TextEditingController(text: _fmt(o.wastePct)),
    ];
    final minCtrls = [
      for (final o in mat.options)
        TextEditingController(text: _fmt(o.minPriceUSD)),
    ];

    // Aplicar a todos
    final bulkProfitCtrl = TextEditingController();
    final bulkWasteCtrl = TextEditingController();
    final bulkMinCtrl = TextEditingController();

    // Solo números con . o , (sin -)
    final numberInput = <TextInputFormatter>[
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      FilteringTextInputFormatter.deny(RegExp(r'-')),
    ];

    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.8,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Encabezado
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Editar ${mat.name}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Tamaño de lámina
                      const Text(
                        'Tamaño de lámina (cm)',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: widthCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Ancho',
                                suffixText: ' cm',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: numberInput,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: heightCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Alto',
                                suffixText: ' cm',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: numberInput,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 6),

                      // Barra "Aplicar a todos"
                      Row(
                        children: [
                          const Icon(Icons.tune, size: 20),
                          const SizedBox(width: 8),
                          const Text('Aplicar a todos los espesores'),
                          const Spacer(),
                          SizedBox(
                            width: 140,
                            child: TextField(
                              controller: bulkProfitCtrl,
                              textAlign: TextAlign.right,
                              decoration: const InputDecoration(
                                labelText: 'Ganancia %',
                                border: OutlineInputBorder(),
                                suffixText: ' %',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: numberInput,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 140,
                            child: TextField(
                              controller: bulkWasteCtrl,
                              textAlign: TextAlign.right,
                              decoration: const InputDecoration(
                                labelText: 'Merma %',
                                border: OutlineInputBorder(),
                                suffixText: ' %',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: numberInput,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 150,
                            child: TextField(
                              controller: bulkMinCtrl,
                              textAlign: TextAlign.right,
                              decoration: const InputDecoration(
                                labelText: 'Mínimo USD',
                                border: OutlineInputBorder(),
                                prefixText: '\$ ',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: numberInput,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () {
                              final p = _parseFromDialog(bulkProfitCtrl.text);
                              final w = _parseFromDialog(bulkWasteCtrl.text);
                              final m = _parseFromDialog(bulkMinCtrl.text);
                              setState(() {
                                for (int i = 0; i < mat.options.length; i++) {
                                  if (bulkProfitCtrl.text.trim().isNotEmpty) {
                                    profitCtrls[i].text = _fmt(p);
                                  }
                                  if (bulkWasteCtrl.text.trim().isNotEmpty) {
                                    wasteCtrls[i].text = _fmt(w);
                                  }
                                  if (bulkMinCtrl.text.trim().isNotEmpty) {
                                    minCtrls[i].text = _fmt(m);
                                  }
                                }
                              });
                            },
                            icon: const Icon(Icons.content_paste_go),
                            label: const Text('Aplicar'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      const Text(
                        'Parámetros por espesor',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),

                      // Tabla
                      SizedBox(
                        height: 420,
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: 820,
                                ),
                                child: DataTable(
                                  headingRowHeight: 44,
                                  dataRowMinHeight: 48,
                                  dataRowMaxHeight: 56,
                                  columns: const [
                                    DataColumn(label: Text('Espesor')),
                                    DataColumn(label: Text('Costo (USD)')),
                                    DataColumn(label: Text('Ganancia %')),
                                    DataColumn(label: Text('Merma %')),
                                    DataColumn(label: Text('Mínimo (USD)')),
                                  ],
                                  rows: List.generate(mat.options.length, (i) {
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(mat.options[i].label)),
                                        DataCell(
                                          SizedBox(
                                            width: 130,
                                            child: TextField(
                                              controller: costCtrls[i],
                                              textAlign: TextAlign.right,
                                              decoration: const InputDecoration(
                                                prefixText: '\$ ',
                                                border: OutlineInputBorder(),
                                              ),
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              inputFormatters: numberInput,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          SizedBox(
                                            width: 130,
                                            child: TextField(
                                              controller: profitCtrls[i],
                                              textAlign: TextAlign.right,
                                              decoration: const InputDecoration(
                                                suffixText: ' %',
                                                border: OutlineInputBorder(),
                                              ),
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              inputFormatters: numberInput,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          SizedBox(
                                            width: 130,
                                            child: TextField(
                                              controller: wasteCtrls[i],
                                              textAlign: TextAlign.right,
                                              decoration: const InputDecoration(
                                                suffixText: ' %',
                                                border: OutlineInputBorder(),
                                              ),
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              inputFormatters: numberInput,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          SizedBox(
                                            width: 140,
                                            child: TextField(
                                              controller: minCtrls[i],
                                              textAlign: TextAlign.right,
                                              decoration: const InputDecoration(
                                                prefixText: '\$ ',
                                                border: OutlineInputBorder(),
                                              ),
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              inputFormatters: numberInput,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () async {
                              final w = _parseFromDialog(widthCtrl.text);
                              final h = _parseFromDialog(heightCtrl.text);
                              if (w <= 0 || h <= 0) {
                                _showSnack(
                                  'Ancho/Alto de lámina deben ser > 0',
                                );
                                return;
                              }
                              for (int i = 0; i < mat.options.length; i++) {
                                final c = _parseFromDialog(costCtrls[i].text);
                                final p = _parseFromDialog(profitCtrls[i].text);
                                final wa = _parseFromDialog(wasteCtrls[i].text);
                                final mi = _parseFromDialog(minCtrls[i].text);
                                if (c < 0 || p < 0 || wa < 0 || mi < 0) {
                                  _showSnack(
                                    'Valores negativos en la fila ${i + 1}.',
                                  );
                                  return;
                                }
                              }
                              mat.sheetWidthCm = w;
                              mat.sheetHeightCm = h;
                              for (int i = 0; i < mat.options.length; i++) {
                                mat.options[i].costPerSheetUSD =
                                    _parseFromDialog(costCtrls[i].text);
                                mat.options[i].profitPct = _parseFromDialog(
                                  profitCtrls[i].text,
                                );
                                mat.options[i].wastePct = _parseFromDialog(
                                  wasteCtrls[i].text,
                                );
                                mat.options[i].minPriceUSD = _parseFromDialog(
                                  minCtrls[i].text,
                                );
                              }
                              await _saveMaterials();
                              if (mounted) Navigator.pop(ctx);
                              setState(() {});
                            },
                            child: const Text('Guardar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Duplicar material actual (copia profunda)  **PARCHE incluida**
  Future<void> _duplicateCurrentMaterialDialog() async {
    final base = _currentMaterial;
    final nameCtrl = TextEditingController(text: '${base.name} (copia)');
    final idCtrl = TextEditingController(
      text: _slugFromName('${base.id}_copy'),
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Duplicar material actual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre visible'),
            ),
            TextField(
              controller: idCtrl,
              decoration: const InputDecoration(
                labelText: 'ID interno (único, sin espacios)',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Se copiarán tamaños de lámina y todos los espesores con sus parámetros.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              final newId = _slugFromName(idCtrl.text.trim());
              if (newName.isEmpty || newId.isEmpty) {
                _showSnack('Nombre e ID no pueden estar vacíos.');
                return;
              }
              if (_materials.any((m) => m.id == newId)) {
                _showSnack('El ID ya existe. Usa otro.');
                return;
              }
              final dup = MaterialConfig(
                id: newId,
                name: newName,
                sheetWidthCm: base.sheetWidthCm,
                sheetHeightCm: base.sheetHeightCm,
                options: base.options
                    .map(
                      (o) => ThicknessOption(
                        label: o.label,
                        costPerSheetUSD: o.costPerSheetUSD,
                        profitPct: o.profitPct,
                        wastePct: o.wastePct,
                        minPriceUSD: o.minPriceUSD,
                      ),
                    )
                    .toList(),
              );
              _materials.add(dup);
              _selectedMaterialId = dup.id;
              _selectedThicknessIndex = 0;
              await _saveMaterials();
              if (mounted) Navigator.pop(ctx);
              setState(() {});
              _showSnack('Material duplicado.');
            },
            child: const Text('Duplicar'),
          ),
        ],
      ),
    );
  }

  String _slugFromName(String s) {
    final t = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
    return t.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  }

  Future<void> _saveMaterials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'materialsData',
      jsonEncode(_materials.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> _editHourlyRate() async {
    if (!_isAdminAuthed) {
      _showSnack('Requiere permisos de administrador.');
      return;
    }
    final c = TextEditingController(text: _fmt(_hourlyRate));
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tarifa por hora (USD)'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(prefixText: '\$ '),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              _hourlyRate = _parseFromDialog(c.text);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setDouble('hourlyRate', _hourlyRate);
              if (mounted) Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  String _fmt(num v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
  String _fmtSmart(num v) {
    final a = v.abs();
    if (a == a.truncateToDouble()) return v.toStringAsFixed(0);
    if (a < 0.001) return v.toStringAsFixed(6);
    if (a < 0.01) return v.toStringAsFixed(4);
    return v.toStringAsFixed(2);
  }

  String? _positiveValidator(String? s) {
    final v = double.tryParse((s ?? '').trim().replaceAll(',', '.')) ?? -1;
    if (v <= 0) return 'Debe ser un número > 0';
    return null;
  }

  String? _nonNegativeValidator(String? s) {
    final v = double.tryParse((s ?? '').trim().replaceAll(',', '.')) ?? -1;
    if (v < 0) return 'No puede ser negativo';
    return null;
  }

  // --------- UI ----------
  @override
  Widget build(BuildContext context) {
    final presetSelected =
        (_selectedPresetIndex >= 0 && _selectedPresetIndex < _presets.length)
        ? _presets[_selectedPresetIndex]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculadora de Empacaduras'),
        actions: [
          IconButton(
            tooltip: 'Historial de cotizaciones',
            onPressed: _openHistorySheet,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Gestionar presets',
            onPressed: _openPresetManagerPage,
            icon: const Icon(Icons.bookmarks_outlined),
          ),
          IconButton(
            tooltip: 'Editar tarifa por hora',
            onPressed: _editHourlyRate,
            icon: const Icon(Icons.timer),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'priceCfg') {
                await _openPriceSettings();
              } else if (v == 'backup') {
                await _openBackupDialog();
              } else if (v == 'duplicate') {
                await _duplicateCurrentMaterialDialog();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'priceCfg',
                child: Text('Ajustes de precio (redondeo)'),
              ),
              PopupMenuItem(
                value: 'backup',
                child: Text('Respaldo (exportar/importar)'),
              ),
              PopupMenuItem(
                value: 'duplicate',
                child: Text('Duplicar material actual'),
              ),
            ],
            icon: const Icon(Icons.more_vert),
            tooltip: 'Opciones',
          ),
        ],
      ),
      body: _materials.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                final form = _buildForm();
                final result = _buildResults(presetSelected);
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: SingleChildScrollView(child: form)),
                      const VerticalDivider(width: 1),
                      Expanded(child: SingleChildScrollView(child: result)),
                    ],
                  );
                }
                return SingleChildScrollView(
                  child: Column(
                    children: [form, const Divider(height: 32), result],
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isConfigReady ? _calculate : null,
                  icon: const Icon(Icons.calculate),
                  label: const Text('Calcular'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _total == null ? null : _createOrderFromCalc,
                  icon: const Icon(Icons.assignment_add),
                  label: const Text('Guardar orden'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------- Formulario principal --------
  Widget _buildForm() {
    final mat = _currentMaterial;
    final thicknesses = mat.options;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedMaterialId,
                    decoration: const InputDecoration(labelText: 'Material'),
                    items: [
                      for (final m in _materials)
                        DropdownMenuItem(value: m.id, child: Text(m.name)),
                    ],
                    onChanged: (v) => setState(() {
                      _selectedMaterialId = v;
                      _selectedThicknessIndex = 0;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () async => await _openMaterialEditor(),
                  icon: const Icon(Icons.settings),
                  label: const Text('Configurar material'),
                ),
              ],
            ),
            if (!_isConfigReady)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.redAccent),
                    SizedBox(width: 6),
                    Text(
                      'Completa tamaño de lámina y costo del espesor.',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // Espesor
            if (thicknesses.isNotEmpty)
              DropdownButtonFormField<int>(
                value: _selectedThicknessIndex,
                decoration: const InputDecoration(labelText: 'Espesor'),
                items: [
                  for (int i = 0; i < thicknesses.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(thicknesses[i].label),
                    ),
                ],
                onChanged: (v) =>
                    setState(() => _selectedThicknessIndex = v ?? 0),
              ),
            const SizedBox(height: 8),

            // Info costo lámina
            if (_currentThicknessOption != null)
              Row(
                children: [
                  const Text(
                    'Costo lámina (espesor): ',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text('\$${_fmt(_currentThicknessOption!.costPerSheetUSD)}'),
                ],
              ),

            const SizedBox(height: 16),

            // Preset de pieza (selector en diálogo)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _presets.isEmpty ? null : _pickPresetDialog,
                    icon: const Icon(Icons.list_alt),
                    label: Text(
                      _selectedPresetIndex >= 0 &&
                              _selectedPresetIndex < _presets.length
                          ? 'Preset: ${_presets[_selectedPresetIndex].name}'
                          : 'Elegir preset…',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _openPresetManagerPage,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Gestionar'),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Dimensiones
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _widthCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ancho de la pieza (cm)',
                      helperText: 'Ej.: 10.5',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _positiveValidator,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _heightCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Largo de la pieza (cm)',
                      helperText: 'Ej.: 8',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _positiveValidator,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Horas
            TextFormField(
              controller: _hoursCtrl,
              decoration: InputDecoration(
                labelText: 'Horas trabajadas',
                helperText: 'Tarifa actual: \$${_fmt(_hourlyRate)}/h',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: _nonNegativeValidator,
            ),

            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _createPresetFromCurrent,
                icon: const Icon(Icons.bookmark_add),
                label: const Text('Guardar como preset'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------- Resultados --------
  Widget _buildResults(PiecePreset? presetSelected) {
    final th = _currentThicknessOption;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resultados',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _kv('Material', _currentMaterial.name),
          if (th != null) _kv('Espesor', th.label),
          _kv(
            'Tamaño lámina (cm)',
            '${_fmt(_currentMaterial.sheetWidthCm)} × ${_fmt(_currentMaterial.sheetHeightCm)}',
          ),
          const Divider(height: 24),
          Text(
            _total != null ? 'TOTAL: \$${_fmt(_total!)}' : 'TOTAL: -',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _kv(
            'Área base (cm²)',
            _areaBaseCm2 != null ? _fmt(_areaBaseCm2!) : '-',
          ),
          _kv(
            'Área con merma (cm²)',
            _areaWithWasteCm2 != null ? _fmt(_areaWithWasteCm2!) : '-',
          ),
          _kv(
            'Precio por cm² (USD)',
            _pricePerCm2 != null ? _fmtSmart(_pricePerCm2!) : '-',
          ),
          _kv(
            'Costo material (USD)',
            _materialCost != null ? _fmt(_materialCost!) : '-',
          ),
          _kv(
            'Costo mano de obra (USD)',
            _laborCost != null ? _fmt(_laborCost!) : '-',
          ),
          if (_appliedMin && th != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Se aplicó mínimo por pieza: \$${_fmt(th.minPriceUSD)}',
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          if (_appliedRounding && _roundingStepUSD > 0)
            Text(
              'Redondeado a múltiplos de \$${_fmt(_roundingStepUSD)}',
              style: const TextStyle(color: Colors.black54),
            ),
          const SizedBox(height: 12),

          // Foto del preset seleccionado
          if (presetSelected?.imageB64 != null) ...[
            const Text(
              'Foto del preset',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                base64Decode(presetSelected!.imageB64!),
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Botones PDF
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _total == null ? null : _printPreviewPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Vista previa / Imprimir PDF'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _total == null ? null : _sharePdf,
                icon: const Icon(Icons.ios_share),
                label: const Text('Compartir / Guardar PDF'),
              ),
            ],
          ),

          const SizedBox(height: 8),
          const Text(
            'Nota: Ganancia, Merma y Mínimo se configuran por **espesor** dentro de "Configurar material".',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  // --- Presets ---
  Future<void> _openPresetManagerPage() async {
    final updated = await Navigator.push<List<PiecePreset>>(
      context,
      MaterialPageRoute(
        builder: (_) => PresetManagerPage(
          initial: List<PiecePreset>.from(_presets),
          isAdmin: _isAdminAuthed,
          onRequestAdmin: widget.onRequestAdmin,
        ),
      ),
    );
    if (updated != null) {
      setState(() => _presets = updated);
      await _savePresets();
    }
  }

  Future<void> _pickPresetDialog() async {
    final searchCtrl = TextEditingController();
    int? selectedIndex;

    final pickedIndex = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final q = searchCtrl.text.trim().toLowerCase();
          final indexed = _presets.asMap().entries.where((e) {
            final p = e.value;
            bool hit(String? s) => (s ?? '').toLowerCase().contains(q);
            final hay =
                hit(p.name) ||
                hit(p.brand) ||
                hit(p.enginePlace) ||
                hit(p.ringSize) ||
                hit(p.notes);
            return q.isEmpty ? true : hay;
          }).toList();

          return AlertDialog(
            title: const Text('Elegir preset de pieza'),
            content: SizedBox(
              width: 520,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nombre/marca/lugar/anillo/notas…',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setS(() {}),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: indexed.isEmpty
                        ? const Center(child: Text('Sin resultados'))
                        : ListView.separated(
                            itemCount: indexed.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final realIndex = indexed[i].key;
                              final p = indexed[i].value;
                              final thumb = p.imageB64 == null
                                  ? null
                                  : base64Decode(p.imageB64!);
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: thumb == null
                                      ? null
                                      : MemoryImage(thumb),
                                  child: thumb == null
                                      ? const Icon(Icons.photo)
                                      : null,
                                ),
                                title: Text(p.name),
                                subtitle: Text(
                                  '${_fmt(p.widthCm)} × ${_fmt(p.heightCm)} cm'
                                  '${(p.brand ?? '').isNotEmpty ? ' · ${p.brand}' : ''}'
                                  '${(p.enginePlace ?? '').isNotEmpty ? ' · ${p.enginePlace}' : ''}',
                                ),
                                trailing: Radio<int>(
                                  value: realIndex,
                                  groupValue: selectedIndex,
                                  onChanged: (v) =>
                                      setS(() => selectedIndex = v),
                                ),
                                onTap: () =>
                                    setS(() => selectedIndex = realIndex),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: selectedIndex == null
                    ? null
                    : () => Navigator.pop(ctx, selectedIndex),
                child: const Text('Usar'),
              ),
            ],
          );
        },
      ),
    );

    if (pickedIndex != null &&
        pickedIndex >= 0 &&
        pickedIndex < _presets.length) {
      final p = _presets[pickedIndex];
      setState(() {
        _selectedPresetIndex = pickedIndex;
        _widthCtrl.text = _fmt(p.widthCm);
        _heightCtrl.text = _fmt(p.heightCm);
      });
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _createPresetFromCurrent() async {
    final w = _parseNum(_widthCtrl);
    final h = _parseNum(_heightCtrl);
    final initial = PiecePreset(
      name: '${_fmt(w)} x ${_fmt(h)} cm',
      widthCm: (w <= 0 ? 10 : w),
      heightCm: (h <= 0 ? 10 : h),
    );
    final created = await Navigator.push<PiecePreset>(
      context,
      MaterialPageRoute(
        builder: (_) => PresetEditPage(
          initial: initial,
          title: 'Nuevo preset',
          allowPhoto: true,
        ),
      ),
    );
    if (created != null) {
      setState(() {
        _presets.add(created);
        _selectedPresetIndex = _presets.length - 1;
      });
      await _savePresets();
      _showSnack('Preset guardado.');
    }
  }

  // -------- Historial (bottom sheet) --------
  void _openHistorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) {
          return Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text(
                      'Historial de cotizaciones',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _history.isEmpty
                          ? null
                          : () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (dctx) => AlertDialog(
                                  title: const Text('Limpiar historial'),
                                  content: const Text(
                                    '¿Seguro que deseas borrar todas las cotizaciones guardadas?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dctx, false),
                                      child: const Text('Cancelar'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(dctx, true),
                                      child: const Text('Borrar'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                setState(() => _history.clear());
                                _saveHistory();
                                _showSnack('Historial borrado.');
                              }
                            },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Borrar todo'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _history.isEmpty
                    ? const Center(child: Text('Aún no hay cotizaciones.'))
                    : ListView.separated(
                        controller: controller,
                        itemCount: _history.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final q = _history[i];
                          final dt = DateTime.tryParse(q.timestamp);
                          final when = dt == null
                              ? q.timestamp
                              : '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
                                    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                          return ListTile(
                            leading: const Icon(Icons.receipt_long),
                            title: Text('${q.material} · ${q.thickness}'),
                            subtitle: Text(
                              'Pieza: ${_fmt(q.widthCm)} × ${_fmt(q.heightCm)} cm · Horas: ${_fmt(q.hours)} · $when',
                            ),
                            trailing: Text(
                              '\$${_fmt(q.total)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openPriceSettings() async {
    final stepCtrl = TextEditingController(text: _fmt(_roundingStepUSD));
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajustes de precio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: stepCtrl,
              decoration: const InputDecoration(
                labelText: 'Redondeo a múltiplos de (USD) — 0 para desactivar',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ej.: 0.25 = redondeo a 25 centavos. Se aplica al total final.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              _roundingStepUSD = _parseFromDialog(stepCtrl.text);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setDouble('roundingStepUSD', _roundingStepUSD);
              if (mounted) Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  // ---------------------- PDF ----------------------
  Future<pw.Document> _buildQuotePdf() async {
    final m = _currentMaterial;
    final th = _currentThicknessOption;

    final doc = pw.Document();
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final total = _total ?? 0;
    final appliedMin = _appliedMin ? 'Sí' : 'No';
    final appliedRound = _appliedRounding ? 'Sí' : 'No';

    doc.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(margin: pw.EdgeInsets.all(24)),
        build: (ctx) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Cotización de Empacadura',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(dateStr),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(),
          pw.SizedBox(height: 8),

          // Resumen
          pw.Text(
            'Resumen',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Table.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: ['Campo', 'Valor'],
            data: [
              ['Material', m.name],
              ['Espesor', th?.label ?? '-'],
              [
                'Dimensiones pieza',
                '${_fmt(_parseNum(_widthCtrl))} × ${_fmt(_parseNum(_heightCtrl))} cm',
              ],
              ['Horas', _fmt(_parseNum(_hoursCtrl))],
              ['Tarifa/h', '\$${_fmt(_hourlyRate)}'],
            ],
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          ),

          pw.SizedBox(height: 14),
          pw.Text(
            'Cálculo',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Table.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: ['Concepto', 'Valor'],
            data: [
              [
                'Tamaño lámina',
                '${_fmt(m.sheetWidthCm)} × ${_fmt(m.sheetHeightCm)} cm',
              ],
              [
                'Área base',
                _areaBaseCm2 != null ? '${_fmt(_areaBaseCm2!)} cm²' : '-',
              ],
              ['Merma %', th != null ? '${_fmt(th.wastePct)} %' : '-'],
              [
                'Área con merma',
                _areaWithWasteCm2 != null
                    ? '${_fmt(_areaWithWasteCm2!)} cm²'
                    : '-',
              ],
              [
                'Precio por cm²',
                _pricePerCm2 != null ? '\$${_fmtSmart(_pricePerCm2!)}' : '-',
              ],
              [
                'Costo material',
                _materialCost != null ? '\$${_fmt(_materialCost!)}' : '-',
              ],
              [
                'Mano de obra',
                _laborCost != null ? '\$${_fmt(_laborCost!)}' : '-',
              ],
              ['Ganancia %', th != null ? '${_fmt(th.profitPct)} %' : '-'],
              [
                'Mínimo por pieza',
                th != null && th.minPriceUSD > 0
                    ? '\$${_fmt(th.minPriceUSD)}'
                    : '-',
              ],
              [
                'Redondeo múltiplos',
                _roundingStepUSD > 0 ? '\$${_fmt(_roundingStepUSD)}' : 'No',
              ],
              ['¿Aplicó mínimo?', appliedMin],
              ['¿Aplicó redondeo?', appliedRound],
            ],
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          ),

          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black),
              color: PdfColors.grey200,
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'TOTAL',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  '\$${_fmt(total)}',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 16),
          pw.Text(
            'Nota: valores calculados localmente. Configuración de Ganancia/Merma/Mínimo por espesor en la app.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    return doc;
  }

  Future<void> _printPreviewPdf() async {
    if (_total == null) {
      _showSnack('Primero calcula un total.');
      return;
    }
    final doc = await _buildQuotePdf();
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  Future<void> _sharePdf() async {
    if (_total == null) {
      _showSnack('Primero calcula un total.');
      return;
    }
    final doc = await _buildQuotePdf();
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'cotizacion_empacadura.pdf',
    );
  }

  // -------- Crear orden desde cálculo --------
  Future<void> _createOrderFromCalc() async {
    final th = _currentThicknessOption;
    if (th == null || _total == null) {
      _showSnack('Primero realiza un cálculo válido.');
      return;
    }

    // Descripción por defecto
    String desc =
        'Pieza ${_fmt(_parseNum(_widthCtrl))}×${_fmt(_parseNum(_heightCtrl))} cm';
    if (_selectedPresetIndex >= 0 && _selectedPresetIndex < _presets.length) {
      desc = _presets[_selectedPresetIndex].name;
    }

    final draft = WorkOrder(
      id: 'w_${DateTime.now().millisecondsSinceEpoch}',
      clientName: '',
      phone: '',
      cedula: '',
      description: desc,
      material: _currentMaterial.name,
      thickness: th.label,
      price: _total!,
      abono: 0,
      paymentRef: '',
      method: PaymentMethod.usd,
      photoB64: '',
      createdBy: widget.isAdminAuthed ? 'admin' : 'operador',
      timestamp: DateTime.now().toIso8601String(),
    );

    final saved = await Navigator.push<WorkOrder>(
      context,
      MaterialPageRoute(
        builder: (_) => OrderFormPage(initial: draft, title: 'Nueva orden'),
      ),
    );

    if (saved != null) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('workOrders');
      final list = raw == null
          ? <WorkOrder>[]
          : (jsonDecode(raw) as List)
                .map((e) => WorkOrder.fromJson(e))
                .toList();
      list.insert(0, saved);
      await prefs.setString(
        'workOrders',
        jsonEncode(list.map((e) => e.toJson()).toList()),
      );
      _showSnack('Orden guardada.');
    }
  }

  // -------------------- BACKUP --------------------
  Future<void> _openBackupDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final exportMap = {
      'version': 3,
      'materialsData': _materials.map((m) => m.toJson()).toList(),
      'hourlyRate': _hourlyRate,
      'roundingStepUSD': _roundingStepUSD,
      'piecePresets': _presets.map((e) => e.toJson()).toList(),
    };
    final exportJson = const JsonEncoder.withIndent('  ').convert(exportMap);

    final importCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Respaldo de configuración'),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Exportar',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    exportJson,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: exportJson));
                        _showSnack('Copiado al portapapeles');
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar'),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Incluye materiales, tarifa/hora, redondeo y presets.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Importar (pega aquí tu JSON)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: importCtrl,
                  minLines: 6,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    hintText: '{ ... }',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final map = jsonDecode(importCtrl.text) as Map<String, dynamic>;
                final mats = (map['materialsData'] as List)
                    .map((e) => MaterialConfig.fromJson(e))
                    .toList();
                final rate = (map['hourlyRate'] ?? _hourlyRate) as num;
                final step =
                    (map['roundingStepUSD'] ?? _roundingStepUSD) as num;
                final pres = (map['piecePresets'] ?? []) as List;

                _materials = mats;
                _selectedMaterialId = _materials.first.id;
                _selectedThicknessIndex = 0;
                _hourlyRate = rate.toDouble();
                _roundingStepUSD = step.toDouble();
                _presets = pres.isEmpty
                    ? []
                    : pres.map((e) => PiecePreset.fromJson(e)).toList();

                await prefs.setString(
                  'materialsData',
                  jsonEncode(_materials.map((m) => m.toJson()).toList()),
                );
                await prefs.setDouble('hourlyRate', _hourlyRate);
                await prefs.setDouble('roundingStepUSD', _roundingStepUSD);
                await _savePresets();

                if (mounted) Navigator.pop(ctx);
                setState(() {});
                _showSnack('Configuración importada correctamente.');
              } catch (e) {
                _showSnack('JSON inválido: ${e.toString()}');
              }
            },
            child: const Text('Importar'),
          ),
        ],
      ),
    );
  }
}

// ================== PÁGINAS DE ÓRDENES ==================
class OrdersPage extends StatefulWidget {
  final String currentUser;
  const OrdersPage({super.key, required this.currentUser});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final _searchCtrl = TextEditingController();
  List<WorkOrder> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('workOrders');
    _orders = raw == null
        ? []
        : (jsonDecode(raw) as List).map((e) => WorkOrder.fromJson(e)).toList();
    // Ordenado reciente primero
    _orders.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    setState(() {});
  }

  Future<void> _saveOrders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'workOrders',
      jsonEncode(_orders.map((e) => e.toJson()).toList()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = _orders.where((o) {
      bool h(String s) => s.toLowerCase().contains(q);
      return q.isEmpty ||
          h(o.clientName) ||
          h(o.description) ||
          h(o.paymentRef) ||
          h(o.material) ||
          h(o.thickness) ||
          h(o.createdBy);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Órdenes'),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _loadOrders,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar por cliente / descripción / referencia...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
        ),
      ),
      body: filtered.isEmpty
          ? const Center(child: Text('No hay órdenes'))
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final o = filtered[i];
                final dt = DateTime.tryParse(o.timestamp);
                final when = dt == null
                    ? ''
                    : '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}'
                          ' ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                final color = o.isPaid
                    ? Colors.green
                    : (o.abono > 0 ? Colors.orange : Colors.red);
                final bytes = (o.photoB64.isEmpty)
                    ? null
                    : base64Decode(o.photoB64);
                return InkWell(
                  onTap: () async {
                    final edited = await Navigator.push<WorkOrder>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            OrderFormPage(initial: o, title: 'Editar orden'),
                      ),
                    );
                    if (edited != null) {
                      _orders[_orders.indexWhere((e) => e.id == edited.id)] =
                          edited;
                      await _saveOrders();
                      setState(() {});
                    }
                  },
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 5,
                          height: 64,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.black12,
                          backgroundImage: bytes == null
                              ? null
                              : MemoryImage(bytes),
                          child: bytes == null
                              ? const Icon(Icons.photo, color: Colors.black45)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      (o.clientName.isEmpty
                                          ? '(Sin nombre)'
                                          : o.clientName),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '\$${o.price.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                o.description,
                                style: const TextStyle(color: Colors.black87),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  _chip(
                                    'Material',
                                    '${o.material} · ${o.thickness}',
                                  ),
                                  _chip('Pago', o.method.name),
                                  if (o.paymentRef.isNotEmpty)
                                    _chip('Ref', o.paymentRef),
                                  _chip(
                                    'Por',
                                    o.createdBy.isEmpty ? '-' : o.createdBy,
                                  ),
                                  if (when.isNotEmpty) _chip('Fecha', when),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Abono: \$${o.abono.toStringAsFixed(0)} • Debe: \$${o.due.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, color: Colors.black45),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Crear orden vacía manual
          final draft = WorkOrder(
            id: 'w_${DateTime.now().millisecondsSinceEpoch}',
            clientName: '',
            phone: '',
            cedula: '',
            description: '',
            material: '',
            thickness: '',
            price: 0,
            abono: 0,
            paymentRef: '',
            method: PaymentMethod.usd,
            photoB64: '',
            createdBy: widget.currentUser,
            timestamp: DateTime.now().toIso8601String(),
          );
          final saved = await Navigator.push<WorkOrder>(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  OrderFormPage(initial: draft, title: 'Nueva orden'),
            ),
          );
          if (saved != null) {
            _orders.insert(0, saved);
            await _saveOrders();
            setState(() {});
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _chip(String k, String v) {
    return Chip(
      label: Text('$k: $v'),
      labelStyle: const TextStyle(fontSize: 12),
      backgroundColor: Colors.grey.shade200,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    );
  }
}

// -------- Form para crear/editar orden --------
class OrderFormPage extends StatefulWidget {
  final WorkOrder initial;
  final String title;
  const OrderFormPage({super.key, required this.initial, required this.title});

  @override
  State<OrderFormPage> createState() => _OrderFormPageState();
}

class _OrderFormPageState extends State<OrderFormPage> {
  late TextEditingController nameCtrl;
  late TextEditingController phoneCtrl;
  late TextEditingController cedCtrl;
  late TextEditingController descCtrl;
  late TextEditingController priceCtrl;
  late TextEditingController abonoCtrl;
  late TextEditingController refCtrl;
  PaymentMethod method = PaymentMethod.usd;
  String? photoB64;

  @override
  void initState() {
    super.initState();
    final o = widget.initial;
    nameCtrl = TextEditingController(text: o.clientName);
    phoneCtrl = TextEditingController(text: o.phone);
    cedCtrl = TextEditingController(text: o.cedula);
    descCtrl = TextEditingController(text: o.description);
    priceCtrl = TextEditingController(
      text: o.price == 0
          ? ''
          : o.price.toStringAsFixed(
              o.price.truncateToDouble() == o.price ? 0 : 2,
            ),
    );
    abonoCtrl = TextEditingController(
      text: o.abono == 0
          ? ''
          : o.abono.toStringAsFixed(
              o.abono.truncateToDouble() == o.abono ? 0 : 2,
            ),
    );
    refCtrl = TextEditingController(text: o.paymentRef);
    method = o.method;
    photoB64 = o.photoB64.isEmpty ? null : o.photoB64;
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    cedCtrl.dispose();
    descCtrl.dispose();
    priceCtrl.dispose();
    abonoCtrl.dispose();
    refCtrl.dispose();
    super.dispose();
  }

  double _p(TextEditingController c) {
    final s = c.text.trim().replaceAll(',', '.');
    return double.tryParse(s) ?? 0.0;
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (x != null) {
      final bytes = await x.readAsBytes();
      setState(() => photoB64 = base64Encode(bytes));
    }
  }

  @override
  Widget build(BuildContext context) {
    final due = math.max(0, _p(priceCtrl) - _p(abonoCtrl));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton.icon(
            onPressed: () {
              // Guardar
              final updated = WorkOrder(
                id: widget.initial.id,
                clientName: nameCtrl.text.trim(),
                phone: phoneCtrl.text.trim(),
                cedula: cedCtrl.text.trim(),
                description: descCtrl.text.trim(),
                material: widget.initial.material,
                thickness: widget.initial.thickness,
                price: _p(priceCtrl),
                abono: _p(abonoCtrl),
                paymentRef: refCtrl.text.trim(),
                method: method,
                photoB64: photoB64 ?? '',
                createdBy: widget.initial.createdBy,
                timestamp: widget.initial.timestamp,
              );
              Navigator.pop(context, updated);
            },
            icon: const Icon(Icons.save),
            label: const Text('Guardar'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del cliente',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Teléfono'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: cedCtrl,
              decoration: const InputDecoration(labelText: 'Cédula'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descripción de la empacadura',
              ),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                Chip(label: Text('Material: ${widget.initial.material}')),
                Chip(label: Text('Espesor: ${widget.initial.thickness}')),
              ],
            ),

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      prefixText: '\$ ',
                      labelText: 'Precio',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: abonoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      prefixText: '\$ ',
                      labelText: 'Abono',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Total adeudado: \$${due.toStringAsFixed(due.truncateToDouble() == due ? 0 : 2)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: due <= 0 ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<PaymentMethod>(
              value: method,
              items: PaymentMethod.values
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text(_paymentLabel(e)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => method = v ?? PaymentMethod.usd),
              decoration: const InputDecoration(labelText: 'Método de pago'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: refCtrl,
              decoration: const InputDecoration(
                labelText: 'Referencia / detalle de pago',
              ),
            ),

            const SizedBox(height: 16),
            const Text('Foto de la pieza (obligatoria)'),
            const SizedBox(height: 6),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 120,
                    height: 120,
                    color: Colors.black12,
                    child: photoB64 == null
                        ? const Icon(Icons.photo, size: 40)
                        : Image.memory(
                            base64Decode(photoB64!),
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Tomar / Subir foto'),
                ),
                if (photoB64 != null)
                  TextButton.icon(
                    onPressed: () => setState(() => photoB64 = null),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Quitar'),
                  ),
              ],
            ),

            const SizedBox(height: 16),
            Text(
              'Creado por: ${widget.initial.createdBy}  •  ${_formatDate(widget.initial.timestamp)}',
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _paymentLabel(PaymentMethod m) {
    switch (m) {
      case PaymentMethod.usd:
        return 'Divisa USD';
      case PaymentMethod.eur:
        return 'Euro';
      case PaymentMethod.pagomovil:
        return 'Pago Móvil';
      case PaymentMethod.transferencia:
        return 'Transferencia';
      case PaymentMethod.bs:
        return 'Bolívares efectivo';
      case PaymentMethod.other:
        return 'Otro';
    }
  }
}

// ============== PÁGINAS DE PRESETS (reutiliza el mismo storage) ==============
class PresetsStandalonePage extends StatefulWidget {
  final bool isAdmin;
  final Future<bool> Function() onRequestAdmin;
  const PresetsStandalonePage({
    super.key,
    required this.isAdmin,
    required this.onRequestAdmin,
  });

  @override
  State<PresetsStandalonePage> createState() => _PresetsStandalonePageState();
}

class _PresetsStandalonePageState extends State<PresetsStandalonePage> {
  List<PiecePreset> _presets = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('piecePresets');
    if (raw == null) {
      setState(() => _presets = []);
      return;
    }
    try {
      final list = jsonDecode(raw) as List;
      _presets = list.map((e) => PiecePreset.fromJson(e)).toList();
      setState(() {});
    } catch (_) {
      setState(() => _presets = []);
    }
  }

  Future<void> _save(List<PiecePreset> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'piecePresets',
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Presets'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final updated = await Navigator.push<List<PiecePreset>>(
                context,
                MaterialPageRoute(
                  builder: (_) => PresetManagerPage(
                    initial: List<PiecePreset>.from(_presets),
                    isAdmin: widget.isAdmin,
                    onRequestAdmin: widget.onRequestAdmin,
                  ),
                ),
              );
              if (updated != null) {
                await _save(updated);
                setState(() => _presets = updated);
              }
            },
            icon: const Icon(Icons.edit),
            label: const Text('Gestionar'),
          ),
        ],
      ),
      body: _presets.isEmpty
          ? const Center(child: Text('No hay presets aún'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _presets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final p = _presets[i];
                final img = p.imageB64 == null
                    ? null
                    : base64Decode(p.imageB64!);
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundImage: img == null ? null : MemoryImage(img),
                      child: img == null ? const Icon(Icons.photo) : null,
                    ),
                    title: Text(p.name),
                    subtitle: Text(
                      '${p.widthCm} × ${p.heightCm} cm'
                      '${(p.brand ?? '').isNotEmpty ? '  ·  ${p.brand}' : ''}'
                      '${(p.enginePlace ?? '').isNotEmpty ? '  ·  ${p.enginePlace}' : ''}',
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PresetPreviewPage(preset: p),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ======= Gestor de presets (idéntico al tuyo anterior) =======
class PresetManagerPage extends StatefulWidget {
  final List<PiecePreset> initial;
  final bool isAdmin;
  final Future<bool> Function() onRequestAdmin;

  const PresetManagerPage({
    super.key,
    required this.initial,
    required this.isAdmin,
    required this.onRequestAdmin,
  });

  @override
  State<PresetManagerPage> createState() => _PresetManagerPageState();
}

class _PresetManagerPageState extends State<PresetManagerPage> {
  late List<PiecePreset> _items;
  late bool _isAdmin;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _items = List<PiecePreset>.from(widget.initial);
    _isAdmin = widget.isAdmin;
  }

  List<PiecePreset> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    bool hit(String? s) => (s ?? '').toLowerCase().contains(q);
    return _items
        .where(
          (p) =>
              hit(p.name) ||
              hit(p.brand) ||
              hit(p.enginePlace) ||
              hit(p.ringSize) ||
              hit(p.notes),
        )
        .toList();
  }

  Future<void> _exportCsv() async {
    String esc(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
    final header = [
      'nombre',
      'ancho_cm',
      'largo_cm',
      'marca_motor',
      'lugar_motor',
      'anillo',
      'notas',
      'tiene_foto',
    ];
    final lines = <String>[];
    lines.add(header.join(','));
    for (final p in _items) {
      lines.add(
        [
          esc(p.name),
          p.widthCm.toString(),
          p.heightCm.toString(),
          esc(p.brand),
          esc(p.enginePlace),
          esc(p.ringSize),
          esc(p.notes),
          p.imageB64 == null ? 'no' : 'si',
        ].join(','),
      );
    }
    final csv = lines.join('\n');

    // Copia al portapapeles por si acaso (web)
    await Clipboard.setData(ClipboardData(text: csv));

    try {
      final bytes = Uint8List.fromList(utf8.encode(csv));
      final xf = XFile.fromData(
        bytes,
        name: 'presets.csv',
        mimeType: 'text/csv',
      );
      await Share.shareXFiles(
        [xf],
        text: 'Presets de piezas (CSV)',
        subject: 'Presets de piezas',
      );
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CSV copiado y compartido (si es posible).'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestionar presets de piezas'),
        actions: [
          IconButton(
            tooltip: 'Exportar CSV',
            onPressed: _filtered.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.file_download),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(context, _items),
            icon: const Icon(Icons.save),
            label: const Text('Guardar'),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Filtrar por nombre/marca/lugar/anillo/notas…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(child: Text('No hay presets'))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final p = _filtered[i];
                      final idx = _items.indexOf(p);
                      return Card(
                        elevation: 1,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PresetPreviewPage(preset: p),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.black12,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: p.imageB64 == null
                                      ? const Icon(Icons.photo, size: 30)
                                      : Image.memory(
                                          base64Decode(p.imageB64!),
                                          fit: BoxFit.cover,
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 6,
                                        children: [
                                          _chip(
                                            'Dimensiones',
                                            '${p.widthCm} × ${p.heightCm} cm',
                                          ),
                                          if ((p.brand ?? '').isNotEmpty)
                                            _chip('Marca', p.brand!),
                                          if ((p.enginePlace ?? '').isNotEmpty)
                                            _chip('Lugar', p.enginePlace!),
                                          if ((p.ringSize ?? '').isNotEmpty)
                                            _chip('Anillo', p.ringSize!),
                                        ],
                                      ),
                                      if ((p.notes ?? '').isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          p.notes!,
                                          style: const TextStyle(
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  children: [
                                    IconButton(
                                      tooltip: 'Editar',
                                      onPressed: () async {
                                        if (!_isAdmin) {
                                          final ok = await widget
                                              .onRequestAdmin();
                                          if (!ok) return;
                                          setState(() => _isAdmin = true);
                                        }
                                        final edited =
                                            await Navigator.push<PiecePreset>(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => PresetEditPage(
                                                  initial: p,
                                                  title: 'Editar preset',
                                                  allowPhoto: true,
                                                ),
                                              ),
                                            );
                                        if (edited != null) {
                                          setState(() => _items[idx] = edited);
                                        }
                                      },
                                      icon: const Icon(Icons.edit),
                                    ),
                                    IconButton(
                                      tooltip: 'Eliminar',
                                      onPressed: () async {
                                        if (!_isAdmin) {
                                          final ok = await widget
                                              .onRequestAdmin();
                                          if (!ok) return;
                                          setState(() => _isAdmin = true);
                                        }
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (c) => AlertDialog(
                                            title: const Text(
                                              'Eliminar preset',
                                            ),
                                            content: Text(
                                              '¿Borrar "${p.name}" definitivamente?',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(c, false),
                                                child: const Text('Cancelar'),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(c, true),
                                                child: const Text('Eliminar'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok == true)
                                          setState(() => _items.removeAt(idx));
                                      },
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<PiecePreset>(
            context,
            MaterialPageRoute(
              builder: (_) => const PresetEditPage(
                initial: null,
                title: 'Nuevo preset',
                allowPhoto: true,
              ),
            ),
          );
          if (created != null) setState(() => _items.add(created));
        },
        label: const Text('Añadir preset'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: Colors.grey.shade200,
    );
  }
}

// ====== Editor & Preview de preset (idéntico al tuyo) ======
class PresetEditPage extends StatefulWidget {
  final PiecePreset? initial;
  final String title;
  final bool allowPhoto;

  const PresetEditPage({
    super.key,
    required this.initial,
    required this.title,
    required this.allowPhoto,
  });

  @override
  State<PresetEditPage> createState() => _PresetEditPageState();
}

class _PresetEditPageState extends State<PresetEditPage> {
  late final TextEditingController nameCtrl;
  late final TextEditingController widthCtrl;
  late final TextEditingController heightCtrl;
  late final TextEditingController brandCtrl;
  late final TextEditingController placeCtrl;
  late final TextEditingController ringCtrl;
  late final TextEditingController notesCtrl;

  String? imageB64;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    nameCtrl = TextEditingController(text: p?.name ?? '');
    widthCtrl = TextEditingController(text: _fmt(p?.widthCm ?? 10));
    heightCtrl = TextEditingController(text: _fmt(p?.heightCm ?? 10));
    brandCtrl = TextEditingController(text: p?.brand ?? '');
    placeCtrl = TextEditingController(text: p?.enginePlace ?? '');
    ringCtrl = TextEditingController(text: p?.ringSize ?? '');
    notesCtrl = TextEditingController(text: p?.notes ?? '');
    imageB64 = p?.imageB64;
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    widthCtrl.dispose();
    heightCtrl.dispose();
    brandCtrl.dispose();
    placeCtrl.dispose();
    ringCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  String _fmt(num v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

  Future<void> _pickImage(bool fromCamera) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (x != null) {
      final bytes = await x.readAsBytes();
      setState(() => imageB64 = base64Encode(bytes));
    }
  }

  double _parseNum(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.')) ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final numberInput = <TextInputFormatter>[
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      FilteringTextInputFormatter.deny(RegExp(r'-')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton.icon(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final w = _parseNum(widthCtrl.text);
              final h = _parseNum(heightCtrl.text);
              if (name.isEmpty || w <= 0 || h <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Nombre y dimensiones (> 0) son obligatorios',
                    ),
                  ),
                );
                return;
              }
              final p = PiecePreset(
                name: name,
                widthCm: w,
                heightCm: h,
                brand: brandCtrl.text.trim().isEmpty
                    ? null
                    : brandCtrl.text.trim(),
                enginePlace: placeCtrl.text.trim().isEmpty
                    ? null
                    : placeCtrl.text.trim(),
                ringSize: ringCtrl.text.trim().isEmpty
                    ? null
                    : ringCtrl.text.trim(),
                notes: notesCtrl.text.trim().isEmpty
                    ? null
                    : notesCtrl.text.trim(),
                imageB64: imageB64,
              );
              Navigator.pop(context, p);
            },
            icon: const Icon(Icons.save),
            label: const Text('Guardar'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: imageB64 == null
                      ? null
                      : () {
                          final preset = PiecePreset(
                            name: nameCtrl.text,
                            widthCm: _parseNum(widthCtrl.text),
                            heightCm: _parseNum(heightCtrl.text),
                            brand: brandCtrl.text,
                            enginePlace: placeCtrl.text,
                            ringSize: ringCtrl.text,
                            notes: notesCtrl.text,
                            imageB64: imageB64,
                          );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PresetPreviewPage(preset: preset),
                            ),
                          );
                        },
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: imageB64 == null
                        ? const Icon(Icons.photo, size: 40)
                        : Image.memory(
                            base64Decode(imageB64!),
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                if (widget.allowPhoto)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _pickImage(true),
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Cámara'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _pickImage(false),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Galería'),
                      ),
                      if (imageB64 != null)
                        OutlinedButton.icon(
                          onPressed: () => setState(() => imageB64 = null),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Quitar'),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widthCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ancho (cm) *',
                      border: OutlineInputBorder(),
                    ),
                    textAlign: TextAlign.right,
                    inputFormatters: numberInput,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: heightCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Largo (cm) *',
                      border: OutlineInputBorder(),
                    ),
                    textAlign: TextAlign.right,
                    inputFormatters: numberInput,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: brandCtrl,
              decoration: const InputDecoration(
                labelText: 'Marca de motor',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: placeCtrl,
              decoration: const InputDecoration(
                labelText: 'Lugar del motor',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ringCtrl,
              decoration: const InputDecoration(
                labelText: 'Tamaño del anillo (si aplica)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notas',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PresetPreviewPage extends StatelessWidget {
  final PiecePreset preset;
  const PresetPreviewPage({super.key, required this.preset});

  @override
  Widget build(BuildContext context) {
    final bytes = preset.imageB64 == null
        ? null
        : base64Decode(preset.imageB64!);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vista previa'),
        actions: [
          IconButton(
            tooltip: 'Compartir',
            onPressed: () async {
              if (bytes == null) {
                final text = _toPrettyText(preset);
                await Share.share(text, subject: preset.name);
              } else {
                final xf = XFile.fromData(
                  bytes,
                  name: '${preset.name}.jpg',
                  mimeType: 'image/jpeg',
                );
                await Share.shareXFiles([xf], text: _toPrettyText(preset));
              }
            },
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: bytes == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Sin foto para "${preset.name}"\n\n${_toPrettyText(preset)}',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: Center(
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          _info(
                            'Dimensiones',
                            '${preset.widthCm} × ${preset.heightCm} cm',
                          ),
                          if ((preset.brand ?? '').isNotEmpty)
                            _info('Marca', preset.brand!),
                          if ((preset.enginePlace ?? '').isNotEmpty)
                            _info('Lugar', preset.enginePlace!),
                          if ((preset.ringSize ?? '').isNotEmpty)
                            _info('Anillo', preset.ringSize!),
                        ],
                      ),
                      if ((preset.notes ?? '').isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          preset.notes!,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  static String _toPrettyText(PiecePreset p) {
    final parts = <String>[
      'Nombre: ${p.name}',
      'Dimensiones: ${p.widthCm} x ${p.heightCm} cm',
      if ((p.brand ?? '').isNotEmpty) 'Marca: ${p.brand}',
      if ((p.enginePlace ?? '').isNotEmpty) 'Lugar: ${p.enginePlace}',
      if ((p.ringSize ?? '').isNotEmpty) 'Anillo: ${p.ringSize}',
      if ((p.notes ?? '').isNotEmpty) 'Notas: ${p.notes}',
    ];
    return parts.join('\n');
  }

  Widget _info(String k, String v) {
    return Chip(label: Text('$k: $v'), backgroundColor: Colors.grey.shade200);
  }
}
