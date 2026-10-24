#import "PlystNavigationBarButtonComponentView.h"

#import <React/UIView+React.h>
#import <react/renderer/components/PlystClipSpec/ComponentDescriptors.h>
#import <react/renderer/components/PlystClipSpec/EventEmitters.h>
#import <react/renderer/components/PlystClipSpec/Props.h>
#import <react/renderer/components/PlystClipSpec/RCTComponentViewHelpers.h>

using namespace facebook::react;

@interface PlystNavigationBarButtonComponentView () <RCTPlystNavigationBarButtonViewProtocol>
@end

@implementation PlystNavigationBarButtonComponentView {
  UIBarButtonItem *_item;
  NSString *_side;
  NSString *_icon;
  NSString *_title;
  // 항목을 넣고 관찰 중인 navigationItem
  // 뺄 때는 응답자 체인이 끊겼을 수 있으므로 다시 찾지 않음
  // 관찰자를 해제하기 전에 해제되지 않도록 강한 참조로 둠
  UINavigationItem *_navigationItem;
  BOOL _isRight;
}

static void *ItemsObservationContext = &ItemsObservationContext;

// 정적 링크된 클래스가 링커에서 제거되지 않도록 함
// https://github.com/facebook/react-native/pull/37274
+ (void)load
{
  [super load];
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const PlystNavigationBarButtonProps>();
    _props = defaultProps;
  }
  return self;
}

#pragma mark - RCTComponentViewProtocol

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<PlystNavigationBarButtonComponentDescriptor>();
}

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
  const auto &newProps = *std::static_pointer_cast<PlystNavigationBarButtonProps const>(props);
  NSString *side = [NSString stringWithUTF8String:newProps.side.c_str()];
  NSString *icon = newProps.icon.empty() ? nil : [NSString stringWithUTF8String:newProps.icon.c_str()];
  NSString *title = newProps.title.empty() ? nil : [NSString stringWithUTF8String:newProps.title.c_str()];

  // 모양은 항목을 만들 때만 정하므로 side, icon, title이 바뀌면 항목을 새로 만들어 바꿔 넣음
  if (!_item || ![side isEqualToString:_side] || ![icon ?: @"" isEqualToString:_icon ?: @""] ||
      ![title ?: @"" isEqualToString:_title ?: @""]) {
    [self uninstallItem];
    _side = side;
    _icon = icon;
    _title = title;
    _item = [self makeItem];
    [self installItem];
  }
  _item.enabled = newProps.isEnabled;

  [super updateProps:props oldProps:oldProps];
}

- (void)didMoveToWindow
{
  [super didMoveToWindow];
  if (self.window != nil) {
    [self installItem];
  } else {
    [self uninstallItem];
  }
}

- (void)dealloc
{
  [self stopObservingNavigationItem];
}

- (void)prepareForRecycle
{
  [super prepareForRecycle];
  [self uninstallItem];
  _item = nil;
  _side = nil;
  _icon = nil;
  _title = nil;
}

#pragma mark - Private

- (UIBarButtonItem *)makeItem
{
  UIBarButtonItem *item;
  if (_icon != nil) {
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
    UIImage *image = [UIImage systemImageNamed:_icon withConfiguration:configuration];
    item = [[UIBarButtonItem alloc] initWithImage:image
                                            style:UIBarButtonItemStylePlain
                                           target:self
                                           action:@selector(handlePress)];
  } else {
    item = [[UIBarButtonItem alloc] initWithTitle:_title ?: @""
                                            style:UIBarButtonItemStylePlain
                                           target:self
                                           action:@selector(handlePress)];
  }
  item.tintColor = [UIColor colorNamed:@"HomePrimaryText"];
  return item;
}

// window에 붙어 있고 가장 가까운 뷰 컨트롤러가 내비게이션 컨트롤러 안에 있을 때만 항목을 넣음
- (void)installItem
{
  if (_item == nil || self.window == nil) {
    return;
  }
  UIViewController *controller = self.reactViewController;
  if (controller.navigationController == nil) {
    return;
  }
  UINavigationItem *navigationItem = controller.navigationItem;
  if (_navigationItem != navigationItem) {
    [self stopObservingNavigationItem];
    _navigationItem = navigationItem;
    [_navigationItem addObserver:self forKeyPath:@"leftBarButtonItems" options:0 context:ItemsObservationContext];
    [_navigationItem addObserver:self forKeyPath:@"rightBarButtonItems" options:0 context:ItemsObservationContext];
  }
  _isRight = ![_side isEqualToString:@"left"];
  if (_isRight) {
    if (![_navigationItem.rightBarButtonItems containsObject:_item]) {
      _navigationItem.rightBarButtonItems = @[ _item ];
    }
  } else if (![_navigationItem.leftBarButtonItems containsObject:_item]) {
    _navigationItem.leftBarButtonItems = @[ _item ];
  }
}

// react-native-screens는 헤더 설정을 갱신할 때마다 navigationItem의 좌우 항목을 nil로 비움
// 비워진 자리에 우리 항목이 없으면 다시 넣고 다른 항목이 차지한 자리는 건드리지 않음
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
  if (context != ItemsObservationContext) {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    return;
  }
  __weak PlystNavigationBarButtonComponentView *weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    PlystNavigationBarButtonComponentView *strongSelf = weakSelf;
    if (strongSelf == nil || strongSelf->_navigationItem == nil) {
      return;
    }
    NSArray<UIBarButtonItem *> *items =
        strongSelf->_isRight ? strongSelf->_navigationItem.rightBarButtonItems : strongSelf->_navigationItem.leftBarButtonItems;
    if (items.count == 0) {
      [strongSelf installItem];
    }
  });
}

- (void)stopObservingNavigationItem
{
  [_navigationItem removeObserver:self forKeyPath:@"leftBarButtonItems" context:ItemsObservationContext];
  [_navigationItem removeObserver:self forKeyPath:@"rightBarButtonItems" context:ItemsObservationContext];
  _navigationItem = nil;
}

// 다른 화면의 항목이 이미 자리를 차지했으면 그대로 둠
// 그래서 마운트 순서와 관계없이 항목 하나만 남음
- (void)uninstallItem
{
  UINavigationItem *navigationItem = _navigationItem;
  [self stopObservingNavigationItem];
  if (_item == nil) {
    return;
  }
  if ([navigationItem.rightBarButtonItems containsObject:_item]) {
    navigationItem.rightBarButtonItems = nil;
  }
  if ([navigationItem.leftBarButtonItems containsObject:_item]) {
    navigationItem.leftBarButtonItems = nil;
  }
}

- (void)handlePress
{
  if (_eventEmitter == nullptr) {
    return;
  }
  std::static_pointer_cast<PlystNavigationBarButtonEventEmitter const>(_eventEmitter)->onPress({});
}

@end
