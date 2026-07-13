import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:shared_preferences/shared_preferences.dart';

/// Configurações do treino, persistidas entre sessões.
class TimerSettings {
  int rounds;
  int fightSeconds;
  int restSeconds;
  bool countDown;

  /// Logo da academia como PNG em memória (funciona em Android e web).
  Uint8List? logoBytes;

  TimerSettings({
    this.rounds = 10,
    this.fightSeconds = 3 * 60,
    this.restSeconds = 60,
    this.countDown = true,
    this.logoBytes,
  });

  static Future<TimerSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final logoBase64 = prefs.getString('logoBase64');
    return TimerSettings(
      rounds: prefs.getInt('rounds') ?? 10,
      fightSeconds: prefs.getInt('fightSeconds') ?? 3 * 60,
      restSeconds: prefs.getInt('restSeconds') ?? 60,
      countDown: prefs.getBool('countDown') ?? true,
      logoBytes: logoBase64 != null ? base64Decode(logoBase64) : null,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('rounds', rounds);
    await prefs.setInt('fightSeconds', fightSeconds);
    await prefs.setInt('restSeconds', restSeconds);
    await prefs.setBool('countDown', countDown);
    if (logoBytes == null) {
      await prefs.remove('logoBase64');
    } else {
      await prefs.setString('logoBase64', base64Encode(logoBytes!));
    }
  }
}

/// Redimensiona a imagem para no máximo [maxWidth] de largura e converte
/// para PNG, para não guardar fotos enormes nas preferências.
Future<Uint8List> resizeLogo(Uint8List input, {int maxWidth = 800}) async {
  var codec = await ui.instantiateImageCodec(input);
  var frame = await codec.getNextFrame();
  if (frame.image.width > maxWidth) {
    codec = await ui.instantiateImageCodec(input, targetWidth: maxWidth);
    frame = await codec.getNextFrame();
  }
  final data =
      await frame.image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

String formatTime(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
