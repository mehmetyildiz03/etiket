import 'package:flutter/material.dart';
import 'domain/fabric.dart';
import 'domain/analysis.dart';

void main() => runApp(const EtiketApp());

const _green = Color(0xFF254A3F);
const _cream = Color(0xFFF4F2EC);

class EtiketApp extends StatelessWidget {
  const EtiketApp({super.key});

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
      home: const EtiketHome(),
    );
  }
}

class _EditableFiber {
  String name;
  int percent;
  _EditableFiber(this.name, this.percent);
}

class _EditableSection {
  String name;
  final List<_EditableFiber> fibers;
  _EditableSection(this.name, this.fibers);
  int get total => fibers.fold(0, (sum, fiber) => sum + fiber.percent);
  bool get valid => name.trim().isNotEmpty && fibers.isNotEmpty &&
      fibers.every((fiber) => fiber.percent > 0 && fiber.percent <= 100) &&
      total == 100;
}

enum _Page { home, camera, edit, purpose, result }

class EtiketHome extends StatefulWidget {
  const EtiketHome({super.key});
  @override
  State<EtiketHome> createState() => _EtiketHomeState();
}

class _EtiketHomeState extends State<EtiketHome> {
  _Page page = _Page.home;
  WearPurpose purpose = WearPurpose.summer;
  final List<_EditableSection> sections = [
    _EditableSection('Ana kumaş', [_EditableFiber('Pamuk', 70), _EditableFiber('Polyester', 30)])
  ];

  bool get allValid => sections.isNotEmpty && sections.every((s) => s.valid);
  Garment get garment => Garment('Kıyafet', sections.map((s) => FabricSection(
    s.name, s.fibers.map((f) => FiberEntry(f.name, f.percent)).toList())).toList());

  void navigate(_Page target) => setState(() => page = target);
  void back() {
    navigate(switch (page) {
      _Page.home => _Page.home,
      _Page.camera => _Page.home,
      _Page.edit => _Page.camera,
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
    return Scaffold(
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
            if (page == _Page.edit) edit(),
            if (page == _Page.purpose) choosePurpose(),
            if (page == _Page.result) result(),
          ],
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
    const SizedBox(height: 22),
    const Text('Üyelik gerekmez • Şimdilik örnek tarama kullanılıyor',
      textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 12)),
  ]);

  Widget camera() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    pageTitle('Etiketi tara', 'Gerçek kamera bağlantısı sonraki geliştirme aşamasında eklenecek.'),
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

  Widget edit() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    pageTitle('Kumaş içeriğini doğrula',
      'Her bölümün elyaf oranları ayrı ayrı %100 olmalı. Okunamayan bilgileri tahmin etme.'),
    for (var s = 0; s < sections.length; s++) sectionEditor(s),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: () => setState(() => sections.add(
        _EditableSection('Yeni bölüm', [_EditableFiber('Pamuk', 100)]))),
      icon: const Icon(Icons.add), label: const Text('Kumaş bölümü ekle')),
    const SizedBox(height: 20),
    primary('Devam et', allValid ? () => navigate(_Page.purpose) : null),
  ]);

  Widget sectionEditor(int sectionIndex) {
    final section = sections[sectionIndex];
    return Card(key: ObjectKey(section), margin: const EdgeInsets.only(bottom: 12), child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: TextFormField(
            key: ObjectKey(section),
            initialValue: section.name,
            decoration: const InputDecoration(labelText: 'Bölüm adı'),
            onChanged: (value) => setState(() => section.name = value),
          )),
          if (sections.length > 1)
            IconButton(tooltip: 'Bölümü sil', icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => sections.removeAt(sectionIndex))),
        ]),
        const SizedBox(height: 12),
        for (var i = 0; i < section.fibers.length; i++)
          Padding(key: ObjectKey(section.fibers[i]), padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(flex: 3, child: DropdownButtonFormField<String>(
                key: ValueKey('fiber-$sectionIndex-$i-${section.fibers[i].name}'),
                initialValue: section.fibers[i].name,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Elyaf', isDense: true),
                items: knownFibers.map((name) =>
                  DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => section.fibers[i].name = value);
                  }
                },
              )),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: TextFormField(
                key: ObjectKey(section.fibers[i]),
                initialValue: section.fibers[i].percent.toString(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Yüzde', suffixText: '%', isDense: true),
                onChanged: (text) => setState(() => section.fibers[i].percent = int.tryParse(text) ?? -1),
              )),
              IconButton(icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Elyafı kaldır',
                onPressed: section.fibers.length == 1 ? null : () =>
                  setState(() => section.fibers.removeAt(i))),
            ])),
        Text('Toplam: %${section.total}',
          style: TextStyle(fontWeight: FontWeight.bold, color: section.valid ? _green : Colors.red)),
        const SizedBox(height: 8),
        TextButton.icon(onPressed: () => setState(() =>
            section.fibers.add(_EditableFiber('Diğer', 0))),
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
