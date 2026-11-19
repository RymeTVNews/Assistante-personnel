import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'avatar.dart';
import 'controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const SarraApp());
}

class SarraApp extends StatelessWidget {
  const SarraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sarra',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3A5A96), brightness: Brightness.dark),
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

class _HomePageState extends State<HomePage> {
  final c = SarraController();
  bool _dialogOpen = false;

  static const _green = Color(0xFF138A43);
  static const _red = Color(0xFFC9231A);
  static const _muted = Color(0xFFA9B4CF);

  @override
  void initState() {
    super.initState();
    c.onNeedKey = _askKey;
    WidgetsBinding.instance.addPostFrameCallback((_) => c.start());
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> _askKey() async {
    if (_dialogOpen || !mounted) return;
    _dialogOpen = true;
    final ctl = TextEditingController(text: await c.loadKey() ?? '');
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clé d'accès de Sarra"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Sarra réfléchit grâce à l'API Claude d'Anthropic. "
                'Collez ici votre clé API (console.anthropic.com). Elle reste sur ce téléphone.'),
            const SizedBox(height: 12),
            TextField(controller: ctl, obscureText: true, decoration: const InputDecoration(hintText: 'sk-ant-…')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    _dialogOpen = false;
    if (ok == true && ctl.text.trim().isNotEmpty) await c.saveKey(ctl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.4),
            radius: 1.2,
            colors: [Color(0xFF26407A), Color(0xFF16233F), Color(0xFF0D1630)],
            stops: [0, 0.46, 1],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: ListenableBuilder(
              listenable: c,
              builder: (context, _) => Column(
                children: [
                  _topCard(),
                  Expanded(child: _stage(context)),
                  _bottom(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Ce que Nathalie dit s'affiche en haut de l'écran.
  Widget _topCard() {
    final empty = c.said.isEmpty;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 108),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 12),
      decoration: BoxDecoration(color: Colors.white.withAlpha(20), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('NATHALIE', style: TextStyle(color: _muted, fontSize: 12, letterSpacing: 1.4)),
              const Spacer(),
              IconButton(
                tooltip: c.wakeOn ? "Écoute « Dis Sarra » active (toucher pour arrêter)" : "Activer l'écoute « Dis Sarra »",
                onPressed: c.toggleWake,
                icon: Icon(
                  c.wakeOn ? Icons.hearing : Icons.hearing_disabled,
                  color: c.wakeOn ? const Color(0xFF5BD68A) : _muted,
                  size: 22,
                ),
              ),
              IconButton(
                tooltip: "Clé d'accès",
                onPressed: _askKey,
                icon: const Icon(Icons.settings, color: _muted, size: 22),
              ),
            ],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: SingleChildScrollView(
              reverse: true,
              child: Text(
                empty ? 'Vos paroles apparaîtront ici.' : c.said,
                style: TextStyle(
                  fontSize: empty ? 16 : 21,
                  height: 1.35,
                  color: empty ? _muted : Colors.white,
                  fontStyle: empty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stage(BuildContext context) {
    const status = {
      SarraMode.idle: 'Appuyez sur PARLER pour parler à Sarra',
      SarraMode.listening: 'Sarra vous écoute…',
      SarraMode.thinking: 'Sarra réfléchit…',
      SarraMode.speaking: 'Sarra parle…',
    };
    final side = min(MediaQuery.of(context).size.width * 0.66, 280.0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(width: side, height: side, child: SarraAvatar(mode: c.mode)),
        const SizedBox(height: 6),
        SizedBox(height: 12, child: c.mode == SarraMode.thinking ? const _Dots() : null),
        const SizedBox(height: 6),
        Text(status[c.mode]!, style: const TextStyle(color: _muted, fontSize: 14)),
        const SizedBox(height: 8),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              c.reply,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, height: 1.4, color: Color(0xFFE4EAFB)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bottom(BuildContext context) {
    final live = c.mode == SarraMode.listening;
    final width = min(300.0, MediaQuery.of(context).size.width * 0.78);
    return Column(
      children: [
        SizedBox(
          height: 22,
          child: Text(c.note, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFD58A), fontSize: 13)),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: width,
          height: 76,
          child: ElevatedButton(
            onPressed: c.onTalk,
            style: ElevatedButton.styleFrom(
              backgroundColor: live ? _red : _green,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              elevation: 8,
            ),
            child: Text(
              live ? 'FIN' : 'PARLER',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 3),
            ),
          ),
        ),
      ],
    );
  }
}

class _Dots extends StatefulWidget {
  const _Dots();

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7CC4FF).withOpacity(0.25 + 0.75 * max(0, sin((_c.value - i * 0.15) * 2 * pi))),
              ),
            ),
        ],
      ),
    );
  }
}
