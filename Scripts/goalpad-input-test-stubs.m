#include "../GOALPad/Native/GOALPadRuntimeBridge.h"

void GOALPadInputSetState(int32_t port, GOALPadControllerState state) {
  (void)port;
  (void)state;
}

void GOALPadInputSetDisconnected(int32_t port) {
  (void)port;
}

GOALPadRumble GOALPadInputRumble(int32_t port) {
  (void)port;
  return (GOALPadRumble){0, 0};
}
