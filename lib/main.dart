import 'dart:async';
import 'package:flutter/material.dart';
import 'domain/fabric.dart';
import 'domain/analysis.dart';
import 'domain/composition_draft.dart';
import 'scan/photo_scan.dart';
import 'scan/scan_services.dart';
import 'ui/photo_scan_panel.dart';
import 'ui/photo_crop_editor.dart';
import 'scan/photo_edit.dart';

void main() => runApp(const EtiketApp());

const _green = Color(0xFF254A3F);
const _cream = Color(0xFFF4F2EC);

class EtiketApp extends StatelessWidget {
  const EtiketApp({super.key, this.photoSource, this.textRecognizer});
  final PhotoSourceService? photoSource;
  final TextRecognitionService? textRecognizer;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doku • Etiket',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _cream,
        colorScheme: ColorScheme.fromSeed(seedColor: _green, primary: _green),
        appBarTheme: const AppBarTheme(backgroundColor: _cream),
        cardTheme: CardThemeData(color: Colors.white, elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)))),
      ),
      home: EtiketHome(photoSource: photoSource, textRecognizer: textRecognizer),
    );
  }
}

enum _Page { home, camera, label, edit, purpose, result }

class EtiketHome extends StatefulWidget {
  const EtiketHome({super.key, this.photoSource, this.textRecognizer});
  final PhotoSourceService? photoSource;
  final TextRecognitionService? textRecognizer;
  @override
  State<EtiketHome> createState() => _EtiketHomeState();
}

class _EtiketHomeState extends State<EtiketHome> with WidgetsBindingObserver {
  _Page page = _Page.home;
  WearPurpose purpose = WearPurpose.summer;
  final CompositionDraft draft = CompositionDraft.sample();
  final TextEditingController labelController = TextEditingController();
  LabelImportProposal? labelProposal;
  _Page labelReturnPage = _Page.home;
  late final PhotoScanController scan;
  bool _recoveringStartup = true;
  bool _labelFromOcr = false;
  int _labelEditRevision = 0;
  bool _photoChanged = false;
  ScanPhoto? _lastScanPhoto;

  bool get allValid => draft.canAnalyze;
  Garment get garment => draft.verifiedGarment();

  @override
  void initState() {
    super.initState();
    final services = createScanServices();
    scan = PhotoScanController(widget.photoSource ?? services.photos,
      widget.textRecognizer ?? services.recognizer);
    scan.onChanged = () {
      if (!mounted) return;
      setState(() {
        final current = scan.photo;
        if (current != null && !identical(current, _lastScanPhoto)) {
          draft.confirmSource(false);
          labelProposal = null;
          _photoChanged = true;
        }
        _lastScanPhoto = current;
        if (_recoveringStartup && page == _Page.home &&
            ((scan.stage == ScanStage.preview && scan.photo != null) || scan.stage == ScanStage.failed)) {
          page = _Page.camera;
        }
      });
    };
    WidgetsBinding.instance.addObserver(this);
    unawaited(scan.recover().whenComplete(() => _recoveringStartup = false));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // An external camera/picker legitimately backgrounds the activity. Only
    // suspend OCR; its eventual result must not be applied after suspension.
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.hidden) &&
        scan.stage == ScanStage.recognizing) {
      scan.cancel(message: 'Tarama duraklatıldı. Geri döndüğünde tekrar okuyabilirsin.');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    scan.dispose();
    labelController.dispose();
    super.dispose();
  }

  void openLabel(_Page from) {
    FocusScope.of(context).unfocus();
    setState(() {
      labelReturnPage = from;
      _labelFromOcr = false;
      labelProposal = null;
      page = _Page.label;
    });
    _recoveringStartup = false;
    scan.abandon();
  }

  Future<void> openOcrLabel() async {
    if (scan.stage != ScanStage.ready) return;
    final text = scan.text;
    final scanRevision = scan.revision;
    final editRevision = _labelEditRevision;
    if (labelController.text.isNotEmpty && labelController.text != text) {
      final replace = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Önceki metin değiştirilsin mi?'),
        content: const Text('Fotoğraftan okunan metin, metin alanının yerini alacak. Kumaş düzenlemelerin bu adımda değişmez.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Metnimi koru')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Fotoğraf metnini kullan')),
        ],
      )) ?? false;
      if (!replace) return;
    }
    if (!mounted || page != _Page.camera || scan.revision != scanRevision ||
        _labelEditRevision != editRevision || scan.stage != ScanStage.ready) {
      return;
    }
    setState(() {
      labelController.text = text;
      ++_labelEditRevision;
      labelProposal = null;
      _labelFromOcr = true;
      labelReturnPage = _Page.camera;
      page = _Page.label;
    });
    // Keep editable Web originals only for this scan session; native cleanup is unchanged.
    _photoChanged = false;
    if (!scan.canEditPhoto) scan.abandon();
  }

  Future<void> openPhotoEditor() async {
    if (!scan.beginPhotoEdit()) return;
    final source = scan.originalPhoto!.sourceImage!;
    var fallback = 0;
    await showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (dialogContext) => Dialog.fullscreen(
        child: PhotoCropEditor(
          source: source,
          initial: scan.appliedEdit ?? const PhotoEdit(),
          onApply: (edit) async {
            final applied = await scan.applyPhotoEdit(edit);
            if (applied && mounted) {
              setState(() {
                _photoChanged = true;
                labelProposal = null;
                draft.confirmSource(false);
              });
            }
            return applied
                ? null
                : (scan.message ??
                      'Düzenleme iptal edildi. Tekrar deneyebilirsin.');
          },
          onPaste: () {
            fallback = 1;
            Navigator.pop(dialogContext);
          },
          onManual: () {
            fallback = 2;
            Navigator.pop(dialogContext);
          },
        ),
      ),
    );
    scan.cancelPhotoEdit();
    if (!mounted) return;
    if (fallback == 1) openLabel(_Page.camera);
    if (fallback == 2) navigate(_Page.edit);
  }

  Future<void> applyLabel() async {
    final proposal = labelProposal;
    if (proposal == null) {
      return;
    }
    var replace = false;
    if (draft.hasUserChanges) {
      replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mevcut düzenlemeler değiştirilsin mi?'),
          content: const Text('Yeni metin mevcut bileşimin yerini alacak. İptal edersen düzeltmelerin korunur.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Düzenlemeleri koru')),
            TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Yeni metni kullan')),
          ],
        ),
      ) ?? false;
      if (!replace) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      if (draft.applyImport(proposal, replaceUserChanges: replace)) {
        page = _Page.edit;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bileşim değişmiş. Metni tekrar ayrıştırın; düzeltmeler korunuyor.')),
        );
      }
    });
  }

  void navigate(_Page target) {
    final leaveScan = page == _Page.camera && target != _Page.camera;
    final cancelRecovery = _recoveringStartup;
    _recoveringStartup = false;
    setState(() => page = target);
    if (leaveScan || cancelRecovery || target == _Page.home) scan.abandon();
  }
  void back() {
    FocusScope.of(context).unfocus();
    navigate(switch (page) {
      _Page.home => _Page.home,
      _Page.camera => _Page.home,
      _Page.label => labelReturnPage,
      _Page.edit => draft.imported ? _Page.label : _Page.camera,
      _Page.purpose => _Page.edit,
      _Page.result => _Page.purpose,
    });
  }

  Widget primary(String label, VoidCallback? onPressed, {IconData? icon}) {
    return FilledButton.icon(onPressed: onPressed, icon: Icon(icon ?? Icons.arrow_forward),
      label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)));
  }

  Widget pageTitle(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _green)),
      const SizedBox(height: 9),
      Text(subtitle, style: TextStyle(fontSize: 15, color: Colors.grey.shade700, height: 1.4)),
      const SizedBox(height: 24),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: page == _Page.home,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          back();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        leading: page == _Page.home ? const Icon(Icons.checkroom, color: _green)
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: back,
                tooltip: 'Geri'),
        title: const Text('doku.', style: TextStyle(fontWeight: FontWeight.w900,
          letterSpacing: -0.8, color: _green)),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            if (page == _Page.home) home(),
            if (page == _Page.camera) camera(),
            if (page == _Page.label) labelEntry(),
            if (page == _Page.edit) edit(),
            if (page == _Page.purpose) choosePurpose(),
            if (page == _Page.result) result(),
          ],
        ),
      ),
      ),
    );
  }

  Widget home() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    pageTitle('Ne giydiğini gerçekten bil.',
      'Kıyafetinin kumaş içeriğini öğren, avantajlarını ve bilinmeyenlerini gör.'),
    Card(child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 18),
      child: Column(children: [
        const Icon(Icons.sell_outlined, size: 64, color: _green),
        const SizedBox(height: 10),
        const Text('%70 PAMUK  ·  %30 POLYESTER',
          style: TextStyle(fontWeight: FontWeight.bold, color: _green)),
        const SizedBox(height: 8),
        Text('Etiketinden fazlasını öğren.', style: TextStyle(color: Colors.grey.shade700)),
      ]),
    )),
    const SizedBox(height: 20),
    primary('Etiket tara', () => navigate(_Page.camera), icon: Icons.camera_alt_outlined),
    const SizedBox(height: 12),
    OutlinedButton.icon(onPressed: () => navigate(_Page.edit),
      icon: const Icon(Icons.edit_note), label: const Text('Elle kumaş bilgisi gir')),
    const SizedBox(height: 12),
    OutlinedButton.icon(onPressed: () => openLabel(_Page.home),
      icon: const Icon(Icons.content_paste), label: const Text('Etiket metnini yapıştır')),
    const SizedBox(height: 22),
    const Text('Üyelik gerekmez • Etiketini kontrol ederek doğrula',
      textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 12)),
  ]);

  Widget camera() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    pageTitle('Etiketi tara', 'Etiketi net ve aydınlık çek. Okunan yazıyı kontrol etmeden doğrulamıyoruz.'),
    PhotoScanPanel(scan: scan, onReview: openOcrLabel, onEdit: openPhotoEditor,
      onManual: () => navigate(_Page.edit), onPaste: () => openLabel(_Page.camera)),
    const SizedBox(height: 24),
    const Text('DEMO — fotoğraf veya OCR kullanılmaz', style: TextStyle(color: Colors.black54)),
    const SizedBox(height: 8),
    Container(height: 260, decoration: BoxDecoration(color: const Color(0xFF202824),
        borderRadius: BorderRadius.circular(22)),
      child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.document_scanner_outlined, color: Colors.white, size: 64),
        SizedBox(height: 14),
        Text('70% COTTON', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        Text('30% POLYESTER', style: TextStyle(color: Colors.white)),
        SizedBox(height: 14),
        Text('ÖRNEK ETİKET', style: TextStyle(color: Colors.white70, fontSize: 12)),
      ])),
    const SizedBox(height: 20),
    primary('Örnek etiketle devam et', () => navigate(_Page.edit)),
    const SizedBox(height: 12),
    OutlinedButton(onPressed: () => navigate(_Page.edit),
      child: const Text('Bilgileri elle gir')),
  ]);

  Widget labelEntry() {
    final proposal = labelProposal;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      pageTitle(_labelFromOcr ? 'Fotoğraftan okunan metin' : 'Etiket metnini yapıştır',
        _labelFromOcr
          ? 'OCR hata yapabilir. Metni etiketle karşılaştırıp düzelt. Ayrıştırma ve açık doğrulama sonraki adımlardır.'
          : 'Metni cihazında ayrıştırırız. Eksik oranları veya belirsiz elyafları tahmin etmeyiz.'),
      if (_photoChanged) const Padding(padding: EdgeInsets.only(bottom: 12),
        child: Text('Fotoğraf değişti. Önceki metnin korunuyor; yeni görüntüyü tekrar oku veya metni etiketle karşılaştırarak düzelt.')),
      TextField(
        key: const ValueKey('label-text'),
        controller: labelController,
        minLines: 4,
        maxLines: 8,
        maxLength: 20000,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(
          labelText: 'Etiket metni',
          hintText: 'Dış kumaş: %70 Pamuk %30 Polyester\nAstar: Viskon %100',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) {
          ++_labelEditRevision;
          setState(() => labelProposal = null);
        },
      ),
      const SizedBox(height: 12),
      primary('Metni ayrıştır', () {
        FocusScope.of(context).unfocus();
        setState(() => labelProposal = draft.prepareImport(labelController.text));
      }, icon: Icons.find_in_page_outlined),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: () {
        FocusScope.of(context).unfocus();
        navigate(_Page.edit);
      }, child: const Text('Elle girişe dön')),
      if (proposal != null) ...[
        const SizedBox(height: 20),
        const Text('Ayrıştırma önerisi', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const Text('Henüz doğrulanmadı', style: TextStyle(color: Colors.blueGrey)),
        for (final issue in proposal.label.issues)
          Padding(padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(issue.message, style: const TextStyle(color: Colors.red))),
        for (final section in proposal.label.sections)
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(section.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              for (final fiber in section.fibers) ...[
                const SizedBox(height: 8),
                Text('${fiber.name ?? (fiber.rawName.isEmpty ? 'Elyaf adı eksik' : fiber.rawName)}'
                  '${fiber.percent == null ? ' — yüzde eksik/geçersiz' : ' %${formatPercentage(fiber.percent!)}'}'),
                Text('Kaynak: ${fiber.rawText}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                for (final issue in fiber.issues)
                  Text(issue.message, style: const TextStyle(color: Colors.red)),
              ],
              for (final issue in section.issues)
                Text(issue.message, style: const TextStyle(color: Colors.red)),
            ],
          ))),
        ExpansionTile(title: const Text('Ham etiket metni'), children: [
          Padding(padding: const EdgeInsets.all(12), child: SelectableText(proposal.label.rawText)),
        ]),
        if (proposal.label.sections.isNotEmpty) ...[
          const SizedBox(height: 12),
          primary('Düzenleyicide incele', applyLabel, icon: Icons.edit_note),
        ],
      ],
    ]);
  }

  Widget edit() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    pageTitle('Kumaş içeriğini doğrula',
      'Her bölümün elyaf oranları ayrı ayrı %100 olmalı. Okunamayan bilgileri tahmin etme.'),
    if (!draft.imported && !draft.hasUserChanges)
      const Padding(padding: EdgeInsets.only(bottom: 12),
        child: Text('Başlangıç değerleri örnektir. Kendi etiketindeki bilgileri gir.',
          style: TextStyle(color: Colors.black54))),
    if (draft.rawText != null)
      ExpansionTile(title: const Text('Ham etiket metni'), children: [
        Padding(padding: const EdgeInsets.all(12), child: SelectableText(draft.rawText!)),
      ]),
    for (final section in draft.sections) sectionEditor(section),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: () => setState(draft.addSection),
      icon: const Icon(Icons.add), label: const Text('Kumaş bölümü ekle')),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: () => openLabel(_Page.edit),
      icon: const Icon(Icons.content_paste), label: const Text('Başka metin ayrıştır')),
    if (draft.imported) ...[
      const SizedBox(height: 12),
      if (!draft.isValid)
        const Text('Eksik, belirsiz veya çelişkili bilgileri düzeltmeden doğrulama yapamazsın.',
          style: TextStyle(color: Colors.red)),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Etiketle karşılaştırdım ve doğruladım'),
        value: draft.sourceConfirmed,
        onChanged: draft.isValid ? (value) => setState(() => draft.confirmSource(value ?? false)) : null,
      ),
    ],
    const SizedBox(height: 20),
    primary('Devam et', allValid ? () => navigate(_Page.purpose) : null),
  ]);

  Widget sectionEditor(DraftSection section) {
    return Card(key: ValueKey(section.id), margin: const EdgeInsets.only(bottom: 12),
      child: Padding(padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: TextFormField(
              key: ValueKey('name-${section.id}'),
              initialValue: section.name,
              decoration: InputDecoration(labelText: 'Bölüm adı',
                errorText: section.headingNeedsReview
                  ? 'Bölüm adını kontrol edip düzenleyin.' : null),
              onChanged: (value) => setState(() => draft.setSectionName(section.id, value)),
            )),
            if (draft.sections.length > 1)
              IconButton(tooltip: 'Bölümü sil', icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => draft.removeSection(section.id))),
          ]),
          const SizedBox(height: 12),
          for (final fiber in section.fibers)
            Padding(key: ValueKey(fiber.id), padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(flex: 3, child: DropdownButtonFormField<String>(
                    key: ValueKey('fiber-${fiber.id}-${fiber.name ?? ''}'),
                    initialValue: fiber.name ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Elyaf', isDense: true),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Elyafı seç')),
                      for (final name in knownFibers)
                        DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (value) => setState(() => draft.setFiberName(
                      fiber.id, value == null || value.isEmpty ? null : value)),
                  )),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: TextFormField(
                    key: ValueKey('percent-${fiber.id}'),
                    initialValue: fiber.percentageText,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Yüzde', suffixText: '%', isDense: true),
                    onChanged: (text) => setState(() => draft.setPercentage(fiber.id, text)),
                  )),
                  IconButton(icon: const Icon(Icons.remove_circle_outline), tooltip: 'Elyafı kaldır',
                    onPressed: section.fibers.length == 1 ? null : () =>
                      setState(() => draft.removeFiber(fiber.id))),
                ]),
                if (fiber.rawText != null)
                  Text('Kaynak: ${fiber.rawText}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                if (!fiber.isValid)
                  Text(fiber.name == null
                    ? 'Elyafı elle seçin; kaynak belirsiz olabilir.'
                    : 'Geçerli bir yüzde girin (0’dan büyük, en fazla 100; en çok iki ondalık basamak).',
                    style: const TextStyle(color: Colors.red)),
              ])),
          Text('Toplam: %${formatPercentage(section.total)}',
            style: TextStyle(fontWeight: FontWeight.bold, color: section.isValid ? _green : Colors.red)),
          if (section.imported && section.hasDuplicateFibers)
            const Text('Aynı elyaf bu bölümde tekrarlanıyor; satırları kontrol edin.',
              style: TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
          TextButton.icon(onPressed: () => setState(() => draft.addFiber(section.id)),
            icon: const Icon(Icons.add), label: const Text('Elyaf ekle')),
        ]),
      ));
  }

  Widget choosePurpose() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    pageTitle('Nasıl kullanacaksın?',
      'Bu seçim, bilgilerin hangi açıdan yorumlanacağını değiştirir.'),
    RadioGroup<WearPurpose>(
      groupValue: purpose,
      onChanged: (value) {
        if (value != null) {
          setState(() => purpose = value);
        }
      },
      child: const Column(children: [
        RadioListTile<WearPurpose>(title: Text('Sıcak havalarda'),
          secondary: Icon(Icons.wb_sunny_outlined), value: WearPurpose.summer),
        RadioListTile<WearPurpose>(title: Text('Spor yaparken'),
          secondary: Icon(Icons.directions_run), value: WearPurpose.sport),
        RadioListTile<WearPurpose>(title: Text('Günlük kullanım'),
          secondary: Icon(Icons.checkroom), value: WearPurpose.daily),
      ]),
    ),
    const SizedBox(height: 28),
    primary('Analizi göster', () => navigate(_Page.result)),
  ]);

  Widget result() {
    final insights = analyzeGarment(garment, purpose);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      pageTitle('Kumaş analizi', 'Etiket bilgisi ile tahmini değerlendirmeleri ayrı gösteriyoruz.'),
      for (final insight in insights)
        Card(child: Padding(padding: const EdgeInsets.all(17),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(insight.confirmed ? Icons.verified_outlined : Icons.info_outline,
                color: insight.confirmed ? _green : Colors.blueGrey),
              const SizedBox(width: 8),
              Expanded(child: Text(insight.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 8),
            Text(insight.description, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 8),
            Text(insight.confirmed ? 'KONTROL EDİLEN ETİKET BİLGİSİ' : 'GENEL YORUM / TAHMİN',
              style: const TextStyle(fontSize: 10, color: Colors.black54)),
          ]))),
      const SizedBox(height: 15),
      primary('Yeni analiz', () => navigate(_Page.home), icon: Icons.restart_alt),
    ]);
  }
}
