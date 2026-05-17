import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const double a4WidthMm = 210;
const double a4HeightMm = 297;
const int exportWidthPx = 2480;
const int exportHeightPx = 3508;
const Object _unset = Object();

void runOfflineStudioApp() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const ProviderScope(child: OfflineStudioApp()));
}

final editorProvider = StateNotifierProvider<EditorController, EditorState>(
  (ref) => EditorController(),
);

List<Rect> buildSlotRects(EditorState state) {
  final usableWidth =
      a4WidthMm - (state.marginMm * 2) - (state.gapMm * (state.columns - 1));
  final usableHeight =
      a4HeightMm - (state.marginMm * 2) - (state.gapMm * (state.rows - 1));
  final slotWidth = usableWidth / state.columns;
  final slotHeight = usableHeight / state.rows;

  return List<Rect>.generate(state.slotCount, (index) {
    final row = index ~/ state.columns;
    final column = index % state.columns;
    final left = state.marginMm + column * (slotWidth + state.gapMm);
    final top = state.marginMm + row * (slotHeight + state.gapMm);
    return Rect.fromLTWH(left, top, slotWidth, slotHeight);
  });
}

Offset canvasPointToPagePoint(Offset localPosition, Size canvasSize) {
  final scale = pageScaleForCanvas(canvasSize);
  final pageSize = Size(a4WidthMm * scale, a4HeightMm * scale);
  final pageOffset = Offset(
    (canvasSize.width - pageSize.width) / 2,
    (canvasSize.height - pageSize.height) / 2,
  );
  return (localPosition - pageOffset) / scale;
}

double pageScaleForCanvas(Size canvasSize) {
  return math.min(canvasSize.width / a4WidthMm, canvasSize.height / a4HeightMm);
}

class OfflineStudioApp extends StatelessWidget {
  const OfflineStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF55D6BE),
      brightness: Brightness.dark,
      surface: const Color(0xFF12151C),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Offline A4 Studio',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFF0B0D12),
        cardTheme: CardThemeData(
          color: const Color(0xFF151922),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFF252C38)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Color(0xFF10131A),
          foregroundColor: Color(0xFFEAF2F1),
          elevation: 0,
        ),
      ),
      home: const StudioScreen(),
    );
  }
}

class PhotoSlot {
  const PhotoSlot({
    this.bytes,
    this.localPath,
    this.image,
    this.cropScale = 1,
    this.cropOffset = Offset.zero,
  });

  final Uint8List? bytes;
  final String? localPath;
  final ui.Image? image;
  final double cropScale;
  final Offset cropOffset;

  bool get hasPhoto => image != null;

  PhotoSlot copyWith({
    Object? bytes = _unset,
    Object? localPath = _unset,
    Object? image = _unset,
    double? cropScale,
    Offset? cropOffset,
  }) {
    return PhotoSlot(
      bytes: bytes == _unset ? this.bytes : bytes as Uint8List?,
      localPath: localPath == _unset ? this.localPath : localPath as String?,
      image: image == _unset ? this.image : image as ui.Image?,
      cropScale: cropScale ?? this.cropScale,
      cropOffset: cropOffset ?? this.cropOffset,
    );
  }
}

class EditorState {
  const EditorState({
    required this.rows,
    required this.columns,
    required this.marginMm,
    required this.gapMm,
    required this.cutBorderWidthMm,
    required this.showCutBorders,
    required this.applyOverlayToAll,
    required this.overlayOpacity,
    required this.slots,
    required this.selectedIndex,
    this.overlayBytes,
    this.overlayPath,
    this.overlayImage,
    this.isBusy = false,
    this.notice,
  });

  factory EditorState.initial() {
    const rows = 2;
    const columns = 2;
    return EditorState(
      rows: rows,
      columns: columns,
      marginMm: 8,
      gapMm: 4,
      cutBorderWidthMm: 0.35,
      showCutBorders: true,
      applyOverlayToAll: true,
      overlayOpacity: 0.85,
      slots: List<PhotoSlot>.generate(rows * columns, (_) => const PhotoSlot()),
      selectedIndex: 0,
    );
  }

  final int rows;
  final int columns;
  final double marginMm;
  final double gapMm;
  final double cutBorderWidthMm;
  final bool showCutBorders;
  final bool applyOverlayToAll;
  final double overlayOpacity;
  final Uint8List? overlayBytes;
  final String? overlayPath;
  final ui.Image? overlayImage;
  final List<PhotoSlot> slots;
  final int selectedIndex;
  final bool isBusy;
  final String? notice;

  int get slotCount => rows * columns;
  PhotoSlot get selectedSlot =>
      slots[selectedIndex.clamp(0, slots.length - 1).toInt()];

  EditorState copyWith({
    int? rows,
    int? columns,
    double? marginMm,
    double? gapMm,
    double? cutBorderWidthMm,
    bool? showCutBorders,
    bool? applyOverlayToAll,
    double? overlayOpacity,
    Object? overlayBytes = _unset,
    Object? overlayPath = _unset,
    Object? overlayImage = _unset,
    List<PhotoSlot>? slots,
    int? selectedIndex,
    bool? isBusy,
    Object? notice = _unset,
  }) {
    final nextSlots = slots ?? this.slots;
    return EditorState(
      rows: rows ?? this.rows,
      columns: columns ?? this.columns,
      marginMm: marginMm ?? this.marginMm,
      gapMm: gapMm ?? this.gapMm,
      cutBorderWidthMm: cutBorderWidthMm ?? this.cutBorderWidthMm,
      showCutBorders: showCutBorders ?? this.showCutBorders,
      applyOverlayToAll: applyOverlayToAll ?? this.applyOverlayToAll,
      overlayOpacity: overlayOpacity ?? this.overlayOpacity,
      overlayBytes: overlayBytes == _unset
          ? this.overlayBytes
          : overlayBytes as Uint8List?,
      overlayPath: overlayPath == _unset
          ? this.overlayPath
          : overlayPath as String?,
      overlayImage: overlayImage == _unset
          ? this.overlayImage
          : overlayImage as ui.Image?,
      slots: nextSlots,
      selectedIndex: (selectedIndex ?? this.selectedIndex)
          .clamp(0, math.max(0, nextSlots.length - 1))
          .toInt(),
      isBusy: isBusy ?? this.isBusy,
      notice: notice == _unset ? this.notice : notice as String?,
    );
  }
}

class EditorController extends StateNotifier<EditorState> {
  EditorController() : super(EditorState.initial()) {
    _loadPreferences();
  }

  static const _rowsKey = 'editor.rows';
  static const _columnsKey = 'editor.columns';
  static const _marginKey = 'editor.marginMm';
  static const _gapKey = 'editor.gapMm';
  static const _cutKey = 'editor.cutBorderWidthMm';
  static const _showCutKey = 'editor.showCutBorders';
  static const _overlayAllKey = 'editor.applyOverlayToAll';
  static const _overlayOpacityKey = 'editor.overlayOpacity';
  static const _recentExportsKey = 'editor.recentExports';

  final ImagePicker _picker = ImagePicker();

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = (prefs.getInt(_rowsKey) ?? state.rows).clamp(1, 6).toInt();
    final columns = (prefs.getInt(_columnsKey) ?? state.columns)
        .clamp(1, 6)
        .toInt();
    state = state.copyWith(
      rows: rows,
      columns: columns,
      marginMm: prefs.getDouble(_marginKey) ?? state.marginMm,
      gapMm: prefs.getDouble(_gapKey) ?? state.gapMm,
      cutBorderWidthMm: prefs.getDouble(_cutKey) ?? state.cutBorderWidthMm,
      showCutBorders: prefs.getBool(_showCutKey) ?? state.showCutBorders,
      applyOverlayToAll:
          prefs.getBool(_overlayAllKey) ?? state.applyOverlayToAll,
      overlayOpacity:
          prefs.getDouble(_overlayOpacityKey) ?? state.overlayOpacity,
      slots: _resizeSlots(state.slots, rows * columns),
    );
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_rowsKey, state.rows);
    await prefs.setInt(_columnsKey, state.columns);
    await prefs.setDouble(_marginKey, state.marginMm);
    await prefs.setDouble(_gapKey, state.gapMm);
    await prefs.setDouble(_cutKey, state.cutBorderWidthMm);
    await prefs.setBool(_showCutKey, state.showCutBorders);
    await prefs.setBool(_overlayAllKey, state.applyOverlayToAll);
    await prefs.setDouble(_overlayOpacityKey, state.overlayOpacity);
  }

  List<PhotoSlot> _resizeSlots(List<PhotoSlot> current, int length) {
    return List<PhotoSlot>.generate(
      length,
      (index) => index < current.length ? current[index] : const PhotoSlot(),
    );
  }

  void selectSlot(int index) {
    state = state.copyWith(selectedIndex: index, notice: null);
  }

  void setGrid({int? rows, int? columns}) {
    final nextRows = (rows ?? state.rows).clamp(1, 6).toInt();
    final nextColumns = (columns ?? state.columns).clamp(1, 6).toInt();
    state = state.copyWith(
      rows: nextRows,
      columns: nextColumns,
      slots: _resizeSlots(state.slots, nextRows * nextColumns),
      notice: 'Grid updated to $nextColumns x $nextRows slots',
    );
    _savePreferences();
  }

  void setSpacing({double? marginMm, double? gapMm}) {
    state = state.copyWith(
      marginMm: (marginMm ?? state.marginMm).clamp(0, 24).toDouble(),
      gapMm: (gapMm ?? state.gapMm).clamp(0, 16).toDouble(),
      notice: null,
    );
    _savePreferences();
  }

  void setCutBorders({bool? enabled, double? widthMm}) {
    state = state.copyWith(
      showCutBorders: enabled ?? state.showCutBorders,
      cutBorderWidthMm: (widthMm ?? state.cutBorderWidthMm)
          .clamp(0.1, 1.5)
          .toDouble(),
      notice: null,
    );
    _savePreferences();
  }

  void setOverlayOptions({bool? applyToAll, double? opacity}) {
    state = state.copyWith(
      applyOverlayToAll: applyToAll ?? state.applyOverlayToAll,
      overlayOpacity: (opacity ?? state.overlayOpacity).clamp(0, 1).toDouble(),
      notice: null,
    );
    _savePreferences();
  }

  Future<void> pickPhoto(ImageSource source) async {
    if (state.isBusy) {
      return;
    }
    state = state.copyWith(isBusy: true, notice: null);
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 100);
      if (picked == null) {
        state = state.copyWith(isBusy: false);
        return;
      }

      final bytes = await picked.readAsBytes();
      final image = await _decodeImage(bytes);
      final extension = picked.name.toLowerCase().endsWith('.png')
          ? '.png'
          : '.jpg';
      final localPath = await _copyIntoDocuments(
        bytes,
        prefix: 'photo',
        extension: extension,
      );

      final slots = List<PhotoSlot>.of(state.slots);
      slots[state.selectedIndex] = PhotoSlot(
        bytes: bytes,
        localPath: localPath,
        image: image,
      );
      state = state.copyWith(
        slots: slots,
        isBusy: false,
        notice: source == ImageSource.camera
            ? 'Camera photo added locally'
            : 'Gallery photo imported locally',
      );
    } catch (error) {
      state = state.copyWith(
        isBusy: false,
        notice: 'Image import failed: $error',
      );
    }
  }

  Future<void> importOverlay() async {
    if (state.isBusy) {
      return;
    }
    state = state.copyWith(isBusy: true, notice: null);
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (picked == null) {
        state = state.copyWith(isBusy: false);
        return;
      }

      final bytes = await picked.readAsBytes();
      final image = await _decodeImage(bytes);
      final localPath = await _copyIntoDocuments(
        bytes,
        prefix: 'overlay',
        extension: '.png',
      );

      state = state.copyWith(
        overlayBytes: bytes,
        overlayPath: localPath,
        overlayImage: image,
        applyOverlayToAll: true,
        isBusy: false,
        notice: 'PNG overlay ready for all photo slots',
      );
      _savePreferences();
    } catch (error) {
      state = state.copyWith(
        isBusy: false,
        notice: 'Overlay import failed: $error',
      );
    }
  }

  void clearOverlay() {
    state = state.copyWith(
      overlayBytes: null,
      overlayPath: null,
      overlayImage: null,
      notice: 'Overlay removed',
    );
  }

  void clearSelectedSlot() {
    final slots = List<PhotoSlot>.of(state.slots);
    slots[state.selectedIndex] = const PhotoSlot();
    state = state.copyWith(slots: slots, notice: 'Selected slot cleared');
  }

  void setCrop(int slotIndex, double scale, Offset offset) {
    if (slotIndex < 0 || slotIndex >= state.slots.length) {
      return;
    }
    final slot = state.slots[slotIndex];
    final image = slot.image;
    if (image == null) {
      return;
    }

    final nextScale = scale.clamp(1.0, 5.0).toDouble();
    final slotRect = buildSlotRects(state)[slotIndex];
    final cover = math.max(
      slotRect.width / image.width,
      slotRect.height / image.height,
    );
    final drawnWidth = image.width * cover * nextScale;
    final drawnHeight = image.height * cover * nextScale;
    final maxX = math.max(0.0, (drawnWidth - slotRect.width) / 2);
    final maxY = math.max(0.0, (drawnHeight - slotRect.height) / 2);
    final clampedOffset = Offset(
      offset.dx.clamp(-maxX, maxX).toDouble(),
      offset.dy.clamp(-maxY, maxY).toDouble(),
    );

    final slots = List<PhotoSlot>.of(state.slots);
    slots[slotIndex] = slot.copyWith(
      cropScale: nextScale,
      cropOffset: clampedOffset,
    );
    state = state.copyWith(slots: slots, notice: null);
  }

  Future<File?> exportPng() async {
    if (state.isBusy) {
      return null;
    }
    state = state.copyWith(isBusy: true, notice: null);
    try {
      final bytes = await RenderService.renderPng(state);
      final file = await _writeExport(bytes, extension: 'png');
      state = state.copyWith(
        isBusy: false,
        notice: '300 DPI PNG exported to ${file.path}',
      );
      await _rememberExport(file.path);
      return file;
    } catch (error) {
      state = state.copyWith(
        isBusy: false,
        notice: 'PNG export failed: $error',
      );
      return null;
    }
  }

  Future<File?> exportPdf() async {
    if (state.isBusy) {
      return null;
    }
    state = state.copyWith(isBusy: true, notice: null);
    try {
      final bytes = await RenderService.renderPdf(state);
      final file = await _writeExport(bytes, extension: 'pdf');
      state = state.copyWith(
        isBusy: false,
        notice: '300 DPI PDF exported to ${file.path}',
      );
      await _rememberExport(file.path);
      return file;
    } catch (error) {
      state = state.copyWith(
        isBusy: false,
        notice: 'PDF export failed: $error',
      );
      return null;
    }
  }

  Future<void> printLayout() async {
    if (state.isBusy) {
      return;
    }
    state = state.copyWith(isBusy: true, notice: null);
    try {
      final pdfBytes = await RenderService.renderPdf(state);
      state = state.copyWith(
        isBusy: false,
        notice: 'Opening local print sheet',
      );
      await Printing.layoutPdf(
        name: 'Offline A4 Studio 300 DPI',
        format: PdfPageFormat.a4,
        onLayout: (_) async => pdfBytes,
      );
    } catch (error) {
      state = state.copyWith(isBusy: false, notice: 'Print failed: $error');
    }
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<String> _copyIntoDocuments(
    Uint8List bytes, {
    required String prefix,
    required String extension,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final imports = Directory('${documents.path}/offline_editor_imports');
    await imports.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final file = File('${imports.path}/${prefix}_$stamp$extension');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<File> _writeExport(
    Uint8List bytes, {
    required String extension,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final exports = Directory('${documents.path}/offline_editor_exports');
    await exports.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final file = File('${exports.path}/a4_layout_300dpi_$stamp.$extension');
    return file.writeAsBytes(bytes, flush: true);
  }

  Future<void> _rememberExport(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final exports = prefs.getStringList(_recentExportsKey) ?? <String>[];
    await prefs.setStringList(
      _recentExportsKey,
      <String>[path, ...exports].take(10).toList(),
    );
  }
}

class RenderService {
  static Future<Uint8List> renderPng(EditorState state) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    OfflineEditorPainter(
      state: state,
      forExport: true,
    ).paint(canvas, Size(exportWidthPx.toDouble(), exportHeightPx.toDouble()));
    final picture = recorder.endRecording();
    final image = await picture.toImage(exportWidthPx, exportHeightPx);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    if (byteData == null) {
      throw StateError('Unable to encode PNG export');
    }
    return byteData.buffer.asUint8List();
  }

  static Future<Uint8List> renderPdf(EditorState state) async {
    final pngBytes = await renderPng(state);
    final document = pw.Document();
    final image = pw.MemoryImage(pngBytes);
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(image, fit: pw.BoxFit.cover),
        ),
      ),
    );
    return document.save();
  }
}

class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key});

  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen> {
  @override
  Widget build(BuildContext context) {
    ref.listen<EditorState>(editorProvider, (previous, next) {
      if (next.notice != null && next.notice != previous?.notice) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(next.notice!)));
      }
    });

    final state = ref.watch(editorProvider);
    final controller = ref.read(editorProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline A4 Studio'),
        actions: [
          IconButton(
            tooltip: 'Export PNG at 300 DPI',
            onPressed: state.isBusy ? null : controller.exportPng,
            icon: const Icon(Icons.image_outlined),
          ),
          IconButton(
            tooltip: 'Export PDF at 300 DPI',
            onPressed: state.isBusy ? null : controller.exportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            tooltip: 'Print locally',
            onPressed: state.isBusy ? null : controller.printLayout,
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              if (wide) {
                return Row(
                  children: const [
                    SizedBox(width: 360, child: ControlPanel()),
                    VerticalDivider(width: 1),
                    Expanded(child: EditorWorkspace()),
                  ],
                );
              }

              return Column(
                children: const [
                  Expanded(child: EditorWorkspace()),
                  Divider(height: 1),
                  SizedBox(height: 330, child: ControlPanel()),
                ],
              );
            },
          ),
          if (state.isBusy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Processing locally on device...'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class EditorWorkspace extends StatelessWidget {
  const EditorWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B0D12),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const _StatusStrip(),
          const SizedBox(height: 14),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: a4WidthMm / a4HeightMm,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 34,
                        color: Colors.black54,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  child: const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    child: EditorCanvas(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusStrip extends ConsumerWidget {
  const _StatusStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        const _MetricChip(
          icon: Icons.straighten,
          label: 'A4 210 x 297 mm',
          value: '300 DPI',
        ),
        _MetricChip(
          icon: Icons.grid_view,
          label: 'Grid',
          value: '${state.columns} x ${state.rows}',
        ),
        _MetricChip(
          icon: Icons.crop,
          label: 'Selected',
          value: 'Slot ${state.selectedIndex + 1}',
        ),
        _MetricChip(
          icon: state.overlayImage == null
              ? Icons.layers_clear_outlined
              : Icons.layers_outlined,
          label: 'Overlay',
          value: state.overlayImage == null ? 'None' : 'All slots',
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF171B24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF283141)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: theme.textTheme.labelMedium?.copyWith(
              color: const Color(0xFF9EA8B8),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              color: const Color(0xFFEAF2F1),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class ControlPanel extends ConsumerWidget {
  const ControlPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final controller = ref.read(editorProvider.notifier);

    return Material(
      color: const Color(0xFF10131A),
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Local print layout',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No server, no cloud processing. Camera, gallery, crop, overlay, '
              'export, and print all run on device.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF9EA8B8)),
            ),
            const SizedBox(height: 18),
            _PanelCard(
              title: 'Photos',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Tap a slot on the A4 sheet, then add a camera or gallery '
                    'photo. Pinch to resize and drag to crop inside the slot.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF9EA8B8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: state.isBusy
                              ? null
                              : () => controller.pickPhoto(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Camera'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: state.isBusy
                              ? null
                              : () => controller.pickPhoto(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Gallery'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: state.isBusy
                        ? null
                        : controller.clearSelectedSlot,
                    icon: const Icon(Icons.delete_outline),
                    label: Text('Clear slot ${state.selectedIndex + 1}'),
                  ),
                ],
              ),
            ),
            _PanelCard(
              title: 'Grid and cutting',
              child: Column(
                children: [
                  _NumberSelector(
                    label: 'Columns',
                    value: state.columns,
                    onChanged: (value) => controller.setGrid(columns: value),
                  ),
                  _NumberSelector(
                    label: 'Rows',
                    value: state.rows,
                    onChanged: (value) => controller.setGrid(rows: value),
                  ),
                  _LabeledSlider(
                    label: 'Outer margin',
                    value: state.marginMm,
                    min: 0,
                    max: 24,
                    divisions: 24,
                    suffix: 'mm',
                    onChanged: (value) =>
                        controller.setSpacing(marginMm: value),
                  ),
                  _LabeledSlider(
                    label: 'Grid gap',
                    value: state.gapMm,
                    min: 0,
                    max: 16,
                    divisions: 16,
                    suffix: 'mm',
                    onChanged: (value) => controller.setSpacing(gapMm: value),
                  ),
                  SwitchListTile(
                    value: state.showCutBorders,
                    onChanged: (value) =>
                        controller.setCutBorders(enabled: value),
                    title: const Text('Cutting borders'),
                    subtitle: const Text('Show print-safe border guides'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  _LabeledSlider(
                    label: 'Border width',
                    value: state.cutBorderWidthMm,
                    min: 0.1,
                    max: 1.5,
                    divisions: 14,
                    suffix: 'mm',
                    onChanged: (value) =>
                        controller.setCutBorders(widthMm: value),
                  ),
                ],
              ),
            ),
            _PanelCard(
              title: 'PNG overlay',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: state.isBusy ? null : controller.importOverlay,
                    icon: const Icon(Icons.layers_outlined),
                    label: const Text('Import PNG overlay'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: state.applyOverlayToAll,
                    onChanged: state.overlayImage == null
                        ? null
                        : (value) =>
                              controller.setOverlayOptions(applyToAll: value),
                    title: const Text('Apply overlay to all photos'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  _LabeledSlider(
                    label: 'Overlay opacity',
                    value: state.overlayOpacity,
                    min: 0,
                    max: 1,
                    divisions: 20,
                    suffix: '',
                    onChanged: state.overlayImage == null
                        ? null
                        : (value) =>
                              controller.setOverlayOptions(opacity: value),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.overlayImage == null
                        ? null
                        : controller.clearOverlay,
                    icon: const Icon(Icons.layers_clear_outlined),
                    label: const Text('Clear overlay'),
                  ),
                ],
              ),
            ),
            _PanelCard(
              title: 'Export and print',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: state.isBusy ? null : controller.exportPng,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Export PNG 300 DPI'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: state.isBusy ? null : controller.exportPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Export PDF 300 DPI'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: state.isBusy ? null : controller.printLayout,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print from device'),
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

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _NumberSelector extends StatelessWidget {
  const _NumberSelector({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: List<Widget>.generate(6, (index) {
              final option = index + 1;
              return ChoiceChip(
                label: Text('$option'),
                selected: value == option,
                onSelected: (_) => onChanged(option),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final display = suffix.isEmpty
        ? value.toStringAsFixed(2)
        : '${value.toStringAsFixed(1)} $suffix';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Text(
                display,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF9EA8B8),
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class EditorCanvas extends ConsumerStatefulWidget {
  const EditorCanvas({super.key});

  @override
  ConsumerState<EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends ConsumerState<EditorCanvas> {
  int? _gestureSlotIndex;
  PhotoSlot? _gestureStartSlot;
  Offset? _gestureStartFocalPage;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);
    final controller = ref.read(editorProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final index = _slotIndexAt(details.localPosition, size, state);
            if (index != null) {
              controller.selectSlot(index);
            }
          },
          onScaleStart: (details) {
            final index = _slotIndexAt(details.localFocalPoint, size, state);
            if (index == null) {
              _gestureSlotIndex = null;
              _gestureStartSlot = null;
              _gestureStartFocalPage = null;
              return;
            }
            controller.selectSlot(index);
            _gestureSlotIndex = index;
            _gestureStartSlot = state.slots[index];
            _gestureStartFocalPage = canvasPointToPagePoint(
              details.localFocalPoint,
              size,
            );
          },
          onScaleUpdate: (details) {
            final index = _gestureSlotIndex;
            final startSlot = _gestureStartSlot;
            final startFocal = _gestureStartFocalPage;
            if (index == null || startSlot == null || startFocal == null) {
              return;
            }
            if (!startSlot.hasPhoto) {
              return;
            }
            final focal = canvasPointToPagePoint(details.localFocalPoint, size);
            controller.setCrop(
              index,
              startSlot.cropScale * details.scale,
              startSlot.cropOffset + (focal - startFocal),
            );
          },
          child: CustomPaint(
            painter: OfflineEditorPainter(state: state),
            size: Size.infinite,
          ),
        );
      },
    );
  }

  int? _slotIndexAt(Offset localPosition, Size canvasSize, EditorState state) {
    final pagePoint = canvasPointToPagePoint(localPosition, canvasSize);
    if (pagePoint.dx < 0 ||
        pagePoint.dy < 0 ||
        pagePoint.dx > a4WidthMm ||
        pagePoint.dy > a4HeightMm) {
      return null;
    }

    final slots = buildSlotRects(state);
    for (var index = 0; index < slots.length; index++) {
      if (slots[index].contains(pagePoint)) {
        return index;
      }
    }
    return null;
  }
}

class OfflineEditorPainter extends CustomPainter {
  const OfflineEditorPainter({required this.state, this.forExport = false});

  final EditorState state;
  final bool forExport;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = pageScaleForCanvas(size);
    final pagePixelSize = Size(a4WidthMm * scale, a4HeightMm * scale);
    final pageOffset = Offset(
      (size.width - pagePixelSize.width) / 2,
      (size.height - pagePixelSize.height) / 2,
    );

    if (!forExport) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFF0B0D12),
      );
    }

    canvas.save();
    canvas.translate(pageOffset.dx, pageOffset.dy);
    canvas.scale(scale);

    final pageRect = Rect.fromLTWH(0, 0, a4WidthMm, a4HeightMm);
    canvas.drawRect(pageRect, Paint()..color = const Color(0xFFF7F5EF));

    final slots = buildSlotRects(state);
    for (var index = 0; index < slots.length; index++) {
      _paintSlot(canvas, slots[index], state.slots[index], index);
    }

    if (state.showCutBorders) {
      final borderPaint = Paint()
        ..color = const Color(0xFF121212).withValues(alpha: 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = state.cutBorderWidthMm;
      _drawDashedRect(canvas, pageRect.deflate(0.7), borderPaint);
      for (final slotRect in slots) {
        _drawDashedRect(canvas, slotRect, borderPaint);
      }
    }

    canvas.restore();
  }

  void _paintSlot(Canvas canvas, Rect rect, PhotoSlot slot, int index) {
    final backgroundPaint = Paint()..color = const Color(0xFFE4E1D8);
    canvas.drawRect(rect, backgroundPaint);

    if (slot.image != null) {
      canvas.save();
      canvas.clipRect(rect);
      _drawCoverImage(
        canvas,
        image: slot.image!,
        rect: rect,
        scale: slot.cropScale,
        offset: slot.cropOffset,
        opacity: 1,
      );

      if (state.applyOverlayToAll && state.overlayImage != null) {
        _drawCoverImage(
          canvas,
          image: state.overlayImage!,
          rect: rect,
          scale: 1,
          offset: Offset.zero,
          opacity: state.overlayOpacity,
        );
      }
      canvas.restore();
    } else {
      _drawEmptySlot(canvas, rect, index);
    }

    final selected = index == state.selectedIndex;
    final outlinePaint = Paint()
      ..color = selected ? const Color(0xFF00D6B4) : const Color(0xFF8C8C8C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 0.9 : 0.35;
    canvas.drawRect(rect, outlinePaint);
  }

  void _drawCoverImage(
    Canvas canvas, {
    required ui.Image image,
    required Rect rect,
    required double scale,
    required Offset offset,
    required double opacity,
  }) {
    final coverScale = math.max(
      rect.width / image.width,
      rect.height / image.height,
    );
    final drawnWidth = image.width * coverScale * scale;
    final drawnHeight = image.height * coverScale * scale;
    final dst = Rect.fromCenter(
      center: rect.center + offset,
      width: drawnWidth,
      height: drawnHeight,
    );
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high
      ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0, 1).toDouble());
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      paint,
    );
  }

  void _drawEmptySlot(Canvas canvas, Rect rect, int index) {
    final paint = Paint()
      ..color = const Color(0xFFBFC3C7).withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.35;
    _drawDashedRect(canvas, rect.deflate(3), paint);

    final paragraphStyle = ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: 5.4,
      fontWeight: FontWeight.w700,
    );
    final textStyle = ui.TextStyle(color: const Color(0xFF6E737A));
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle)
      ..addText('SLOT ${index + 1}');
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: rect.width));
    canvas.drawParagraph(
      paragraph,
      Offset(rect.left, rect.center.dy - paragraph.height / 2),
    );
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    _drawDashedLine(canvas, rect.topLeft, rect.topRight, paint);
    _drawDashedLine(canvas, rect.topRight, rect.bottomRight, paint);
    _drawDashedLine(canvas, rect.bottomRight, rect.bottomLeft, paint);
    _drawDashedLine(canvas, rect.bottomLeft, rect.topLeft, paint);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dash = 3.0;
    const gap = 1.8;
    final delta = end - start;
    final distance = delta.distance;
    if (distance == 0) {
      return;
    }
    final direction = delta / distance;
    var traveled = 0.0;
    while (traveled < distance) {
      final segmentEnd = math.min(traveled + dash, distance);
      canvas.drawLine(
        start + direction * traveled,
        start + direction * segmentEnd,
        paint,
      );
      traveled += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant OfflineEditorPainter oldDelegate) {
    return oldDelegate.state != state || oldDelegate.forExport != forExport;
  }
}
