/// Draws the biological-age sphere: one `drawRawAtlas` call per frame.
///
/// ## Why an atlas
///
/// About two thousand dots at 30 fps is two thousand `drawCircle` calls a frame
/// if drawn naively. `drawRawAtlas` takes the lot as three typed lists (a
/// transform, a source rect and a colour per dot) and one sprite, and the GPU
/// draws them as a single batch. The sprite is a white disc; the per-dot colour
/// tints it (`BlendMode.modulate`), so one sprite serves every dot, every hue
/// and every alpha. The buffers are allocated once per count and rewritten in
/// place each frame: a frame allocates nothing.
///
/// ## One hue
///
/// The colour is the owner's accent and nothing else. Dark themes add the dots
/// to the ground (`BlendMode.plus`), so they glow where they overlap at the
/// rim, with a faint radial ring behind them. Light themes lay them over the
/// ground (`srcOver`) with no glow and no fill: additive light on a pale page is
/// white mush.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:healthee/core/theme/palette.dart';
import 'package:healthee/shared/v02/instruments/age_sphere_lattice.dart';

/// Edge of the square white sprite every dot is cut from, in image px.
const double kSpriteSize = 16;

/// Radius of the sprite's disc; the half pixel margin keeps filtering inside.
const double kSpriteRadius = 7.5;

/// The view is tilted this far about the X axis, in degrees.
const double kSphereTiltDegrees = 18;

/// One full turn about the sphere's own axis takes this long.
const Duration kSpherePeriod = Duration(seconds: 120);

/// The angle a still sphere (reduced motion, withheld) is drawn at, in radians.
const double kStillAngle = 0.6;

/// Every alpha is multiplied by this when the reading is withheld.
const double kWithheldAlpha = 0.35;

/// Radius of the glow ring, as a multiple of the sphere's radius.
const double kGlowRadius = 1.17;

/// Where the glow starts to rise, as a multiple of the sphere's radius.
const double kGlowInner = 0.80;

/// Where the glow peaks, as a multiple of the sphere's radius.
const double kGlowPeakAt = 0.97;

/// Alpha of the glow at its peak.
const double kGlowPeak = 0.10;

/// Floats in one RSTransform (scos, ssin, tx, ty) and in one source rect.
const int _kQuad = 4;

/// What one frame of the sphere is made of, reused in place.
///
/// Public so a test can read the colours and transforms the painter would draw
/// without a canvas.
class SphereFrame {
  /// Buffers for [count] dots. Source rects never change, so they are filled
  /// here once.
  SphereFrame(this.count)
    : transforms = Float32List(count * _kQuad),
      rects = Float32List(count * _kQuad),
      colors = Int32List(count) {
    for (int i = 0; i < count; i++) {
      rects[i * _kQuad + 2] = kSpriteSize;
      rects[i * _kQuad + 3] = kSpriteSize;
    }
  }

  /// Dots in the frame.
  final int count;

  /// One RSTransform per dot: scale, 0, x, y.
  final Float32List transforms;

  /// The same full-sprite source rect for every dot.
  final Float32List rects;

  /// ARGB of every dot: the accent, with that dot's alpha.
  final Int32List colors;

  /// The sphere seen at [angle] radians of spin.
  ///
  /// [center] and [radius] are in canvas px; [clearWidth] is the number's
  /// half-width over the radius; [alphaScale] multiplies every alpha (0.35 when
  /// withheld); [rgb] is the accent without its alpha.
  void fill(
    SphereLattice lattice, {
    required double angle,
    required Offset center,
    required double radius,
    required double clearWidth,
    required bool dark,
    required double alphaScale,
    required int rgb,
  }) {
    const double tilt = kSphereTiltDegrees * math.pi / 180;
    final double cosA = math.cos(angle), sinA = math.sin(angle);
    final double cosT = math.cos(tilt), sinT = math.sin(tilt);
    for (int i = 0; i < count; i++) {
      // Spin about the sphere's own axis, then tilt the whole view.
      final double sx = lattice.x[i] * cosA + lattice.z[i] * sinA;
      final double sz = -lattice.x[i] * sinA + lattice.z[i] * cosA;
      final double sy = lattice.y[i] * cosT - sz * sinT;
      final double depth = lattice.y[i] * sinT + sz * cosT;
      final double t = ((depth + 1) / 2).clamp(0.0, 1.0);
      final double rho = math.sqrt(sx * sx + sy * sy);
      final bool sparkle = lattice.sparkle[i] == 1;

      double alpha = sphereDotAlpha(t, rho, clearWidth, dark: dark);
      double size = sphereDotSize(t, dark: dark);
      if (sparkle) {
        alpha = math.min(1.0, alpha * kSparkleAlpha);
        size += kSparkleSize;
      }
      final int a = (alpha * alphaScale * 255).round().clamp(0, 255);
      colors[i] = (a << 24) | rgb;

      final double scale = size / kSpriteSize;
      final double half = scale * kSpriteSize / 2;
      transforms[i * _kQuad] = scale;
      transforms[i * _kQuad + 1] = 0;
      transforms[i * _kQuad + 2] = center.dx + sx * radius - half;
      transforms[i * _kQuad + 3] = center.dy - sy * radius - half;
    }
  }
}

/// Paints the sphere. Repaints only when [angle] notifies.
class AgeSpherePainter extends CustomPainter {
  /// [accent] is the owner's accent colour; [frame] the reusable buffers.
  AgeSpherePainter({
    required this.angle,
    required this.lattice,
    required this.frame,
    required this.accent,
    required this.dark,
    required this.clearWidth,
    required this.withheld,
  }) : super(repaint: angle);

  /// The current spin, in radians. The only thing that changes per frame.
  final ValueListenable<double> angle;

  /// The points.
  final SphereLattice lattice;

  /// Preallocated buffers, sized to [lattice].
  final SphereFrame frame;

  /// The one hue.
  final Color accent;

  /// Dark themes add light; light themes lay ink.
  final bool dark;

  /// The number's half-width over the radius, already clamped.
  final double clearWidth;

  /// A withheld reading is dimmed to [kWithheldAlpha].
  final bool withheld;

  /// How long the last paint took, in microseconds. Debug builds only; a device
  /// run reads it, since a frame time cannot be measured off a device.
  static int debugLastPaintMicros = 0;

  static ui.Image? _sprite;

  /// The white disc every dot is cut from, made once.
  static ui.Image get sprite => _sprite ??= _makeSprite();

  static ui.Image _makeSprite() {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    Canvas(recorder).drawCircle(
      const Offset(kSpriteSize / 2, kSpriteSize / 2),
      kSpriteRadius,
      Paint()
        ..color = MaskColors.white
        ..isAntiAlias = true,
    );
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = picture.toImageSync(
      kSpriteSize.toInt(),
      kSpriteSize.toInt(),
    );
    picture.dispose();
    return image;
  }

  Shader? _glow;
  Size _glowSize = Size.zero;

  @override
  void paint(Canvas canvas, Size size) {
    final Stopwatch? watch = kDebugMode ? (Stopwatch()..start()) : null;
    final Offset center = size.center(Offset.zero);
    final double radius = size.width * kSphereRadiusShare;
    final double scale = withheld ? kWithheldAlpha : 1.0;

    if (dark) {
      canvas.drawCircle(
        center,
        radius * kGlowRadius,
        Paint()..shader = _glowShader(size, center, radius, scale),
      );
    }
    frame.fill(
      lattice,
      angle: angle.value,
      center: center,
      radius: radius,
      clearWidth: clearWidth,
      dark: dark,
      alphaScale: scale,
      rgb: accent.toARGB32() & 0xFFFFFF,
    );
    canvas.drawRawAtlas(
      sprite,
      frame.transforms,
      frame.rects,
      frame.colors,
      BlendMode.modulate,
      null,
      Paint()
        ..blendMode = dark ? BlendMode.plus : BlendMode.srcOver
        ..filterQuality = FilterQuality.medium,
    );
    if (watch != null) debugLastPaintMicros = watch.elapsedMicroseconds;
  }

  /// The glow ring: clear to 0.80 R, a faint peak at 0.97 R, clear by 1.17 R.
  Shader _glowShader(Size size, Offset center, double radius, double scale) {
    if (_glow != null && _glowSize == size) return _glow!;
    final Color clear = accent.withValues(alpha: 0);
    _glowSize = size;
    return _glow = ui.Gradient.radial(
      center,
      radius * kGlowRadius,
      <Color>[clear, clear, accent.withValues(alpha: kGlowPeak * scale), clear],
      <double>[0, kGlowInner / kGlowRadius, kGlowPeakAt / kGlowRadius, 1],
    );
  }

  @override
  bool shouldRepaint(AgeSpherePainter old) =>
      old.angle != angle ||
      old.lattice != lattice ||
      old.frame != frame ||
      old.accent != accent ||
      old.dark != dark ||
      old.clearWidth != clearWidth ||
      old.withheld != withheld;
}
