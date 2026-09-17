// Web implementation: play the tick sound via raw HTMLAudioElement
// instances (package:web), completely bypassing the `audioplayers`
// package's AudioPlayer.global scope. That global scope was found to
// throw a MissingPluginException the first time any AudioPlayer/AudioPool
// is used in this app's Web build (channel:
// "xyz.luan/audioplayers.global/events"), which silently left every
// AudioPool.createFromAsset() future never completing - so the tick
// sound was permanently broken (haptic-only) despite no visible errors
// reaching the UI. A bare <audio> element's native .play() was
// separately confirmed to work fine in this same environment, so this
// implementation uses a small round-robin pool of pre-created
// HTMLAudioElements instead.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class TickSoundPoolImpl {
  final List<web.HTMLAudioElement> _players;
  int _next = 0;

  TickSoundPoolImpl._(this._players);

  static Future<TickSoundPoolImpl> create({required String assetPath}) async {
    // Flutter Web serves declared assets under assets/<assetPath>.
    final url = 'assets/assets/$assetPath';
    final players = List.generate(4, (_) {
      final audio = web.HTMLAudioElement()
        ..src = url
        ..preload = 'auto'
        ..volume = 1.0;
      audio.load();
      return audio;
    });
    return TickSoundPoolImpl._(players);
  }

  void play() {
    if (_players.isEmpty) return;
    final audio = _players[_next];
    _next = (_next + 1) % _players.length;
    try {
      audio.currentTime = 0;
      // play() returns a JS Promise; any rejection (e.g. AbortError from
      // rapid overlapping calls on the same element) is caught and
      // ignored - the next tick will just use a different pooled
      // element, so occasional dropped ticks during very fast scrolling
      // are harmless and don't need to be surfaced anywhere.
      audio.play().toDart.catchError((Object _) => null);
    } catch (_) {
      // Ignore - a dropped tick is not worth surfacing to the user.
    }
  }

  void dispose() {
    for (final p in _players) {
      p.pause();
    }
    _players.clear();
  }
}
