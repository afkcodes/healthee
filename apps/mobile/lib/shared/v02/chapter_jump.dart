/// A chapter jump on a lazily built screen: hop down until the heading is
/// built, then land it just below the pinned chapter nav. Shared by Today and
/// Sleep; it was `TodayChapters.jumpTo` before Sleep needed it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:healthee/shared/v02/chapter.dart';

/// How far one hop scrolls, as a share of the viewport.
const double kChapterHopFraction = 0.9;

/// How many hops before giving up. Twelve viewports is longer than any screen.
const int kChapterMaxHops = 12;

/// One hop, and the final landing.
const Duration kChapterStep = Duration(milliseconds: 180);

/// Scrolls until [key]'s heading is on screen, from [from]'s viewport.
Future<void> jumpToChapter(BuildContext from, GlobalKey key) async {
  for (var hop = 0; hop < kChapterMaxHops; hop++) {
    // The button can be scrolled out of the tree by its own animation, so
    // every hop after the first re-checks that the context is still live.
    if (!from.mounted) {
      return;
    }
    final anchor = key.currentContext;
    if (anchor != null) {
      await _landing(from, anchor);
      return;
    }
    final position = Scrollable.maybeOf(from)?.position;
    if (position == null || !position.hasContentDimensions) {
      return;
    }
    final next = math.min(
      position.pixels + position.viewportDimension * kChapterHopFraction,
      position.maxScrollExtent,
    );
    if (next <= position.pixels) {
      return;
    }
    await position.animateTo(
      next,
      duration: kChapterStep,
      curve: Curves.easeOut,
    );
  }
}

/// Scrolls so [anchor] sits just **below** the pinned nav rather than under
/// it. Falls back to `ensureVisible` when the geometry cannot be read, which
/// is the pre-pinning behaviour and still lands the heading on screen.
Future<void> _landing(BuildContext from, BuildContext anchor) async {
  final box = anchor.findRenderObject();
  final position = Scrollable.maybeOf(from)?.position;
  final viewport = box is RenderBox
      ? RenderAbstractViewport.maybeOf(box)
      : null;
  if (box is! RenderBox || position == null || viewport == null) {
    await Scrollable.ensureVisible(anchor, duration: kChapterStep);
    return;
  }
  final target =
      (viewport.getOffsetToReveal(box, 0).offset - ChapterNav.extentOf(from))
          .clamp(position.minScrollExtent, position.maxScrollExtent);
  await position.animateTo(
    target,
    duration: kChapterStep,
    curve: Curves.easeOut,
  );
}
