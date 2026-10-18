#import "PlystDetailBarButtonComponentView.h"

#import <react/renderer/components/PlystClipSpec/ComponentDescriptors.h>
#import <react/renderer/components/PlystClipSpec/EventEmitters.h>
#import <react/renderer/components/PlystClipSpec/Props.h>
#import <react/renderer/components/PlystClipSpec/RCTComponentViewHelpers.h>

#if __has_include("PlystBridge/PlystBridge-Swift.h")
#import "PlystBridge/PlystBridge-Swift.h"
#else
#import "PlystBridge-Swift.h"
#endif

using namespace facebook::react;

@interface PlystDetailBarButtonComponentView () <RCTPlystDetailBarButtonViewProtocol>
@end

@implementation PlystDetailBarButtonComponentView {
  DetailBarButton *_button;
  NSString *_icon;
  NSString *_title;
}

// 정적 링크된 클래스가 링커에서 제거되지 않도록 합니다. https://github.com/facebook/react-native/pull/37274
+ (void)load
{
  [super load];
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const PlystDetailBarButtonProps>();
    _props = defaultProps;
  }
  return self;
}

#pragma mark - RCTComponentViewProtocol

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<PlystDetailBarButtonComponentDescriptor>();
}

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
  const auto &newProps = *std::static_pointer_cast<PlystDetailBarButtonProps const>(props);
  NSString *icon = newProps.icon.empty() ? nil : [NSString stringWithUTF8String:newProps.icon.c_str()];
  NSString *title = newProps.title.empty() ? nil : [NSString stringWithUTF8String:newProps.title.c_str()];

  // 스타일은 버튼을 만들 때만 정해지므로 icon이나 title이 바뀌면 버튼을 새로 만듭니다.
  if (!_button || ![icon ?: @"" isEqualToString:_icon ?: @""] || ![title ?: @"" isEqualToString:_title ?: @""]) {
    [self replaceButtonWithIcon:icon title:title];
  }
  _button.enabled = newProps.isEnabled;

  [super updateProps:props oldProps:oldProps];
}

- (void)prepareForRecycle
{
  [super prepareForRecycle];
  [_button removeFromSuperview];
  _button = nil;
  _icon = nil;
  _title = nil;
}

#pragma mark - Private

- (void)replaceButtonWithIcon:(NSString *)icon title:(NSString *)title
{
  [_button removeFromSuperview];
  _icon = icon;
  _title = title;
  if (icon == nil && title == nil) {
    _button = nil;
    return;
  }
  _button = icon != nil ? [[DetailBarButton alloc] initWithIcon:icon] : [[DetailBarButton alloc] initWithTitle:title];
  [_button addTarget:self action:@selector(handlePress) forControlEvents:UIControlEventTouchUpInside];
  [self addSubview:_button];
  // 버튼은 자기 크기를 유지하므로 Yoga 상자의 중앙에 둡니다.
  [NSLayoutConstraint activateConstraints:@[
    [_button.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
    [_button.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
  ]];
}

- (void)handlePress
{
  if (_eventEmitter == nullptr) {
    return;
  }
  std::static_pointer_cast<PlystDetailBarButtonEventEmitter const>(_eventEmitter)->onPress({});
}

@end
