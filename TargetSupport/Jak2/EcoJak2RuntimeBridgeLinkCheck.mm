#import "GOALPadRuntimeBridge.h"

int main(void) {
  @autoreleasepool {
    return GOALPadRuntimeBridge.isGameCodeLinked ? 0 : 1;
  }
}
