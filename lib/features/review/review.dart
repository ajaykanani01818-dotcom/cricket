/// In-app review: system review API under eligibility rules, plus the
/// Settings "Rate Cric Ticker" store link. No custom rating dialog.
library;

export 'review_controller.dart'
    show
        ReviewController,
        ReviewScope,
        defaultOpenStoreListing,
        defaultRequestReview,
        storeListingUri;
export 'review_host.dart' show ReviewHost;
export 'review_storage.dart' show ReviewStore, ReviewRules, canAskForReview;
