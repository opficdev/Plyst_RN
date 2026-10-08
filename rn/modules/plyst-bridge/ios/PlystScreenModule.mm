#import "PlystScreenModule.h"

#if __has_include("PlystBridge/PlystBridge-Swift.h")
#import "PlystBridge/PlystBridge-Swift.h"
#else
#import "PlystBridge-Swift.h"
#endif

@implementation PlystScreenModule {
  ScreenBridgeModuleImpl *_implementation;
}

RCT_EXPORT_MODULE(PlystScreen);

- (instancetype)init {
  self = [super init];
  if (self) {
    _implementation = [ScreenBridgeModuleImpl new];
  }
  return self;
}

+ (BOOL)requiresMainQueueSetup {
  return NO;
}

RCT_EXPORT_METHOD(close) {
  [_implementation close];
}

- (void)invalidate {
  [_implementation invalidate];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativePlystScreenSpecJSI>(params);
}

@end
