#import "GOALPadGameDataPreparationBridge.h"

#include <atomic>
#include <exception>
#include <filesystem>
#include <mutex>
#include <new>
#include <string>

#ifndef GOALPAD_HAS_JAK1_IMPORT_COMPOSER
#define GOALPAD_HAS_JAK1_IMPORT_COMPOSER 0
#endif

#ifndef GOALPAD_HAS_JAK2_IMPORT_COMPOSER
#define GOALPAD_HAS_JAK2_IMPORT_COMPOSER 0
#endif

#if GOALPAD_HAS_JAK1_IMPORT_COMPOSER && GOALPAD_HAS_JAK2_IMPORT_COMPOSER
#error "GOALPad must select exactly one import composer"
#endif

#if GOALPAD_HAS_JAK1_IMPORT_COMPOSER
#include "decompiler/extractor/jak1_import_composer.h"
namespace GOALPadImportComposer = jak1_import_composer;
#elif GOALPAD_HAS_JAK2_IMPORT_COMPOSER
#include "decompiler/extractor/jak2_import_composer.h"
namespace GOALPadImportComposer = jak2_import_composer;
#endif

NSErrorDomain const GOALPadGameDataPreparationErrorDomain =
    @"com.zephyrstudiosllc.eco.GameDataPreparation";

BOOL GOALPadGameDataPreparationIsAvailable(void) {
#if GOALPAD_HAS_JAK1_IMPORT_COMPOSER || GOALPAD_HAS_JAK2_IMPORT_COMPOSER
  return YES;
#else
  return NO;
#endif
}

#if GOALPAD_HAS_JAK1_IMPORT_COMPOSER || GOALPAD_HAS_JAK2_IMPORT_COMPOSER
static NSString *GOALPadPreparationString(const std::string &value, NSString *fallback) {
  NSString *string = [[NSString alloc] initWithBytes:value.data()
                                             length:value.size()
                                           encoding:NSUTF8StringEncoding];
  return string ?: fallback;
}
#endif

static NSError *GOALPadPreparationError(GOALPadGameDataPreparationErrorCode code,
                                        NSString *message) {
  return [NSError errorWithDomain:GOALPadGameDataPreparationErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}

#if GOALPAD_HAS_JAK1_IMPORT_COMPOSER || GOALPAD_HAS_JAK2_IMPORT_COMPOSER
static GOALPadGameDataPreparationPhase GOALPadPreparationPhase(
    GOALPadImportComposer::Phase phase) {
  using Phase = GOALPadImportComposer::Phase;
  switch (phase) {
    case Phase::validating_source_pack:
      return GOALPadGameDataPreparationPhaseValidatingSourcePack;
#if GOALPAD_HAS_JAK2_IMPORT_COMPOSER
    case Phase::validating_project_resources:
      return GOALPadGameDataPreparationPhaseValidatingProjectResources;
#endif
    case Phase::extracting_iso:
      return GOALPadGameDataPreparationPhaseExtractingISO;
    case Phase::cataloging_retail:
      return GOALPadGameDataPreparationPhaseCatalogingRetail;
    case Phase::generating_data:
      return GOALPadGameDataPreparationPhaseGeneratingData;
    case Phase::preparing_fr3:
      return GOALPadGameDataPreparationPhasePreparingFR3;
    case Phase::generating_recipe:
      return GOALPadGameDataPreparationPhaseGeneratingRecipe;
    case Phase::materializing_output:
      return GOALPadGameDataPreparationPhaseMaterializingOutput;
    case Phase::finalizing_candidate:
      return GOALPadGameDataPreparationPhaseFinalizingCandidate;
  }
  return GOALPadGameDataPreparationPhaseValidatingSourcePack;
}

static GOALPadGameDataPreparationErrorCode GOALPadPreparationErrorCode(
    GOALPadImportComposer::ErrorCode code) {
  using ErrorCode = GOALPadImportComposer::ErrorCode;
  switch (code) {
    case ErrorCode::invalid_argument:
      return GOALPadGameDataPreparationErrorInvalidArgument;
    case ErrorCode::cancelled:
      return GOALPadGameDataPreparationErrorCancelled;
    case ErrorCode::callback_failed:
      return GOALPadGameDataPreparationErrorCallbackFailed;
    case ErrorCode::source_pack_failed:
      return GOALPadGameDataPreparationErrorSourcePackFailed;
#if GOALPAD_HAS_JAK2_IMPORT_COMPOSER
    case ErrorCode::project_resources_failed:
      return GOALPadGameDataPreparationErrorProjectResourcesFailed;
#endif
    case ErrorCode::iso_open_failed:
      return GOALPadGameDataPreparationErrorISOOpenFailed;
    case ErrorCode::iso_validation_failed:
      return GOALPadGameDataPreparationErrorISOValidationFailed;
    case ErrorCode::unsupported_revision:
      return GOALPadGameDataPreparationErrorUnsupportedRevision;
    case ErrorCode::graph_failed:
      return GOALPadGameDataPreparationErrorGraphFailed;
    case ErrorCode::retail_catalog_failed:
      return GOALPadGameDataPreparationErrorRetailCatalogFailed;
    case ErrorCode::generated_data_failed:
      return GOALPadGameDataPreparationErrorGeneratedDataFailed;
    case ErrorCode::fr3_failed:
      return GOALPadGameDataPreparationErrorFR3Failed;
    case ErrorCode::recipe_failed:
      return GOALPadGameDataPreparationErrorRecipeFailed;
    case ErrorCode::candidate_create_failed:
      return GOALPadGameDataPreparationErrorCandidateCreateFailed;
    case ErrorCode::work_write_failed:
      return GOALPadGameDataPreparationErrorWorkWriteFailed;
    case ErrorCode::insufficient_storage:
      return GOALPadGameDataPreparationErrorInsufficientStorage;
    case ErrorCode::materialization_failed:
      return GOALPadGameDataPreparationErrorMaterializationFailed;
    case ErrorCode::candidate_finalize_failed:
      return GOALPadGameDataPreparationErrorCandidateFinalizeFailed;
    case ErrorCode::candidate_cleanup_failed:
      return GOALPadGameDataPreparationErrorCandidateCleanupFailed;
    case ErrorCode::allocation_failed:
      return GOALPadGameDataPreparationErrorAllocationFailed;
    case ErrorCode::unexpected_failure:
      return GOALPadGameDataPreparationErrorUnexpectedFailure;
  }
  return GOALPadGameDataPreparationErrorUnexpectedFailure;
}
#endif

static NSString *GOALPadPreparationPhaseLabel(GOALPadGameDataPreparationPhase phase) {
  switch (phase) {
    case GOALPadGameDataPreparationPhaseValidatingSourcePack:
      return @"Verifying preparation resources";
    case GOALPadGameDataPreparationPhaseValidatingProjectResources:
      return @"Verifying project resources";
    case GOALPadGameDataPreparationPhaseExtractingISO:
      return @"Reading disc image";
    case GOALPadGameDataPreparationPhaseCatalogingRetail:
      return @"Cataloging game data";
    case GOALPadGameDataPreparationPhaseGeneratingData:
      return @"Generating prepared data";
    case GOALPadGameDataPreparationPhasePreparingFR3:
      return @"Preparing level data";
    case GOALPadGameDataPreparationPhaseGeneratingRecipe:
      return @"Planning final output";
    case GOALPadGameDataPreparationPhaseMaterializingOutput:
      return @"Writing final output";
    case GOALPadGameDataPreparationPhaseFinalizingCandidate:
      return @"Finalizing candidate";
  }
  return @"Preparing game data";
}

@interface GOALPadGameDataPreparationProgress ()
@property(nonatomic, readwrite) GOALPadGameDataPreparationPhase phase;
@property(nonatomic, readwrite) uint64_t completed;
@property(nonatomic, readwrite) uint64_t total;
@property(nonatomic, readwrite) uint64_t bytesCompleted;
@property(nonatomic, readwrite) NSString *currentItem;
- (instancetype)initWithPhase:(GOALPadGameDataPreparationPhase)phase
                     completed:(uint64_t)completed
                         total:(uint64_t)total
                bytesCompleted:(uint64_t)bytesCompleted
                   currentItem:(NSString *)currentItem;
@end

@implementation GOALPadGameDataPreparationProgress

- (instancetype)initWithPhase:(GOALPadGameDataPreparationPhase)phase
                     completed:(uint64_t)completed
                         total:(uint64_t)total
                bytesCompleted:(uint64_t)bytesCompleted
                   currentItem:(NSString *)currentItem {
  self = [super init];
  if (self) {
    _phase = phase;
    _completed = completed;
    _total = total;
    _bytesCompleted = bytesCompleted;
    _currentItem = [currentItem copy];
  }
  return self;
}

- (NSString *)phaseLabel {
  return GOALPadPreparationPhaseLabel(self.phase);
}

@end


@interface GOALPadGameDataPreparationSummary ()
@property(nonatomic, readwrite) uint32_t archivesWritten;
@property(nonatomic, readwrite) uint32_t objectsWritten;
@property(nonatomic, readwrite) uint32_t flatFilesWritten;
@property(nonatomic, readwrite) uint32_t fr3FilesWritten;
@property(nonatomic, readwrite) uint64_t outputBytes;
- (instancetype)initWithArchivesWritten:(uint32_t)archivesWritten
                         objectsWritten:(uint32_t)objectsWritten
                       flatFilesWritten:(uint32_t)flatFilesWritten
                        fr3FilesWritten:(uint32_t)fr3FilesWritten
                            outputBytes:(uint64_t)outputBytes;
@end

@implementation GOALPadGameDataPreparationSummary

- (instancetype)initWithArchivesWritten:(uint32_t)archivesWritten
                         objectsWritten:(uint32_t)objectsWritten
                       flatFilesWritten:(uint32_t)flatFilesWritten
                        fr3FilesWritten:(uint32_t)fr3FilesWritten
                            outputBytes:(uint64_t)outputBytes {
  self = [super init];
  if (self) {
    _archivesWritten = archivesWritten;
    _objectsWritten = objectsWritten;
    _flatFilesWritten = flatFilesWritten;
    _fr3FilesWritten = fr3FilesWritten;
    _outputBytes = outputBytes;
  }
  return self;
}

@end


@interface GOALPadGameDataPreparationJob ()
- (void)runWithProgressHandler:(GOALPadGameDataPreparationProgressHandler)progressHandler
             completionHandler:(GOALPadGameDataPreparationCompletionHandler)completionHandler;
@end

@implementation GOALPadGameDataPreparationJob {
  NSURL *_sourceURL;
  NSURL *_candidateURL;
  NSURL *_projectResourceURL;
  NSURL *_sourceObjectPackURL;
  dispatch_queue_t _workQueue;
  std::atomic_bool _cancelRequested;
  std::mutex _startMutex;
  bool _started;
}

- (instancetype)initWithSourceURL:(NSURL *)sourceURL
                     candidateURL:(NSURL *)candidateURL
               projectResourceURL:(NSURL *)projectResourceURL
              sourceObjectPackURL:(NSURL *)sourceObjectPackURL {
  self = [super init];
  if (self) {
    _sourceURL = [sourceURL copy];
    _candidateURL = [candidateURL copy];
    _projectResourceURL = [projectResourceURL copy];
    _sourceObjectPackURL = [sourceObjectPackURL copy];
    dispatch_queue_attr_t attributes = dispatch_queue_attr_make_with_qos_class(
        DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL, QOS_CLASS_UTILITY, 0);
    _workQueue = dispatch_queue_create("com.zephyrstudiosllc.eco.game-data-preparation",
                                       attributes);
    _cancelRequested.store(false, std::memory_order_relaxed);
    _started = false;
  }
  return self;
}

- (void)startWithProgressHandler:(GOALPadGameDataPreparationProgressHandler)progressHandler
               completionHandler:(GOALPadGameDataPreparationCompletionHandler)completionHandler {
  bool alreadyStarted = false;
  {
    std::lock_guard<std::mutex> lock(_startMutex);
    if (_started) {
      alreadyStarted = true;
    } else {
      _started = true;
    }
  }
  if (alreadyStarted) {
    completionHandler(nil, GOALPadPreparationError(
                                 GOALPadGameDataPreparationErrorAlreadyStarted,
                                 @"This preparation job has already been started."));
    return;
  }

  GOALPadGameDataPreparationProgressHandler progress = [progressHandler copy];
  GOALPadGameDataPreparationCompletionHandler completion = [completionHandler copy];
  dispatch_async(_workQueue, ^{
    [self runWithProgressHandler:progress completionHandler:completion];
  });
}

- (void)cancel {
  _cancelRequested.store(true, std::memory_order_relaxed);
}

- (void)runWithProgressHandler:(GOALPadGameDataPreparationProgressHandler)progressHandler
             completionHandler:(GOALPadGameDataPreparationCompletionHandler)completionHandler {
  for (NSURL *URL in @[_sourceURL, _candidateURL, _projectResourceURL, _sourceObjectPackURL]) {
    if (!URL.isFileURL || URL.fileSystemRepresentation == nullptr) {
      completionHandler(nil, GOALPadPreparationError(
                                   GOALPadGameDataPreparationErrorInvalidArgument,
                                   @"Native preparation requires local file URLs."));
      return;
    }
  }

#if GOALPAD_HAS_JAK1_IMPORT_COMPOSER || GOALPAD_HAS_JAK2_IMPORT_COMPOSER
  try {
    const GOALPadImportComposer::Request request{
        std::filesystem::path(_sourceURL.fileSystemRepresentation),
        std::filesystem::path(_sourceObjectPackURL.fileSystemRepresentation),
        std::filesystem::path(_projectResourceURL.fileSystemRepresentation),
        std::filesystem::path(_candidateURL.fileSystemRepresentation),
    };
    GOALPadImportComposer::Options options;
    options.should_cancel = [self]() {
      return self->_cancelRequested.load(std::memory_order_relaxed);
    };
    options.on_progress = [progressHandler](const GOALPadImportComposer::Progress &progress) {
      @autoreleasepool {
        const GOALPadGameDataPreparationPhase phase = GOALPadPreparationPhase(progress.phase);
        NSString *currentItem = GOALPadPreparationString(progress.current_item, @"");
        GOALPadGameDataPreparationProgress *value =
            [[GOALPadGameDataPreparationProgress alloc] initWithPhase:phase
                                                            completed:progress.completed
                                                                total:progress.total
                                                       bytesCompleted:progress.bytes_completed
                                                          currentItem:currentItem];
        progressHandler(value);
      }
    };

    auto result = GOALPadImportComposer::compose(request, options);
    if (!result) {
      const auto &error = result.error();
      NSString *message = GOALPadPreparationString(error.message,
                                                   @"Native game-data preparation failed.");
      if (error.cleanup_error && !error.cleanup_error->empty()) {
        NSString *cleanup = GOALPadPreparationString(*error.cleanup_error,
                                                     @"Candidate cleanup also failed.");
        message = [message stringByAppendingFormat:@" %@", cleanup];
      }
      completionHandler(nil,
                        GOALPadPreparationError(GOALPadPreparationErrorCode(error.code), message));
      return;
    }

    const auto summary = result.take_value();
    GOALPadGameDataPreparationSummary *value =
        [[GOALPadGameDataPreparationSummary alloc]
            initWithArchivesWritten:summary.archives_written
                     objectsWritten:summary.objects_written
                   flatFilesWritten:summary.flat_files_written
                    fr3FilesWritten:summary.fr3_files_written
                        outputBytes:summary.output_bytes];
    completionHandler(value, nil);
  } catch (const std::bad_alloc &) {
    completionHandler(nil, GOALPadPreparationError(
                                 GOALPadGameDataPreparationErrorAllocationFailed,
                                 @"Native preparation ran out of memory."));
  } catch (const std::exception &exception) {
    NSString *message = GOALPadPreparationString(exception.what(),
                                                 @"Native game-data preparation failed.");
    completionHandler(nil, GOALPadPreparationError(
                                 GOALPadGameDataPreparationErrorUnexpectedFailure, message));
  } catch (...) {
    completionHandler(nil, GOALPadPreparationError(
                                 GOALPadGameDataPreparationErrorUnexpectedFailure,
                                 @"Native game-data preparation failed unexpectedly."));
  }
#else
  completionHandler(nil,
                    GOALPadPreparationError(
                        GOALPadGameDataPreparationErrorUnexpectedFailure,
                        @"This build does not link the native disc-image preparation pipeline."));
#endif
}

@end
