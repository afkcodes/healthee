/// The sphere's points: where they sit, and how bright and large each is drawn.
///
/// Everything here is pure and deterministic, so the look can be tested without
/// a canvas. The painter (`age_sphere_painter.dart`) only feeds these numbers to
/// one `drawRawAtlas` call.
///
/// ## Why a Fibonacci lattice with jitter and a shell
///
/// A Fibonacci lattice is the most even spread of N points over a sphere that
/// costs no iteration: equal area per point, no poles, no rings. Exactly even
/// reads as a grid, so each coordinate is jittered a little and the point is
/// pushed into a thin shell (0.90 to 1.00 of the radius) so the ball has depth
/// rather than a skin. Seeded, so the same N is the same ball on every frame,
/// every launch and every device.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Seed of the one `Random` that jitters, shells and picks sparkles.
const int kSphereSeed = 7;

/// Golden angle in radians: the azimuth step between lattice points.
const double kGoldenAngle = 2.399963;

/// Largest jitter per coordinate, in unit-sphere radii, either direction.
const double kSphereJitter = 0.025;

/// Innermost shell factor: how far toward the centre a point may sit.
const double kShellInner = 0.90;

/// Outermost shell factor: points never sit beyond the sphere's radius.
const double kShellOuter = 1.00;

/// Share of points that sparkle (brighter and a little larger), chosen once.
const double kSparkleShare = 0.06;

/// Alpha multiplier of a sparkle point, before the cap at 1.
const double kSparkleAlpha = 1.35;

/// Extra diameter, in logical px, of a sparkle point.
const double kSparkleSize = 0.6;

/// Points per squared sphere radius (in logical px) in a dark theme.
const double kDotsPerRadiusSquared = 0.1;

/// Light themes draw this many times the dark count: ink on a pale ground needs
/// more points to carry the same density.
const double kLightDotFactor = 1.2;

/// Alpha floor of a back-most point, before the depth curve adds to it.
const double kAlphaBase = 0.10;

/// Alpha the depth curve adds at the front-most point.
const double kAlphaDepth = 0.80;

/// Exponent of the depth curve: back points stay faint for longer.
const double kAlphaDepthPower = 1.6;

/// Alpha share kept at the very centre, behind the number.
const double kClearFloor = 0.25;

/// Alpha share restored outside the clear zone (floor plus this is 1).
const double kClearRange = 0.75;

/// Where the clear zone starts to fill in, as a multiple of the number's
/// half-width over the radius.
const double kClearStart = 0.55;

/// Where the clear zone is fully filled in, as a multiple of the same.
const double kClearEnd = 1.3;

/// The clear zone never ends beyond this fraction of the radius.
const double kClearEndCap = 0.95;

/// Rim brightening starts here, as a fraction of the radius.
const double kRimStart = 0.78;

/// Rim brightening is complete here.
const double kRimEnd = 1.0;

/// Alpha multiplier away from the rim.
const double kRimFloor = 0.85;

/// Extra alpha multiplier at the rim.
const double kRimGain = 0.35;

/// Overall alpha multiplier in a dark theme.
const double kDarkAlpha = 0.85;

/// Overall alpha multiplier in a light theme.
const double kLightAlpha = 0.9;

/// Dot diameter at the back in a dark theme, in logical px.
const double kDarkSizeBack = 0.6;

/// Extra dot diameter at the front in a dark theme.
const double kDarkSizeFront = 1.5;

/// Dot diameter at the back in a light theme.
const double kLightSizeBack = 0.55;

/// Extra dot diameter at the front in a light theme.
const double kLightSizeFront = 1.15;

/// The smallest clear half-width the number may claim, as a radius fraction.
const double kMinClearWidth = 0.15;

/// The largest clear half-width the number may claim, as a radius fraction.
const double kMaxClearWidth = 0.7;

/// The clear half-width used when the hero passes none, as a radius fraction.
const double kDefaultClearWidth = 0.35;

/// `smoothstep`: 0 at [edge0], 1 at [edge1], an eased S between.
double smoothstep(double edge0, double edge1, double x) {
  final double s = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return s * s * (3 - 2 * s);
}

/// How many dots a sphere of [canvas] logical px draws.
///
/// The radius is 0.425 of the canvas; the rest is room for the glow. Light
/// themes draw 1.2 times the (already rounded) dark count.
int sphereDotCount(double canvas, {required bool dark}) {
  final double radius = canvas * kSphereRadiusShare;
  final int base = (kDotsPerRadiusSquared * radius * radius).round();
  return dark ? base : (base * kLightDotFactor).round();
}

/// Sphere radius as a share of the canvas.
const double kSphereRadiusShare = 0.425;

/// Dot diameter in logical px for a point at depth [t] (front 1, back 0).
double sphereDotSize(double t, {required bool dark}) => dark
    ? kDarkSizeBack + kDarkSizeFront * t
    : kLightSizeBack + kLightSizeFront * t;

/// A dot's alpha, 0 to 1, before the sparkle and withheld multipliers.
///
/// [t] is depth (front 1), [rho] the projected distance from the centre over
/// the radius, and [clearWidth] the number's half-width over the radius. The
/// three factors are depth (front is bright, back faint), the clear zone behind
/// the number, and a lift at the rim that gives the ball its edge.
double sphereDotAlpha(
  double t,
  double rho,
  double clearWidth, {
  required bool dark,
}) {
  final double depth =
      kAlphaBase + kAlphaDepth * math.pow(t, kAlphaDepthPower).toDouble();
  final double clear =
      kClearFloor +
      kClearRange *
          smoothstep(
            kClearStart * clearWidth,
            math.min(kClearEnd * clearWidth, kClearEndCap),
            rho,
          );
  final double rim = kRimFloor + kRimGain * smoothstep(kRimStart, kRimEnd, rho);
  final double tone = dark ? kDarkAlpha : kLightAlpha;
  return (depth * clear * rim * tone).clamp(0.0, 1.0);
}

/// The unit-ish points of one ball. Immutable once built; shared by every
/// sphere with the same count.
class SphereLattice {
  /// A fresh lattice of [count] points, bypassing the cache. For tests that
  /// prove a rebuild is identical; the app uses [forCount].
  SphereLattice.build(this.count)
    : x = Float32List(count),
      y = Float32List(count),
      z = Float32List(count),
      sparkle = Uint8List(count) {
    _build();
  }

  /// The lattice for [count] points, built once per count.
  static SphereLattice forCount(int count) =>
      _cache.putIfAbsent(count, () => SphereLattice.build(count));

  static final Map<int, SphereLattice> _cache = <int, SphereLattice>{};

  /// How many points.
  final int count;

  /// X, Y, Z of each point, as a fraction of the sphere's radius.
  final Float32List x, y, z;

  /// 1 for a sparkle point, else 0.
  final Uint8List sparkle;

  void _build() {
    final math.Random random = math.Random(kSphereSeed);
    for (int i = 0; i < count; i++) {
      final double py = 1 - 2 * (i + 0.5) / count;
      final double r = math.sqrt(1 - py * py);
      final double theta = i * kGoldenAngle;
      final double jx = r * math.cos(theta) + _jitter(random);
      final double jy = py + _jitter(random);
      final double jz = r * math.sin(theta) + _jitter(random);
      final double length = math.sqrt(jx * jx + jy * jy + jz * jz);
      final double shell =
          kShellInner + (kShellOuter - kShellInner) * random.nextDouble();
      x[i] = jx / length * shell;
      y[i] = jy / length * shell;
      z[i] = jz / length * shell;
    }
    // Exactly the share, never a Bernoulli draw: 6% of the points, no more.
    final int wanted = (count * kSparkleShare).round();
    int chosen = 0;
    while (chosen < wanted) {
      final int index = random.nextInt(count);
      if (sparkle[index] == 0) {
        sparkle[index] = 1;
        chosen++;
      }
    }
  }

  /// A uniform offset of up to [kSphereJitter] either way.
  static double _jitter(math.Random random) =>
      random.nextDouble() * 2 * kSphereJitter - kSphereJitter;
}
