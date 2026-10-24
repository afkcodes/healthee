/// The two calls the coach surface makes, and the named failures they can have.
///
/// `POST /api/coach` costs one of the owner's twenty included questions per
/// rolling thirty days (`PRICING.md` §0), and `GET /api/entitlement` is how many
/// are left. They are in one file because they are one transaction from the
/// owner's point of view: the meter is read before the question is asked and again
/// after it is answered, and a surface that could do one without the other is the
/// silent spend this feature is not allowed to have.
///
/// ## Why the meter is re-read rather than decremented
///
/// The server refunds the question on a refusal, on an unvalidated answer, and on
/// a transport failure (`routers/coach.py`). A client that subtracted one locally
/// would be wrong in all three cases and would be wrong in the *flattering*
/// direction — showing fewer questions than the owner has. Re-reading is one cheap
/// ungated call and it is the number the gate itself will enforce.
///
/// ## 402 is an answer, not a crash
///
/// The gate refuses with `402` and a body carrying `limit`, `used`, `resets_at`
/// and `retry_after_s`. That is the same information `/api/entitlement.included`
/// carries, so it is parsed into the same [CoachRefusal] shape rather than shown
/// as an HTTP status — a `DioException` type is never rendered to anybody
/// (`data/api/signin_failure.dart` sets the precedent).
library;

import 'package:dio/dio.dart';
import 'package:healthee/core/env.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/data/api/api_client.dart';
import 'package:healthee/data/coach/coach_answer.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';
import 'package:healthee/data/coach/coach_stream_reader.dart';
import 'package:healthee/data/models/entitlement.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'coach_client.g.dart';

/// The gate refused: the window is spent, or the feature is not included.
@immutable
class CoachRefusal implements Exception {
  /// [resetsAt] is null when the refusal is a hard lock rather than a full window.
  const CoachRefusal({required this.message, this.resetsAt});

  /// What to tell the owner, in this app's own words.
  final String message;

  /// When the window reopens, when the server said.
  final DateTime? resetsAt;

  @override
  String toString() => 'CoachRefusal($message)';
}

/// What this app can honestly say about the meter after a failure.
///
/// Two values, not three, because there is no third thing the client can know.
/// The server charges the slot inside the gate *before* the handler starts, and
/// it refunds inside the handler — so once a request has left the phone, whether
/// it cost one of the owner's twenty is a fact only the server holds.
///
/// This replaced a `bool spent`. That flag could express the true statement and
/// the false one but not the honest one, and it was worse than that: `spent:
/// true` was **never constructed anywhere in the app**, so the "we could not say
/// it wasn't" case its own docstring described was a value the code could not
/// produce. Every failure therefore printed *"Nothing was counted for this"* —
/// including a receive timeout on an answer the server had already delivered and
/// charged for, directly above a meter showing one fewer.
enum CoachCharge {
  /// The request provably never reached the point where a slot is charged.
  notCharged,

  /// It left the phone and we did not see the outcome. It may have been counted.
  unknown,
}

/// The request did not complete. Ours or the network's, never the owner's.
@immutable
class CoachUnreachable implements Exception {
  /// [message] is already owner-facing. [charge] is what we may claim about the meter.
  const CoachUnreachable(this.message, this.charge);

  /// The sentence to show, with no status code and no exception type in it.
  final String message;

  /// Whether this app is entitled to say nothing was counted.
  final CoachCharge charge;

  @override
  String toString() => 'CoachUnreachable($message)';
}

/// Asks the coach, and reads the meter.
class CoachClient {
  /// [dio] is the app's one authenticated client.
  const CoachClient(this._dio);

  final Dio _dio;

  /// What this owner is entitled to right now. Ungated, uncached, cheap.
  Future<Entitlement> entitlement() async {
    try {
      final response = await _dio.get<Map<String, Object?>>('/api/entitlement');
      final body = response.data;
      if (body == null) {
        throw const CoachUnreachable(
          'Your server answered the entitlement check with nothing at all.',
          // Reading the meter never spends: `/api/entitlement` peeks.
          CoachCharge.notCharged,
        );
      }
      return Entitlement.fromJson(body);
    } on DioException catch (error, stackTrace) {
      AppLog.failure('coach', 'reading /api/entitlement', error, stackTrace);
      throw CoachUnreachable(
        _unreachableSentence(error),
        CoachCharge.notCharged,
      );
    }
  }

  /// Asks one question over [messages] — the whole conversation so far.
  ///
  /// **This is the call that spends a question.** Every caller must have shown the
  /// meter first; `features/coach/coach_controller.dart` is the only caller and
  /// its sheet cannot render an input without one.
  ///
  /// [topic] is which screen the coach was opened from, when it was opened about
  /// something. It is sent so the server can rank its context and its evidence on
  /// the subject rather than inferring it from prose; it is not a claim, and
  /// `insights/coach_thread.py` screens and fences it as one that is not.
  ///
  /// ## Why this call carries its own timeout
  ///
  /// The app's client defaults to [Env.requestTimeout] — ten seconds, which
  /// `core/env.dart` derives from a *read* budget of p95 < 100 ms. This endpoint
  /// runs a model, and up to 22 of them: `insights/coach.py`'s gathering
  /// allowance plus the pipeline's reserved answer attempts, each bounded at the
  /// server's own 60 s. It was the only generating call in the app left on the
  /// read default — the insight GETs, `/api/notable` and challenge/program
  /// generation all override — and the failure was not a spinner: **the gate
  /// charges the slot before the handler starts**, so the socket closing at ten
  /// seconds left the server producing an answer, charging for it, matching no
  /// refund branch, and delivering it to nobody.
  Future<CoachAnswer> ask(List<CoachTurn> messages, {String? topic}) async {
    final subject = topic?.trim() ?? '';
    try {
      final response = await _dio.post<Map<String, Object?>>(
        '/api/coach',
        data: <String, Object?>{
          'messages': [for (final turn in messages) turn.toJson()],
          if (subject.isNotEmpty) 'topic': subject,
        },
        options: Options(
          receiveTimeout: Env.coachTimeout,
          sendTimeout: Env.coachTimeout,
        ),
      );
      final body = response.data;
      if (body == null) {
        throw const CoachUnreachable(
          'Your server accepted the question and sent no answer back.',
          // It accepted it, so the gate ran. We cannot say it was not counted.
          CoachCharge.unknown,
        );
      }
      return CoachAnswer.fromJson(body);
    } on DioException catch (error, stackTrace) {
      AppLog.failure('coach', 'asking /api/coach', error, stackTrace);
      final refusal = refusalFrom(error);
      if (refusal != null) {
        throw refusal;
      }
      throw CoachUnreachable(_unreachableSentence(error), _chargeFrom(error));
    }
  }

  /// [ask], as Server-Sent Events: live stage progress, then the validated
  /// answer exactly once — the streaming twin `docs/INTELLIGENCE.md`'s
  /// choke point is growing, on the same wire contract `ask` already uses.
  ///
  /// The same [Env.coachTimeout] applies, on the same Dio instance, so a
  /// stream call cannot skip the auth interceptor or the timeout budget the
  /// non-streaming call gets for free.
  ///
  /// ## A 404/405 falls back to [ask]
  ///
  /// An older server has no streaming twin yet. That is not a failure this
  /// app surfaces — it calls [ask] and emits its answer as the one event, so
  /// code written against this stream works unchanged against that server.
  /// Every OTHER pre-stream status (402, 401, 422, 429, a dead socket) reuses
  /// [refusalFrom], [_chargeFrom] and [_unreachableSentence] exactly as
  /// [ask] does: one mapping from a status to this app's own exceptions, not
  /// two that could drift apart.
  ///
  /// ## Why a pre-stream failure needs [materializeStreamError]
  ///
  /// This request's `responseType` is [ResponseType.stream] so the SUCCESS
  /// body can be read as it arrives. Dio applies that to failures too: a 402
  /// here arrives as raw, undecoded bytes, not the parsed map [ask] gets for
  /// free from the JSON transformer. [materializeStreamError] reads those
  /// bytes once and decodes them into that same shape, so the mapping below
  /// runs unchanged instead of gaining a second body format to understand.
  ///
  /// The byte-reading half — the SSE parse loop, the "dropped mid-turn" case,
  /// and a stream `error` event's own exception — lives in
  /// `coach_stream_reader.dart`, split out at the 400-line gate (Standards §1).
  Stream<CoachStreamEvent> askStream(
    List<CoachTurn> messages, {
    String? topic,
  }) async* {
    final subject = topic?.trim() ?? '';
    final Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        '/api/coach/stream',
        data: <String, Object?>{
          'messages': [for (final turn in messages) turn.toJson()],
          if (subject.isNotEmpty) 'topic': subject,
        },
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: Env.coachTimeout,
          sendTimeout: Env.coachTimeout,
        ),
      );
    } on DioException catch (error, stackTrace) {
      final status = error.response?.statusCode;
      if (status == 404 || status == 405) {
        yield CoachAnswerEvent(await ask(messages, topic: topic));
        return;
      }
      AppLog.failure('coach', 'asking /api/coach/stream', error, stackTrace);
      await materializeStreamError(error);
      final refusal = refusalFrom(error);
      if (refusal != null) {
        throw refusal;
      }
      throw CoachUnreachable(_unreachableSentence(error), _chargeFrom(error));
    }

    final body = response.data;
    if (body == null) {
      throw const CoachUnreachable(
        'Your server accepted the question and sent no answer back.',
        CoachCharge.unknown,
      );
    }
    yield* readCoachStream(body.stream);
  }

  /// What may be claimed about the meter after [error] on the ASK.
  ///
  /// `notCharged` is a positive assertion about the owner's money, so it is made
  /// only where the request demonstrably never reached the gate: the connection
  /// was never established, the certificate was rejected, or the server answered
  /// 401/403 from the auth dependency that runs before the gate.
  ///
  /// **Everything else is `unknown`, including a receive timeout**, which is the
  /// case this whole taxonomy exists for: the request arrived, the gate charged
  /// it, and the answer went to a socket nobody was reading. Saying "nothing was
  /// spent" there is the product denying a charge it made.
  static CoachCharge _chargeFrom(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return CoachCharge.notCharged;
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.connectionError ||
      DioExceptionType.badCertificate => CoachCharge.notCharged,
      _ => CoachCharge.unknown,
    };
  }

  /// The gate's 402 body, as this app's own refusal. Null for anything else.
  /// Also read by the review repository: one parser for the gate's 402.
  static CoachRefusal? refusalFrom(DioException error) {
    if (error.response?.statusCode != 402) {
      return null;
    }
    final detail = switch (error.response?.data) {
      final Map<String, Object?> body => switch (body['detail']) {
        final Map<String, Object?> inner => inner,
        _ => body,
      },
      _ => const <String, Object?>{},
    };
    final resetsAt = switch (detail['resets_at']) {
      final String at => DateTime.tryParse(at),
      _ => null,
    };
    final limit = (detail['limit'] as num?)?.toInt();
    return CoachRefusal(
      message: limit == null
          ? 'Your server says the coach is not included on this account.'
          : 'You have used all $limit coach questions in this window.',
      resetsAt: resetsAt,
    );
  }

  /// One sentence, in the owner's terms, for a request that did not complete.
  ///
  /// The status is deliberately not shown. A 401 and a dead socket need different
  /// words because they need different actions, and everything else is one
  /// sentence — which is the taxonomy `signin_failure.dart` already argues for.
  ///
  /// The **timeout** sentence is separate from the dead-socket one for the reason
  /// [CoachCharge] exists: a request that never left says one true thing about
  /// the owner's questions, and a request that timed out waiting for an answer
  /// says a different one. Merging them is how "nothing was spent" ended up
  /// printed over a charge.
  static String _unreachableSentence(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return 'Your server refused the sign-in this phone holds. Sign in again '
          'from Settings and the coach will work.';
    }
    if (_chargeFrom(error) == CoachCharge.unknown) {
      return 'Your server did not finish answering in time. It may still be '
          'working on this, and the question may already have been asked.';
    }
    return "Couldn't reach your server. Nothing was asked and nothing was "
        'spent — your questions are untouched.';
  }
}

/// One turn of the conversation, as the router's `CoachMessage` expects it.
@immutable
class CoachTurn {
  /// [role] is `user` or `assistant`; system turns are ignored server-side.
  const CoachTurn({required this.role, required this.content});

  /// Who said it.
  final String role;

  /// What they said.
  final String content;

  /// The wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'role': role,
    'content': content,
  };

  /// Whether this turn came from the owner.
  bool get isOwner => role == 'user';
}

/// The app's [CoachClient].
@Riverpod(keepAlive: true)
CoachClient coachClient(Ref ref) => CoachClient(ref.watch(apiClientProvider));

/// What the owner is entitled to, re-read on demand.
///
/// Not `keepAlive`: the whole point of the endpoint being uncached server-side is
/// that a balance is only true at the moment it was read, and a provider that held
/// one across the life of the app would put a stale meter in front of a spend.
@riverpod
Future<Entitlement> coachEntitlement(Ref ref) =>
    ref.watch(coachClientProvider).entitlement();
