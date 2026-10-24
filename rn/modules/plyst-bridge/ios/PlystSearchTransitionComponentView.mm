#import "PlystSearchTransitionComponentView.h"

#import <React/RCTConversions.h>
#import <react/renderer/components/PlystClipSpec/ComponentDescriptors.h>
#import <react/renderer/components/PlystClipSpec/EventEmitters.h>
#import <react/renderer/components/PlystClipSpec/Props.h>
#import <react/renderer/components/PlystClipSpec/RCTComponentViewHelpers.h>

using namespace facebook::react;

// 원본 UIKit 검색 화면의 UIView.animate와 같은 길이입니다.
static const NSTimeInterval TransitionDuration = 0.3;

@interface PlystSearchTransitionComponentView () <RCTPlystSearchTransitionViewProtocol>
@end

@implementation PlystSearchTransitionComponentView {
  BOOL _isFadeOut;
  BOOL _isExpand;
  // props가 요구하는 상태입니다.
  BOOL _requestedIsPresented;
  // 화면에 반영한 상태입니다.
  BOOL _isPresented;
  BOOL _hasConfigured;
  // expand의 model frame이 너비 0으로 접혀 있으면 YES입니다.
  BOOL _isCollapsed;
  // Yoga가 정한 펼친 frame입니다.
  CGRect _finalFrame;
  // 재활용 전에 시작한 애니메이션의 완료 신호를 버리기 위한 번호입니다.
  NSUInteger _generation;
}

// 정적 링크된 클래스가 링커에서 제거되지 않도록 합니다. https://github.com/facebook/react-native/pull/37274
+ (void)load
{
  [super load];
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const PlystSearchTransitionProps>();
    _props = defaultProps;
  }
  return self;
}

#pragma mark - RCTComponentViewProtocol

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<PlystSearchTransitionComponentDescriptor>();
}

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
  const auto &newProps = *std::static_pointer_cast<PlystSearchTransitionProps const>(props);
  // 알 수 없는 effect는 fadeIn으로 다룹니다.
  _isFadeOut = newProps.effect == "fadeOut";
  _isExpand = newProps.effect == "expand";
  _requestedIsPresented = newProps.isPresented;

  [super updateProps:props oldProps:oldProps];
}

- (void)updateLayoutMetrics:(const LayoutMetrics &)layoutMetrics oldLayoutMetrics:(const LayoutMetrics &)oldLayoutMetrics
{
  [super updateLayoutMetrics:layoutMetrics oldLayoutMetrics:oldLayoutMetrics];
  _finalFrame = RCTCGRectFromRect(layoutMetrics.frame);
  // Yoga frame이 바뀌면 super가 펼친 frame으로 되돌리므로 접힌 동안에는 다시 접습니다.
  if (_isCollapsed) {
    [self applyCollapsedFrame];
  }
}

// RCTViewComponentView는 props 변경과 레이아웃 변경마다 layer.opacity를 prop 값으로 되돌립니다.
// 그래서 super 뒤에 상태가 정한 알파를 다시 넣습니다. 진행 중인 애니메이션은 이 대입으로 지워지지 않습니다.
- (void)finalizeUpdates:(RNComponentViewUpdateMask)updateMask
{
  [super finalizeUpdates:updateMask];
  if (!_hasConfigured) {
    _hasConfigured = YES;
    _isPresented = _requestedIsPresented;
    self.alpha = [self restingAlphaForPresented:_isPresented];
    return;
  }
  if (_isPresented != _requestedIsPresented) {
    [self transitionToPresented:_requestedIsPresented];
    return;
  }
  self.alpha = [self restingAlphaForPresented:_isPresented];
}

// 외형이 바뀌면 super가 invalidateLayer로 알파를 되돌립니다.
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
  [super traitCollectionDidChange:previousTraitCollection];
  if (_hasConfigured) {
    self.alpha = [self restingAlphaForPresented:_isPresented];
  }
}

- (void)prepareForRecycle
{
  [super prepareForRecycle];
  [self.layer removeAllAnimations];
  _generation += 1;
  if (_isCollapsed) {
    self.frame = _finalFrame;
  }
  _isFadeOut = NO;
  _isExpand = NO;
  _requestedIsPresented = NO;
  _isPresented = NO;
  _hasConfigured = NO;
  _isCollapsed = NO;
}

#pragma mark - Private

- (CGFloat)restingAlphaForPresented:(BOOL)isPresented
{
  return (_isFadeOut ? !isPresented : isPresented) ? 1 : 0;
}

- (CGRect)collapsedFrame
{
  return CGRectMake(CGRectGetMaxX(_finalFrame), _finalFrame.origin.y, 0, _finalFrame.size.height);
}

- (void)applyCollapsedFrame
{
  self.frame = [self collapsedFrame];
}

- (void)transitionToPresented:(BOOL)isPresented
{
  _isPresented = isPresented;
  const NSUInteger generation = ++_generation;
  const BOOL isExpand = _isExpand;
  const BOOL isAnimating = self.layer.animationKeys.count != 0;
  const CGRect finalFrame = _finalFrame;
  const CGRect collapsedFrame = [self collapsedFrame];
  const CGFloat targetAlpha = [self restingAlphaForPresented:isPresented];

  // super가 되돌린 알파를 시작 상태로 맞춥니다. 진행 중인 애니메이션을 되돌리는 경우에는 현재 표시 값에서 이어갑니다.
  [UIView performWithoutAnimation:^{
    self.alpha = [self restingAlphaForPresented:!isPresented];
    if (isExpand && isPresented && !isAnimating) {
      [self applyCollapsedFrame];
    }
  }];
  _isCollapsed = isExpand && !isPresented;

  __weak PlystSearchTransitionComponentView *weakSelf = self;
  [UIView animateWithDuration:TransitionDuration
      delay:0
      options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut
      animations:^{
        PlystSearchTransitionComponentView *strongSelf = weakSelf;
        if (strongSelf == nil) {
          return;
        }
        strongSelf.alpha = targetAlpha;
        if (isExpand) {
          strongSelf.frame = isPresented ? finalFrame : collapsedFrame;
        }
      }
      completion:^(BOOL finished) {
        PlystSearchTransitionComponentView *strongSelf = weakSelf;
        if (strongSelf == nil || !finished || generation != strongSelf->_generation) {
          return;
        }
        [strongSelf emitTransitionEndWithPresented:isPresented];
      }];
}

- (void)emitTransitionEndWithPresented:(BOOL)isPresented
{
  if (_eventEmitter == nullptr) {
    return;
  }
  PlystSearchTransitionEventEmitter::OnTransitionEnd event{};
  event.isPresented = isPresented;
  std::static_pointer_cast<PlystSearchTransitionEventEmitter const>(_eventEmitter)->onTransitionEnd(event);
}

@end
