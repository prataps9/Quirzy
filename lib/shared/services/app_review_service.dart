import 'package:in_app_review/in_app_review.dart';

/// Asks the user to rate Quirzy: the in-app Play review sheet when the
/// device supports it, otherwise the store listing.
class AppReviewService {
  const AppReviewService._();

  static Future<void> rate() async {
    final review = InAppReview.instance;
    if (await review.isAvailable()) {
      await review.requestReview();
    } else {
      await review.openStoreListing();
    }
  }
}
