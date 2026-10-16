#import <Foundation/Foundation.h>
#import <Sentry/Sentry.h>
#import <Sentry/Sentry-Swift.h>

NS_ASSUME_NONNULL_BEGIN

void HadithlyInstallSentryPrivacyFilter(
    SentryOptions *options,
    SentryEvent *_Nullable (^filter)(SentryEvent *event, SentryHint *hint)
) NS_SWIFT_NAME(installSentryPrivacyFilter(options:filter:));

NS_ASSUME_NONNULL_END
