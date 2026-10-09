#import "PlystToastModule.h"

#if __has_include("PlystBridge/PlystBridge-Swift.h")
#import "PlystBridge/PlystBridge-Swift.h"
#else
#import "PlystBridge-Swift.h"
#endif

@implementation PlystToastModule {
  ToastBridgeModuleImpl *_implementation;
}

RCT_EXPORT_MODULE(PlystToast);

- (instancetype)init {
  self = [super init];
  if (self) {
    __weak PlystToastModule *weakSelf = self;
    _implementation = [[ToastBridgeModuleImpl alloc] initWithEmit:^(NSString *message, BOOL isSuccess) {
      [weakSelf emitOnToastRequest:@{@"message": message, @"isSuccess": @(isSuccess)}];
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

- (void)invalidate {
  [_implementation invalidate];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativePlystToastSpecJSI>(params);
}

@end
