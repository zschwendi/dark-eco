#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const GOALPadJak2GameDataPreparationErrorDomain;
FOUNDATION_EXPORT BOOL GOALPadJak2GameDataPreparationIsAvailable(void);

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
  GOALPadGameDataPreparationErrorProjectResourcesFailed = 22,
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
  GOALPadGameDataPreparationPhaseValidatingProjectResources = 9,
};

@interface GOALPadJak2GameDataPreparationProgress : NSObject
@property(nonatomic, readonly) GOALPadGameDataPreparationPhase phase;
@property(nonatomic, readonly) NSString *phaseLabel;
@property(nonatomic, readonly) uint64_t completed;
@property(nonatomic, readonly) uint64_t total;
@property(nonatomic, readonly) uint64_t bytesCompleted;
@property(nonatomic, readonly) NSString *currentItem;
@end

@interface GOALPadJak2GameDataPreparationSummary : NSObject
@property(nonatomic, readonly) uint32_t archivesWritten;
@property(nonatomic, readonly) uint32_t objectsWritten;
@property(nonatomic, readonly) uint32_t flatFilesWritten;
@property(nonatomic, readonly) uint32_t fr3FilesWritten;
@property(nonatomic, readonly) uint64_t outputBytes;
@end

typedef void (^GOALPadJak2GameDataPreparationProgressHandler)(
    GOALPadJak2GameDataPreparationProgress *progress);
typedef void (^GOALPadJak2GameDataPreparationCompletionHandler)(
    GOALPadJak2GameDataPreparationSummary *_Nullable summary, NSError *_Nullable error);

@interface GOALPadJak2GameDataPreparationJob : NSObject
- (instancetype)initWithSourceURL:(NSURL *)sourceURL
                     candidateURL:(NSURL *)candidateURL
               projectResourceURL:(NSURL *)projectResourceURL
              sourceObjectPackURL:(NSURL *)sourceObjectPackURL
    NS_SWIFT_NAME(init(sourceURL:candidateURL:projectResourceURL:sourceObjectPackURL:));
- (void)startWithProgressHandler:(GOALPadJak2GameDataPreparationProgressHandler)progressHandler
               completionHandler:(GOALPadJak2GameDataPreparationCompletionHandler)completionHandler
    NS_SWIFT_NAME(start(progress:completion:));
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
