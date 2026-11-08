#import "PlystHomeModule.h"

#if __has_include("PlystBridge/PlystBridge-Swift.h")
#import "PlystBridge/PlystBridge-Swift.h"
#else
#import "PlystBridge-Swift.h"
#endif

@implementation PlystHomeModule {
  HomeBridgeModuleImpl *_implementation;
}

RCT_EXPORT_MODULE(PlystHome);

- (instancetype)init {
  self = [super init];
  if (self) {
    __weak PlystHomeModule *weakSelf = self;
    _implementation = [[HomeBridgeModuleImpl alloc] initWithRequestSave:^{
      [weakSelf emitOnClipboardSaveRequest];
    }];
  }
  return self;
}

+ (BOOL)requiresMainQueueSetup {
  return NO;
}

RCT_EXPORT_METHOD(ready) {
  [_implementation ready];
}

RCT_EXPORT_SYNCHRONOUS_TYPED_METHOD(NSNumber *, isDuoDevice) {
  return @([_implementation isDuoDevice]);
}

- (void)invalidate {
  [_implementation invalidate];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativePlystHomeSpecJSI>(params);
}

@end
