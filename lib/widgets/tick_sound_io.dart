// Non-Web (Android/iOS/desktop) implementation: use the normal
// `audioplayers` package AudioPool as before - the MissingPluginException
// bug that breaks this on Web does not apply on these platforms.
import 'package:audioplayers/audioplayers.dart';

class TickSoundPoolImpl {
  final AudioPool _pool;

  TickSoundPoolImpl._(this._pool);

  static Future<TickSoundPoolImpl> create({required String assetPath}) async {
    final pool = await AudioPool.createFromAsset(
      path: assetPath,
      maxPlayers: 6,
      minPlayers: 3,
    );
    return TickSoundPoolImpl._(pool);
  }

  void play() {
    _pool.start(volume: 1.0);
  }

  void dispose() {
    _pool.dispose();
  }
}
