// Platform-conditional tick-sound player. On Web, the real
// implementation (tick_sound_web.dart) plays the click sound via raw
// HTMLAudioElement instances, completely bypassing the `audioplayers`
// package's global scope (AudioPlayer.global), which was found to throw
// a MissingPluginException on this environment's Web build the very
// first time ANY AudioPlayer/AudioPool is used - silently leaving the
// tick sound permanently broken (no sound, only haptic feedback) even
// though play() calls elsewhere appeared to succeed. On non-Web
// platforms (Android, etc.) that bug doesn't apply, so the io
// implementation (tick_sound_io.dart) uses the normal `audioplayers`
// package as usual.
import 'tick_sound_io.dart' if (dart.library.js_interop) 'tick_sound_web.dart'
    as impl;

class TickSoundPool {
  final impl.TickSoundPoolImpl _impl;

  TickSoundPool._(this._impl);

  static Future<TickSoundPool> create({required String assetPath}) async {
    final impl0 = await impl.TickSoundPoolImpl.create(assetPath: assetPath);
    return TickSoundPool._(impl0);
  }

  void play() => _impl.play();

  void dispose() => _impl.dispose();
}
