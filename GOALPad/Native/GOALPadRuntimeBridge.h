#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One GOAL type read out of the live kernel heap.
@interface GOALPadKernelType : NSObject

@property(nonatomic, readonly) NSString *symbolName;
@property(nonatomic, readonly) NSString *typeName;
@property(nonatomic, readonly) NSString *parentName;
@property(nonatomic, readonly) uint32_t typeOffset;
@property(nonatomic, readonly) uint32_t allocatedSize;
@property(nonatomic, readonly) uint32_t methodCount;

@end

/// A snapshot of the GOAL kernel session. Every `*Offset` is a GOAL pointer: a byte offset from
/// `mainMemoryAddress`.
@interface GOALPadKernelStatus : NSObject

@property(nonatomic, readonly, getter=isRunning) BOOL running;
@property(nonatomic, readonly) NSString *message;
@property(nonatomic, readonly) NSString *architecture;
@property(nonatomic, readonly) NSString *storagePath;

@property(nonatomic, readonly) uint64_t mainMemoryAddress;
@property(nonatomic, readonly) uint32_t mainMemorySize;
@property(nonatomic, readonly, getter=isMainMemoryExecutable) BOOL mainMemoryExecutable;

@property(nonatomic, readonly) uint32_t globalHeapBaseOffset;
@property(nonatomic, readonly) uint32_t globalHeapCurrentOffset;
@property(nonatomic, readonly) uint32_t globalHeapTopBaseOffset;
@property(nonatomic, readonly) uint32_t globalHeapUsedBytes;
@property(nonatomic, readonly) uint32_t debugHeapBaseOffset;

@property(nonatomic, readonly) uint32_t symbolTableOffset;
@property(nonatomic, readonly) uint32_t s7Offset;
@property(nonatomic, readonly) uint32_t lastSymbolOffset;
@property(nonatomic, readonly) int32_t symbolCount;

@property(nonatomic, readonly) NSArray<GOALPadKernelType *> *types;

@end

/// The whole Swift-facing surface of the native runtime. The GOAL kernel is a process-wide
/// singleton, so this is a class API rather than an instantiable object.
@interface GOALPadRuntimeBridge : NSObject

/// Bring the kernel up. All-or-nothing: if the returned status is not `running`, nothing is live
/// and `message` says why.
+ (GOALPadKernelStatus *)startKernel;

/// Tear the kernel down. Safe to call when no session is live.
+ (void)stopKernel;

+ (BOOL)isKernelRunning;

@end

NS_ASSUME_NONNULL_END
