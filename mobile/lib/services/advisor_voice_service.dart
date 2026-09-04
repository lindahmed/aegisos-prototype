import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

abstract interface class AdvisorVoiceService {
  Future<bool> startRecording();

  Future<Uint8List?> stopRecording();

  Future<void> cancelRecording();

  Future<void> play(Uint8List audioBytes);

  Future<void> dispose();
}

class DeviceAdvisorVoiceService implements AdvisorVoiceService {
  DeviceAdvisorVoiceService({AudioRecorder? recorder, AudioPlayer? player})
    : _recorder = recorder ?? AudioRecorder(),
      _player = player ?? AudioPlayer();

  final AudioRecorder _recorder;
  final AudioPlayer _player;

  @override
  Future<bool> startRecording() async {
    if (!await _recorder.hasPermission()) return false;

    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/advisor_voice_${DateTime.now().microsecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: path,
    );
    return true;
  }

  @override
  Future<Uint8List?> stopRecording() async {
    final path = await _recorder.stop();
    if (path == null) return null;

    final file = File(path);
    try {
      return await file.readAsBytes();
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<void> cancelRecording() => _recorder.cancel();

  @override
  Future<void> play(Uint8List audioBytes) async {
    await _player.stop();
    await _player.play(BytesSource(audioBytes, mimeType: 'audio/mpeg'));
  }

  @override
  Future<void> dispose() async {
    await _recorder.dispose();
    await _player.dispose();
  }
}
