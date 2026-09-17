// Web implementation: play the tick sound via the Web Audio API
// (AudioContext + decoded AudioBuffer + a fresh AudioBufferSourceNode per
// tick), NOT via HTMLAudioElement/<audio>.play().
//
// History of why this file looks the way it does:
// 1. The `audioplayers` package's AudioPool was found to throw a
//    MissingPluginException on Web in this app (channel:
//    "xyz.luan/audioplayers.global/events"), silently leaving the tick
//    sound permanently broken (haptic-only, no audio at all).
// 2. Switching to a small pool of raw HTMLAudioElements (each replayed
//    via `audio.currentTime = 0; audio.play();`) fixed that - but only
//    on Android/desktop Chrome. On iOS Safari specifically, resetting
//    currentTime and re-calling play() on an <audio> element is a
//    comparatively heavy, partially-synchronous operation (it can
//    involve re-validating the decode/seek state on the media element),
//    and doing this once per dial notch while the user drags fast was
//    enough to visibly stutter/jank the ListWheelScrollView's scroll
//    animation on iOS - "カクカクする" - even though the exact same code
//    was perfectly smooth on Android.
// 3. This version avoids HTMLMediaElement entirely for playback: the mp3
//    is fetched and decoded ONCE (via AudioContext.decodeAudioData) into
//    an in-memory AudioBuffer, and each tick just creates a brand new,
//    extremely cheap AudioBufferSourceNode wired to the destination and
//    calls start(0) - no seeking, no re-validating an <audio> element's
//    playback/network state, no promise-based play() call at all. This
//    is the standard low-latency approach recommended for rapid-fire
//    sound effects on Web and should be equally cheap on iOS Safari and
//    Android Chrome.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class TickSoundPoolImpl {
  web.AudioContext? _ctx;
  web.AudioBuffer? _buffer;

  TickSoundPoolImpl._();

  static Future<TickSoundPoolImpl> create({required String assetPath}) async {
    final impl = TickSoundPoolImpl._();
    try {
      final ctx = web.AudioContext();
      final url = 'assets/assets/$assetPath';
      final response = await web.window.fetch(url.toJS).toDart;
      final arrayBuffer = await response.arrayBuffer().toDart;
      final buffer = await ctx.decodeAudioData(arrayBuffer).toDart;
      impl._ctx = ctx;
      impl._buffer = buffer;
    } catch (_) {
      // If Web Audio setup fails for any reason, play() below just
      // becomes a silent no-op (haptic feedback still fires from the
      // caller) - never worth crashing the dial picker over a sound
      // effect.
    }
    return impl;
  }

  void play() {
    final ctx = _ctx;
    final buffer = _buffer;
    if (ctx == null || buffer == null) return;
    try {
      if (ctx.state == 'suspended') {
        // Fire-and-forget resume; on platforms/browsers that need a user
        // gesture to unlock audio, by the time the user is dragging the
        // dial that gesture has already happened, so this normally
        // resolves near-instantly (and the current tick may still be
        // silent-if-first, which is harmless).
        ctx.resume();
      }
      final source = ctx.createBufferSource();
      source.buffer = buffer;
      source.connect(ctx.destination);
      source.start(0);
    } catch (_) {
      // A dropped tick is not worth surfacing to the user.
    }
  }

  void dispose() {
    _ctx?.close();
    _ctx = null;
    _buffer = null;
  }
}
