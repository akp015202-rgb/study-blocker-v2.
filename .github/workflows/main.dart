import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _ch = MethodChannel('guard');

void main() => runApp(const StudyApp());

class StudyApp extends StatelessWidget {
  const StudyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Study Blocker',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F1A),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF6C8CFF)),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  SharedPreferences? _p;
  Timer? _tick;
  final _ctrl = TextEditingController();

  bool _enabled = false;
  int _end = 0;
  int _minutes = 120;
  List<String> _channels = [];
  List<String> _allowed = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  // Settings se wapas aane par permission dobara check
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    bool en = false;
    try {
      en = await _ch.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _p = p;
      _enabled = en;
      _end = p.getInt('session_end') ?? 0;
      _channels = p.getStringList('channels') ?? [];
      _allowed = p.getStringList('allowed') ?? [];
    });
  }

  Future<void> _start() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Session shuru karein?'),
        content: Text(
            '$_minutes minute tak sirf allowed apps aur study channels chalenge. Shuru hone ke baad rok nahi paoge.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Nahi')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Haan, shuru')),
        ],
      ),
    );
    if (ok != true) return;

    final end = DateTime.now()
        .add(Duration(minutes: _minutes))
        .millisecondsSinceEpoch;
    await _ch.invokeMethod('start', {
      'sessionEnd': end,
      'channels': _channels,
      'allowed': _allowed,
    });
    await _p?.setInt('session_end', end);
    if (!mounted) return;
    setState(() => _end = end);
  }

  void _addChannel() {
    final n = _ctrl.text.trim();
    if (n.isEmpty || _channels.contains(n)) return;
    setState(() => _channels.add(n));
    _ctrl.clear();
    _p?.setStringList('channels', _channels);
  }

  Future<void> _pickApps() async {
    final r = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(builder: (_) => AppsPage(selected: _allowed)),
    );
    if (r != null) {
      setState(() => _allowed = r);
      await _p?.setStringList('allowed', r);
    }
  }

  Future<void> _showDebug() async {
    final ids = await _ch.invokeMethod<String>('getDebug') ?? '';
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Debug: YouTube view ids'),
        content: SingleChildScrollView(
          child: SelectableText(ids.isEmpty
              ? 'Kuch nahi mila. Session chalu karke YouTube kholo, phir yaha aao.'
              : ids),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
        ],
      ),
    );
  }

  String _fmt(int ms) {
    final s = (ms / 1000).ceil();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(s ~/ 3600)}:${two((s % 3600) ~/ 60)}:${two(s % 60)}';
  }

  Widget _card(Widget child) => Card(
        color: const Color(0xFF141A2B),
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      );

  @override
  Widget build(BuildContext context) {
    final left = _end - DateTime.now().millisecondsSinceEpoch;
    final active = left > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Study Blocker'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_enabled)
            _card(Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pehle permission do',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text(
                    'Accessibility settings me "Study Blocker" ko ON karo, phir wapas aao.'),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () => _ch.invokeMethod('openSettings'),
                  child: const Text('Settings kholo'),
                ),
              ],
            )),
          _card(active
              ? Column(
                  children: [
                    const Text('Session chal raha hai'),
                    const SizedBox(height: 8),
                    Text(_fmt(left),
                        style: const TextStyle(
                            fontSize: 48, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Ab ruk nahi sakta. Padhai karo!'),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Session ka time chuno',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final m in [1, 30, 60, 120])
                          ChoiceChip(
                            label: Text(m == 1 ? '1 min (test)' : '$m min'),
                            selected: _minutes == m,
                            onSelected: (_) => setState(() => _minutes = m),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _enabled ? _start : null,
                        child: const Text('Start Session'),
                      ),
                    ),
                  ],
                )),
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Study channels (YouTube)',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                  'Naam bilkul waisa likho jaisa video ke neeche dikhta hai. Koi channel nahi to YouTube poora band rahega.',
                  style: TextStyle(fontSize: 12)),
              if (!active) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      decoration:
                          const InputDecoration(labelText: 'Channel ka naam'),
                      onSubmitted: (_) => _addChannel(),
                    ),
                  ),
                  IconButton(
                      onPressed: _addChannel, icon: const Icon(Icons.add)),
                ]),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in _channels)
                    Chip(
                      label: Text(c),
                      onDeleted: active
                          ? null
                          : () {
                              setState(() => _channels.remove(c));
                              _p?.setStringList('channels', _channels);
                            },
                    ),
                ],
              ),
            ],
          )),
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Allowed apps',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('${_allowed.length} apps allowed. Phone/call, keyboard aur home screen hamesha chalenge.',
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: active ? null : _pickApps,
                child: const Text('Apps chuno'),
              ),
            ],
          )),
          TextButton.icon(
            onPressed: _showDebug,
            icon: const Icon(Icons.bug_report),
            label: const Text('Debug ids dekho'),
          ),
        ],
      ),
    );
  }
}

class AppsPage extends StatefulWidget {
  final List<String> selected;
  const AppsPage({super.key, required this.selected});

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  List<Map<String, String>> _apps = [];
  late Set<String> _sel;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _sel = widget.selected.toSet();
    _fetch();
  }

  Future<void> _fetch() async {
    final raw = await _ch.invokeMethod<List<dynamic>>('getApps');
    final list =
        (raw ?? []).map((e) => Map<String, String>.from(e as Map)).toList();
    if (!mounted) return;
    setState(() {
      _apps = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Allowed apps chuno')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pop(context, _sel.toList()),
        label: const Text('Save'),
        icon: const Icon(Icons.check),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _apps.length,
              itemBuilder: (_, i) {
                final a = _apps[i];
                final pkg = a['pkg']!;
                return CheckboxListTile(
                  title: Text(a['label'] ?? pkg),
                  subtitle: Text(pkg, style: const TextStyle(fontSize: 11)),
                  value: _sel.contains(pkg),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _sel.add(pkg);
                    } else {
                      _sel.remove(pkg);
                    }
                  }),
                );
              },
            ),
    );
  }
}
