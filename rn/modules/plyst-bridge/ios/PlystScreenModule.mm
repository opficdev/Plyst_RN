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
    __weak PlystScreenModule *weakSelf = self;
    _implementation = [[ScreenBridgeModuleImpl alloc] initWithEmit:^{
      [weakSelf emitOnSave];
    }];
  }
  return self;
}

+ (BOOL)requiresMainQueueSetup {
  return NO;
}

RCT_EXPORT_METHOD(close) {
  [_implementation close];
}

RCT_EXPORT_METHOD(ready) {
  [_implementation ready];
}

RCT_EXPORT_METHOD(setSaveEnabled:(BOOL)isEnabled) {
  [_implementation setSaveEnabled:isEnabled];
}

- (void)invalidate {
  [_implementation invalidate];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativePlystScreenSpecJSI>(params);
}

@end
