import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'settings.dart';
import 'timer_screen.dart';

/// Tela 1 — Configuração do treino.
class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  TimerSettings? _settings;

  @override
  void initState() {
    super.initState();
    TimerSettings.load().then((s) => setState(() => _settings = s));
  }

  Future<void> _pickLogo() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await resizeLogo(await picked.readAsBytes());
    setState(() => _settings!.logoBytes = bytes);
    await _settings!.save();
  }

  /// Diálogo para digitar o número de lutas.
  Future<void> _editRounds() async {
    final s = _settings!;
    final controller = TextEditingController(text: s.rounds.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Número de lutas'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          onSubmitted: (_) =>
              Navigator.of(ctx).pop(int.tryParse(controller.text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(controller.text)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() => s.rounds = result.clamp(1, 99));
    }
  }

  /// Diálogo para digitar um tempo (minutos e segundos separados).
  Future<void> _editTime({
    required String title,
    required int currentSeconds,
    required int minSeconds,
    required void Function(int) apply,
  }) async {
    final minCtrl =
        TextEditingController(text: (currentSeconds ~/ 60).toString());
    final secCtrl = TextEditingController(
        text: (currentSeconds % 60).toString().padLeft(2, '0'));

    int? readTotal() {
      final m = int.tryParse(minCtrl.text) ?? 0;
      final sec = int.tryParse(secCtrl.text) ?? 0;
      if (minCtrl.text.isEmpty && secCtrl.text.isEmpty) return null;
      return m * 60 + sec;
    }

    Widget timeField(TextEditingController c, String hint) => SizedBox(
          width: 72,
          child: TextField(
            controller: c,
            autofocus: c == minCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            decoration: InputDecoration(helperText: hint),
          ),
        );

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            timeField(minCtrl, 'min'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(':',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            ),
            timeField(secCtrl, 'seg'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(readTotal()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() => apply(result.clamp(minSeconds, 59 * 60 + 59)));
    }
  }

  Future<void> _start() async {
    final s = _settings!;
    if (s.fightSeconds < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('O tempo de luta deve ser de pelo menos 10 segundos.')));
      return;
    }
    await s.save();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TimerScreen(settings: s)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    if (s == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // Coluna do logo
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickLogo,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: s.logoBytes != null
                                ? Image.memory(s.logoBytes!,
                                    fit: BoxFit.contain)
                                : Image.asset('assets/images/logo.jpeg',
                                    fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    ),
                    const Text('Toque na imagem para trocar o logo',
                        style:
                            TextStyle(fontSize: 12, color: Colors.white54)),
                    if (s.logoBytes != null)
                      TextButton.icon(
                        onPressed: () async {
                          setState(() => s.logoBytes = null);
                          await s.save();
                        },
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Restaurar logo padrão'),
                      ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1, color: Colors.white12),
            // Coluna das configurações
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 12),
                            _NumberRow(
                              label: 'Número de lutas',
                              value: s.rounds.toString(),
                              onTapValue: _editRounds,
                              onMinus: () => setState(() =>
                                  s.rounds = (s.rounds - 1).clamp(1, 99)),
                              onPlus: () => setState(() =>
                                  s.rounds = (s.rounds + 1).clamp(1, 99)),
                            ),
                            _NumberRow(
                              label: 'Tempo de luta',
                              value: formatTime(s.fightSeconds),
                              onTapValue: () => _editTime(
                                title: 'Tempo de luta',
                                currentSeconds: s.fightSeconds,
                                minSeconds: 10,
                                apply: (v) => s.fightSeconds = v,
                              ),
                              onMinus: () => setState(() => s.fightSeconds =
                                  (s.fightSeconds - 15).clamp(15, 59 * 60)),
                              onPlus: () => setState(() => s.fightSeconds =
                                  (s.fightSeconds + 15).clamp(15, 59 * 60)),
                            ),
                            _NumberRow(
                              label: 'Tempo de descanso',
                              value: formatTime(s.restSeconds),
                              onTapValue: () => _editTime(
                                title: 'Tempo de descanso',
                                currentSeconds: s.restSeconds,
                                minSeconds: 0,
                                apply: (v) => s.restSeconds = v,
                              ),
                              onMinus: () => setState(() => s.restSeconds =
                                  (s.restSeconds - 5).clamp(0, 59 * 60)),
                              onPlus: () => setState(() => s.restSeconds =
                                  (s.restSeconds + 5).clamp(0, 59 * 60)),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Contagem regressiva',
                                  style: TextStyle(fontSize: 16)),
                              subtitle: const Text(
                                  'Mostrar tempo restante em vez de decorrido',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.white54)),
                              value: s.countDown,
                              onChanged: (v) =>
                                  setState(() => s.countDown = v),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            textStyle: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          onPressed: _start,
                          child: const Text('INICIAR'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Linha com rótulo, valor (tocável para digitar) e botões de - / +.
class _NumberRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTapValue;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _NumberRow({
    required this.label,
    required this.value,
    required this.onTapValue,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 16)),
          ),
          _RoundButton(icon: Icons.remove, onPressed: onMinus),
          InkWell(
            onTap: onTapValue,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 90,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.white38),
                ),
              ),
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          _RoundButton(icon: Icons.add, onPressed: onPlus),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _RoundButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white10,
        foregroundColor: Colors.white,
      ),
    );
  }
}
