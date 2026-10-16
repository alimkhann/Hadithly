#import "SentryHintCompatibility.h"

void HadithlyInstallSentryPrivacyFilter(
    SentryOptions *options,
    SentryEvent *_Nullable (^filter)(SentryEvent *event, SentryHint *hint)
) {
    // Sentry 9 documents this transitional hook as the only attachment filter.
    // Remove this adapter when beforeSend gains its Hint parameter. Keep the
    // exception on this setter only; all other deprecation diagnostics stay on.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    options.beforeSendWithHint = filter;
#pragma clang diagnostic pop
}
