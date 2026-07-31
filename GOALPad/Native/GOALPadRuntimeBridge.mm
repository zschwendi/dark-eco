#import "GOALPadRuntimeBridge.h"

#include "GOALPadRuntimeCore.hpp"

#include <string>

@interface GOALPadKernelType ()
@property(nonatomic, readwrite) NSString *symbolName;
@property(nonatomic, readwrite) NSString *typeName;
@property(nonatomic, readwrite) NSString *parentName;
@property(nonatomic, readwrite) uint32_t typeOffset;
@property(nonatomic, readwrite) uint32_t allocatedSize;
@property(nonatomic, readwrite) uint32_t methodCount;
@end

@implementation GOALPadKernelType
@end

@interface GOALPadKernelStatus ()
@property(nonatomic, readwrite, getter=isRunning) BOOL running;
@property(nonatomic, readwrite) NSString *message;
@property(nonatomic, readwrite) NSString *architecture;
@property(nonatomic, readwrite) NSString *storagePath;
@property(nonatomic, readwrite) uint64_t mainMemoryAddress;
@property(nonatomic, readwrite) uint32_t mainMemorySize;
@property(nonatomic, readwrite, getter=isMainMemoryExecutable) BOOL mainMemoryExecutable;
@property(nonatomic, readwrite) uint32_t globalHeapBaseOffset;
@property(nonatomic, readwrite) uint32_t globalHeapCurrentOffset;
@property(nonatomic, readwrite) uint32_t globalHeapTopBaseOffset;
@property(nonatomic, readwrite) uint32_t globalHeapUsedBytes;
@property(nonatomic, readwrite) uint32_t debugHeapBaseOffset;
@property(nonatomic, readwrite) uint32_t symbolTableOffset;
@property(nonatomic, readwrite) uint32_t s7Offset;
@property(nonatomic, readwrite) uint32_t lastSymbolOffset;
@property(nonatomic, readwrite) int32_t symbolCount;
@property(nonatomic, readwrite) NSArray<GOALPadKernelType *> *types;
@end

@implementation GOALPadKernelStatus
@end

/// Kernel strings come out of the GOAL heap, so never hand Swift a nil for a nonnull property.
static NSString *GOALPadString(const std::string &value) {
  NSString *string = [NSString stringWithUTF8String:value.c_str()];
  return string ?: @"";
}

/// Where prepared, user-supplied game data will live. Created up front so a failure to prepare
/// application storage is reported instead of surfacing later as a mysterious load failure.
static NSString *GOALPadStoragePath(NSError **outError) {
  NSFileManager *manager = [NSFileManager defaultManager];
  NSURL *applicationSupport = [manager URLForDirectory:NSApplicationSupportDirectory
                                              inDomain:NSUserDomainMask
                                     appropriateForURL:nil
                                                create:YES
                                                 error:outError];
  if (applicationSupport == nil) {
    return nil;
  }
  NSURL *storageURL =
      [[applicationSupport URLByAppendingPathComponent:@"GOALPad" isDirectory:YES]
          URLByAppendingPathComponent:@"Jak1"
                          isDirectory:YES];
  if (![manager createDirectoryAtURL:storageURL
         withIntermediateDirectories:YES
                          attributes:nil
                               error:outError]) {
    return nil;
  }
  return @(storageURL.fileSystemRepresentation);
}

@implementation GOALPadRuntimeBridge

+ (GOALPadKernelStatus *)startKernel {
  NSError *error = nil;
  NSString *storagePath = GOALPadStoragePath(&error);
  if (storagePath == nil) {
    GOALPadKernelStatus *status = [[GOALPadKernelStatus alloc] init];
    status.running = NO;
    status.message = [NSString stringWithFormat:@"Application storage is unavailable: %@",
                                                error.localizedDescription ?: @"unknown error"];
    status.architecture = @"";
    status.storagePath = @"";
    status.types = @[];
    NSLog(@"GOALPad kernel: %@", status.message);
    return status;
  }

  // goalpad::start_kernel is noexcept and reports failure in its status, but the conversions
  // below allocate, so nothing C++ is allowed to escape into Objective-C either way.
  goalpad::KernelStatus core;
  try {
    core = goalpad::start_kernel(storagePath.UTF8String);
  } catch (...) {
    goalpad::stop_kernel();
    GOALPadKernelStatus *status = [[GOALPadKernelStatus alloc] init];
    status.running = NO;
    status.message = @"The native kernel bridge threw; no session is live.";
    status.architecture = @"";
    status.storagePath = storagePath;
    status.types = @[];
    NSLog(@"GOALPad kernel: %@", status.message);
    return status;
  }

  GOALPadKernelStatus *status = [[GOALPadKernelStatus alloc] init];
  status.running = core.running;
  status.message = GOALPadString(core.message);
  status.architecture = GOALPadString(core.architecture);
  status.storagePath = GOALPadString(core.storage_path);
  status.mainMemoryAddress = core.main_memory_address;
  status.mainMemorySize = core.main_memory_size;
  status.mainMemoryExecutable = core.main_memory_executable;
  status.globalHeapBaseOffset = core.global_heap_base;
  status.globalHeapCurrentOffset = core.global_heap_current;
  status.globalHeapTopBaseOffset = core.global_heap_top_base;
  status.globalHeapUsedBytes = core.global_heap_used_bytes;
  status.debugHeapBaseOffset = core.debug_heap_base;
  status.symbolTableOffset = core.symbol_table;
  status.s7Offset = core.s7;
  status.lastSymbolOffset = core.last_symbol;
  status.symbolCount = core.symbol_count;

  NSMutableArray<GOALPadKernelType *> *types =
      [NSMutableArray arrayWithCapacity:core.types.size()];
  for (const auto &coreType : core.types) {
    GOALPadKernelType *type = [[GOALPadKernelType alloc] init];
    type.symbolName = GOALPadString(coreType.symbol_name);
    type.typeName = GOALPadString(coreType.type_name);
    type.parentName = GOALPadString(coreType.parent_name);
    type.typeOffset = coreType.type_offset;
    type.allocatedSize = coreType.allocated_size;
    type.methodCount = coreType.method_count;
    [types addObject:type];
  }
  status.types = types;

  NSLog(@"GOALPad kernel: %@ (arch=%@, s7=#x%08x, symbols=%d, PROT_EXEC=%@)", status.message,
        status.architecture, status.s7Offset, status.symbolCount,
        status.isMainMemoryExecutable ? @"yes" : @"no");
  return status;
}

+ (void)stopKernel {
  goalpad::stop_kernel();
  NSLog(@"GOALPad kernel: shut down.");
}

+ (BOOL)isKernelRunning {
  return goalpad::kernel_is_running() ? YES : NO;
}

@end
