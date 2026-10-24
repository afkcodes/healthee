/// `POST /api/coach/review`, held for the app session.
///
/// The first call in a review week writes the review (a model call, slow); the
/// server then serves the stored one. The call is made ONLY when the owner opens
/// the review, never on screen open, and the result is kept in
/// [coachReviewProvider] so reopening does not ask again.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/env.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/api/problem_message.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/coach/review_models.dart';

/// A failure with words the owner can read.
class ReviewFailure implements Exception {
  /// Builds a failure.
  const ReviewFailure(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'ReviewFailure($message)';
}

/// Asks the server for this week's review through the one account client.
class ReviewRepository {
  /// Reads through [api].
  const ReviewRepository(this.api);

  /// The account's client.
  final AccountApi api;

  /// Writes or reads this week's review. A 402 is a [CoachRefusal].
  Future<CoachReview> generate() async {
    try {
      return CoachReview.fromJson(
        await api.request(
          '/api/coach/review',
          method: 'POST',
          timeout: Env.pushTimeout,
        ),
      );
    } on DioException catch (error) {
      final refusal = CoachClient.refusalFrom(error);
      if (refusal != null) {
        throw refusal;
      }
      throw ReviewFailure(_sentence(error));
    }
  }

  static String _sentence(DioException error) {
    if (error.response?.statusCode == 503) {
      return 'The review is still being written. Try again in a moment.';
    }
    if (error.type == DioExceptionType.receiveTimeout) {
      return 'The review took too long to write. Try again; if it finished, '
          'it will be waiting.';
    }
    return apiProblem(error);
  }
}

/// The repository on the signed-in account.
final FutureProvider<ReviewRepository> reviewRepositoryProvider =
    FutureProvider<ReviewRepository>(
      (ref) async =>
          ReviewRepository(await ref.watch(accountApiProvider.future)),
    );

/// The review for this app session. Null data means nobody has opened it yet.
class CoachReviewNotifier extends AsyncNotifier<CoachReview?> {
  @override
  Future<CoachReview?> build() async => null;

  /// Asks once; a review already held, or one being written, is not asked again.
  Future<void> open() async {
    if (state.value != null || state.isLoading) {
      return;
    }
    await _load();
  }

  /// Asks again after a failure.
  Future<void> retry() => _load();

  /// Replaces the held job's slot after the owner changed it.
  void setSlot(String slot) {
    final held = state.value;
    if (held != null) {
      state = AsyncData<CoachReview?>(held.withSlot(slot));
    }
  }

  Future<void> _load() async {
    state = const AsyncLoading<CoachReview?>();
    try {
      final repository = await ref.read(reviewRepositoryProvider.future);
      final review = await repository.generate();
      if (ref.mounted) {
        state = AsyncData<CoachReview?>(review);
      }
    } on Object catch (error, stack) {
      AppLog.failure('coach', 'writing the weekly review', error, stack);
      if (ref.mounted) {
        state = AsyncError<CoachReview?>(error, stack);
      }
    }
  }
}

/// The held review.
final AsyncNotifierProvider<CoachReviewNotifier, CoachReview?>
coachReviewProvider = AsyncNotifierProvider<CoachReviewNotifier, CoachReview?>(
  CoachReviewNotifier.new,
);
