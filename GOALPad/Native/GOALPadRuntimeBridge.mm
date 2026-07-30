#import "GOALPadRuntimeBridge.h"

#include "GOALPadRuntimeCore.hpp"

@interface GOALPadRuntimeStatus ()

@property(nonatomic, readwrite) NSString *architecture;
@property(nonatomic, readwrite) NSString *storagePath;
@property(nonatomic, readwrite) NSUInteger workloadResult;
@property(nonatomic, readwrite, getter=isWorkloadVerified) BOOL workloadVerified;
@property(nonatomic, readwrite) NSString *message;

@end

@implementation GOALPadRuntimeStatus
@end

@implementation GOALPadRuntimeBridge

+ (GOALPadRuntimeStatus *)initializeRuntime {
  NSError *error = nil;
  NSURL *applicationSupport =
      [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                             inDomain:NSUserDomainMask
                                    appropriateForURL:nil
                                               create:YES
                                                error:&error];
  NSURL *storageURL = [[applicationSupport URLByAppendingPathComponent:@"GOALPad"
                                                           isDirectory:YES]
      URLByAppendingPathComponent:@"Jak1" isDirectory:YES];

  if (error == nil) {
    [[NSFileManager defaultManager] createDirectoryAtURL:storageURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:&error];
  }

  std::string storagePath;
  if (error == nil) {
    storagePath = storageURL.fileSystemRepresentation;
  }

  goalpad::RuntimeStatus coreStatus = goalpad::initialize_runtime(std::move(storagePath));
  GOALPadRuntimeStatus *status = [[GOALPadRuntimeStatus alloc] init];
  status.architecture = [NSString stringWithUTF8String:coreStatus.architecture.c_str()];
  status.storagePath = [NSString stringWithUTF8String:coreStatus.storage_path.c_str()];
  status.workloadResult = coreStatus.workload_result;
  status.workloadVerified = coreStatus.workload_verified && error == nil;
  status.message =
      error == nil ? [NSString stringWithUTF8String:coreStatus.message.c_str()]
                   : error.localizedDescription;

  NSLog(@"GOALPad runtime probe: %@; architecture=%@; result=%lu", status.message,
        status.architecture, (unsigned long)status.workloadResult);
  return status;
}

@end
