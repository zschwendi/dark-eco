#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const GOALPadGameDataPreparationErrorDomain;
FOUNDATION_EXPORT BOOL GOALPadGameDataPreparationIsAvailable(void);

typedef NS_ENUM(NSInteger, GOALPadGameDataPreparationErrorCode) {
  GOALPadGameDataPreparationErrorInvalidArgument = 1,
  GOALPadGameDataPreparationErrorCancelled = 2,
  GOALPadGameDataPreparationErrorCallbackFailed = 3,
  GOALPadGameDataPreparationErrorSourcePackFailed = 4,
  GOALPadGameDataPreparationErrorISOOpenFailed = 5,
  GOALPadGameDataPreparationErrorISOValidationFailed = 6,
  GOALPadGameDataPreparationErrorUnsupportedRevision = 7,
  GOALPadGameDataPreparationErrorGraphFailed = 8,
  GOALPadGameDataPreparationErrorRetailCatalogFailed = 9,
  GOALPadGameDataPreparationErrorGeneratedDataFailed = 10,
  GOALPadGameDataPreparationErrorFR3Failed = 11,
  GOALPadGameDataPreparationErrorRecipeFailed = 12,
  GOALPadGameDataPreparationErrorCandidateCreateFailed = 13,
  GOALPadGameDataPreparationErrorWorkWriteFailed = 14,
  GOALPadGameDataPreparationErrorInsufficientStorage = 15,
  GOALPadGameDataPreparationErrorMaterializationFailed = 16,
  GOALPadGameDataPreparationErrorCandidateFinalizeFailed = 17,
  GOALPadGameDataPreparationErrorCandidateCleanupFailed = 18,
  GOALPadGameDataPreparationErrorAllocationFailed = 19,
  GOALPadGameDataPreparationErrorUnexpectedFailure = 20,
  GOALPadGameDataPreparationErrorAlreadyStarted = 21,
};

typedef NS_ENUM(NSInteger, GOALPadGameDataPreparationPhase) {
  GOALPadGameDataPreparationPhaseValidatingSourcePack = 1,
  GOALPadGameDataPreparationPhaseExtractingISO = 2,
  GOALPadGameDataPreparationPhaseCatalogingRetail = 3,
  GOALPadGameDataPreparationPhaseGeneratingData = 4,
  GOALPadGameDataPreparationPhasePreparingFR3 = 5,
  GOALPadGameDataPreparationPhaseGeneratingRecipe = 6,
  GOALPadGameDataPreparationPhaseMaterializingOutput = 7,
  GOALPadGameDataPreparationPhaseFinalizingCandidate = 8,
};

@interface GOALPadGameDataPreparationProgress : NSObject

@property(nonatomic, readonly) GOALPadGameDataPreparationPhase phase;
@property(nonatomic, readonly) NSString *phaseLabel;
@property(nonatomic, readonly) uint64_t completed;
@property(nonatomic, readonly) uint64_t total;
@property(nonatomic, readonly) uint64_t bytesCompleted;
@property(nonatomic, readonly) NSString *currentItem;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end


@interface GOALPadGameDataPreparationSummary : NSObject

@property(nonatomic, readonly) uint32_t archivesWritten;
@property(nonatomic, readonly) uint32_t objectsWritten;
@property(nonatomic, readonly) uint32_t flatFilesWritten;
@property(nonatomic, readonly) uint32_t fr3FilesWritten;
@property(nonatomic, readonly) uint64_t outputBytes;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end


typedef void (^GOALPadGameDataPreparationProgressHandler)(
    GOALPadGameDataPreparationProgress *progress);
typedef void (^GOALPadGameDataPreparationCompletionHandler)(
    GOALPadGameDataPreparationSummary *_Nullable summary, NSError *_Nullable error);

/// A single-use, cancellable invocation of the native Jak 1 disc-image composer.
///
/// Work runs on a private serial utility queue. Cancellation is cooperative, and completion is
/// not delivered until the native composer has stopped touching every supplied URL.
@interface GOALPadGameDataPreparationJob : NSObject

- (instancetype)initWithSourceURL:(NSURL *)sourceURL
                     candidateURL:(NSURL *)candidateURL
               projectResourceURL:(NSURL *)projectResourceURL
              sourceObjectPackURL:(NSURL *)sourceObjectPackURL
    NS_SWIFT_NAME(init(sourceURL:candidateURL:projectResourceURL:sourceObjectPackURL:))
        NS_DESIGNATED_INITIALIZER;

- (void)startWithProgressHandler:(GOALPadGameDataPreparationProgressHandler)progressHandler
               completionHandler:(GOALPadGameDataPreparationCompletionHandler)completionHandler
    NS_SWIFT_NAME(start(progress:completion:));

- (void)cancel;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end


NS_ASSUME_NONNULL_END
