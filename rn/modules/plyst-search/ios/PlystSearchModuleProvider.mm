#import "PlystSearchModuleProvider.h"

#import <ReactCommon/RCTTurboModule.h>

#import "PlystSearchModule.h"

// RCTModuleProviders가 클래스 이름으로 찾아 C++ 모듈을 만드는 등록 클래스
@interface PlystSearchModuleProvider () <RCTModuleProvider>
@end

@implementation PlystSearchModuleProvider

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::PlystSearchModule>(params.jsInvoker);
}

@end
