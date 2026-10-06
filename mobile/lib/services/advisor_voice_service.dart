import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:speech_to_text/speech_to_text.dart';

abstract interface class AdvisorVoiceService {
  Future<bool> startListening({
    required String language,
    required void Function(String words) onResult,
  });

  Future<String> stopListening();

  Future<void> cancelListening();

  Future<void> play(Uint8List audioBytes, {void Function()? onComplete});

  Future<void> stopPlayback();

  Future<void> dispose();
}

class DeviceAdvisorVoiceService implements AdvisorVoiceService {
  DeviceAdvisorVoiceService({SpeechToText? speech, AudioPlayer? player})
    : _speech = speech ?? SpeechToText(),
      _player = player ?? AudioPlayer();

  final SpeechToText _speech;
  final AudioPlayer _player;
  StreamSubscription<void>? _playerCompleteSubscription;
  String _recognizedWords = '';

  @override
  Future<bool> startListening({
    required String language,
    required void Function(String words) onResult,
  }) async {
    _recognizedWords = '';
    final available = await _speech.initialize(
      options: [SpeechToText.androidNoBluetooth],
    );
    if (!available) return false;
    final localePrefix = language == 'arabic' ? 'ar' : 'en';
    final locales = await _speech.locales();
    String? localeId;
    for (final locale in locales) {
      if (locale.localeId.toLowerCase().startsWith(localePrefix)) {
        localeId = locale.localeId;
        break;
      }
    }

    await _speech.listen(
      onResult: (result) {
        _recognizedWords = result.recognizedWords.trim();
        onResult(_recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        localeId: localeId,
        listenMode: ListenMode.confirmation,
        partialResults: true,
        cancelOnError: false,
      ),
    );
    return true;
  }

  @override
  Future<String> stopListening() async {
    await _speech.stop();
    return _recognizedWords;
  }

  @override
  Future<void> cancelListening() => _speech.cancel();

  @override
  Future<void> play(Uint8List audioBytes, {void Function()? onComplete}) async {
    await _playerCompleteSubscription?.cancel();
    _playerCompleteSubscription = _player.onPlayerComplete.listen((_) {
      onComplete?.call();
    });
    await _player.stop();
    await _player.play(BytesSource(audioBytes, mimeType: 'audio/mpeg'));
  }

  @override
  Future<void> stopPlayback() async {
    await _playerCompleteSubscription?.cancel();
    _playerCompleteSubscription = null;
    await _player.stop();
  }

  @override
  Future<void> dispose() async {
    await _playerCompleteSubscription?.cancel();
    await _speech.cancel();
    await _player.dispose();
  }
}
