#import "PlystClipModule.h"

#if __has_include("PlystBridge/PlystBridge-Swift.h")
#import "PlystBridge/PlystBridge-Swift.h"
#else
#import "PlystBridge-Swift.h"
#endif

@implementation PlystClipModule {
  ClipBridgeModuleImpl *_implementation;
}

RCT_EXPORT_MODULE(PlystClip);

- (instancetype)init {
  self = [super init];
  if (self) {
    _implementation = [ClipBridgeModuleImpl new];
  }
  return self;
}

+ (BOOL)requiresMainQueueSetup {
  return NO;
}

RCT_EXPORT_METHOD(getClip:(NSString *)identifier
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
  [_implementation getClip:identifier completion:^(NSDictionary *record, NSString *code) {
    if (code) {
      reject(code, code, nil);
    } else {
      resolve(record ?: [NSNull null]);
    }
  }];
}

RCT_EXPORT_METHOD(updateClip:(NSString *)identifier
                  name:(NSString * _Nullable)name
                  memo:(NSString * _Nullable)memo
                  isPinned:(BOOL)isPinned
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
  [_implementation updateClip:identifier name:name memo:memo isPinned:isPinned completion:^(NSDictionary *record, NSString *code) {
    if (code) {
      reject(code, code, nil);
    } else {
      resolve(record ?: [NSNull null]);
    }
  }];
}

RCT_EXPORT_METHOD(deleteClip:(NSString *)identifier
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
  [_implementation deleteClip:identifier completion:^(NSString *code) {
    if (code) {
      reject(code, code, nil);
    } else {
      resolve(nil);
    }
  }];
}

RCT_EXPORT_METHOD(copyClip:(NSString *)identifier
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
  [_implementation copyClip:identifier completion:^(NSString *result, NSString *code) {
    if (code) {
      reject(code, code, nil);
    } else {
      resolve(result ?: [NSNull null]);
    }
  }];
}

- (void)invalidate {
  [_implementation invalidate];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativePlystClipSpecJSI>(params);
}

@end
