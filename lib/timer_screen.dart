import 'dart:async';

import 'package:audio_session/audio_session.dart' as session;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'settings.dart';

// Duração de cada efeito sonoro + folga, usada para saber por quanto tempo
// manter a música de fundo (Spotify etc.) abaixada. Não depende do evento
// "terminou de tocar" do player, que se mostrou pouco confiável no modo de
// baixa latência usado aqui.
const _fightStartDuckDuration = Duration(milliseconds: 1300);
const _fightEndDuckDuration = Duration(milliseconds: 3300);
// O bip dura bem menos que 1s, mas os três tocam de segundo em segundo:
// mantemos o foco preso por 1s inteiro para não soltar e re-abaixar a
// música entre um bip e outro (isso soava como uma "piscada" de volume).
const _bipDuckDuration = Duration(milliseconds: 1000);

enum Phase { fight, rest, finished }

/// Tela 2 — Timer do treino.
class TimerScreen extends StatefulWidget {
  final TimerSettings settings;

  const TimerScreen({super.key, required this.settings});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  final _player = AudioPlayer();
  final _watch = Stopwatch();
  Timer? _ticker;
  Timer? _duckReleaseTimer;
  session.AudioSession? _audioSession;

  Phase _phase = Phase.fight;
  int _round = 1;
  bool _paused = false;
  int _lastBipSecond = 0;

  TimerSettings get s => widget.settings;

  int get _phaseLength =>
      _phase == Phase.fight ? s.fightSeconds : s.restSeconds;

  int get _elapsed => _watch.elapsedMilliseconds ~/ 1000;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _initAudio();
    _watch.start();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _duckReleaseTimer?.cancel();
    _audioSession?.setActive(false);
    _player.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _initAudio() async {
    // SoundPool (lowLatency) evita travamentos do MediaPlayer ao mudar de
    // rota de áudio (ex.: espelhamento de tela).
    await _player.setPlayerMode(PlayerMode.lowLatency);
    // O audioplayers pede foco de áudio "exclusivo" (pausa outros apps) por
    // padrão sempre que toca um som — desligamos isso aqui para que só o
    // audio_session, abaixo, negocie o foco (com "duck", não pausa).
    await _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
    ));

    // audio_session controla o foco de áudio diretamente — abaixa a música
    // de fundo (Spotify etc.) enquanto ativo e devolve o volume ao
    // desativar. Controlamos essa ativação/desativação nós mesmos (com
    // temporizadores), em vez de depender do player avisar quando o som
    // termina.
    final audioSession = await session.AudioSession.instance;
    await audioSession.configure(const session.AudioSessionConfiguration(
      avAudioSessionCategory: session.AVAudioSessionCategory.ambient,
      avAudioSessionCategoryOptions:
          session.AVAudioSessionCategoryOptions.duckOthers,
      androidAudioAttributes: session.AndroidAudioAttributes(
        contentType: session.AndroidAudioContentType.sonification,
        usage: session.AndroidAudioUsage.assistanceSonification,
      ),
      androidAudioFocusGainType:
          session.AndroidAudioFocusGainType.gainTransientMayDuck,
      androidWillPauseWhenDucked: false,
    ));
    _audioSession = audioSession;

    _play('fight_start.mp3', _fightStartDuckDuration);
  }

  Future<void> _play(String file, Duration duckDuration) async {
    try {
      await _audioSession?.setActive(true);
      await _player.stop();
      await _player.play(AssetSource('sounds/$file'));
      _duckReleaseTimer?.cancel();
      _duckReleaseTimer = Timer(duckDuration, () {
        _audioSession?.setActive(false);
      });
    } catch (_) {
      // Falha pontual de áudio (ex.: foco negado) não deve travar o timer.
    }
  }

  void _tick() {
    if (_phase == Phase.finished || _paused) return;

    final remaining = _phaseLength - _elapsed;

    // Bip nos últimos 3 segundos da luta (3, 2 e 1).
    if (_phase == Phase.fight &&
        remaining >= 1 &&
        remaining <= 3 &&
        remaining != _lastBipSecond) {
      _lastBipSecond = remaining;
      _play('bip.mp3', _bipDuckDuration);
    }

    if (_watch.elapsedMilliseconds >= _phaseLength * 1000) {
      _nextPhase();
    }

    setState(() {});
  }

  void _nextPhase() {
    _watch
      ..stop()
      ..reset();
    _lastBipSecond = 0;

    if (_phase == Phase.fight) {
      if (_round >= s.rounds) {
        _phase = Phase.finished;
        _play('fight_end.mp3', _fightEndDuckDuration);
        return;
      }
      if (s.restSeconds == 0) {
        // Sem descanso: emenda direto na próxima luta.
        _round++;
        _play('fight_end.mp3', _fightEndDuckDuration);
      } else {
        _phase = Phase.rest;
        _play('fight_end.mp3', _fightEndDuckDuration);
      }
    } else {
      _phase = Phase.fight;
      _round++;
      _play('fight_start.mp3', _fightStartDuckDuration);
    }
    _watch.start();
  }

  void _togglePause() {
    if (_phase == Phase.finished) return;
    setState(() {
      _paused = !_paused;
      _paused ? _watch.stop() : _watch.start();
    });
  }

  Future<void> _confirmExit() async {
    if (_phase == Phase.finished) {
      Navigator.of(context).pop();
      return;
    }
    final wasPaused = _paused;
    if (!wasPaused) _togglePause();
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encerrar treino?'),
        content: const Text('O timer será interrompido.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Continuar treino'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );
    if (leave == true) {
      if (mounted) Navigator.of(context).pop();
    } else if (!wasPaused) {
      _togglePause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFight = _phase == Phase.fight;
    final finished = _phase == Phase.finished;
    final accent = finished
        ? Colors.green
        : isFight
            ? Colors.red.shade600
            : Colors.amber.shade600;

    final remainingFights = s.rounds - _round;
    final displaySeconds = s.countDown
        ? (_phaseLength - _elapsed).clamp(0, _phaseLength)
        : _elapsed.clamp(0, _phaseLength);

    final label = finished
        ? 'TREINO CONCLUÍDO'
        : isFight
            ? 'LUTA $_round/${s.rounds}'
            : 'DESCANSO';

    final bottomText = finished
        ? 'Bom trabalho!'
        : remainingFights == 0
            ? 'Última luta'
            : remainingFights == 1
                ? 'Falta 1 luta'
                : 'Faltam $remainingFights lutas';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePause,
            child: Stack(
              children: [
                Column(
                  children: [
                    // Logo da academia
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: s.logoBytes != null
                            ? Image.memory(s.logoBytes!, fit: BoxFit.contain)
                            : Image.asset('assets/images/logo.jpeg',
                                fit: BoxFit.contain),
                      ),
                    ),
                    // LUTA X/N ou DESCANSO
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        color: accent,
                      ),
                    ),
                    // Tempo
                    Expanded(
                      flex: 5,
                      child: finished
                          ? Center(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.green.shade700,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 32, vertical: 16),
                                  textStyle: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold),
                                ),
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.replay),
                                label: const Text('VOLTAR'),
                              ),
                            )
                          : FittedBox(
                              fit: BoxFit.contain,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  formatTime(displaySeconds),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color:
                                        _paused ? Colors.white38 : Colors.white,
                                    fontSize: 200,
                                    height: 1,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    ),
                    // Lutas restantes
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        bottomText,
                        style: const TextStyle(
                            fontSize: 20, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
                // Indicador de pausa
                if (_paused)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Text(
                        'PAUSADO — toque para continuar',
                        style: TextStyle(fontSize: 22, color: Colors.white),
                      ),
                    ),
                  ),
                // Botões de canto
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    onPressed: _confirmExit,
                    icon: const Icon(Icons.close, color: Colors.white54),
                  ),
                ),
                if (!finished)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: IconButton(
                      onPressed: _togglePause,
                      icon: Icon(
                        _paused ? Icons.play_arrow : Icons.pause,
                        color: Colors.white54,
                        size: 32,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
