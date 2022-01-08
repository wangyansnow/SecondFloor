//
//  ViewController.m
//  01-下拉刷新
//
//  Created by wing on 2022/1/3.
//

#import "ViewController.h"

NSString *const MJRefreshKeyPathContentOffset = @"contentOffset";
NSString *const MJRefreshKeyPathContentInset = @"contentInset";
NSString *const MJRefreshKeyPathContentSize = @"contentSize";
NSString *const MJRefreshKeyPathPanState = @"state";

CGFloat const WYSecondFloorLimit = 80;

/** 刷新控件的状态 */
typedef NS_ENUM(NSInteger, WYRefreshState) {
    /** 普通闲置状态 */
    WYRefreshStateIdle = 1,
    /** 松开就可以进行刷新的状态 */
    WYRefreshStatePulling,
    /** 正在刷新中的状态 */
    WYRefreshStateRefreshing,
    /** 即将刷新的状态 */
    WYRefreshStateWillRefresh,
    /** 松开就可以进入二楼的状态 */
    WYRefreshStateSecondFloor,
    /** 正在进入二楼中的状态 */
    WYRefreshStateSecondFloorProcessing,
    /** 展示二楼引导的状态 */
    WYRefreshStateSecondFloorGuide,
};

@interface ViewController ()<UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableview;
@property (nonatomic, strong) UIView *headerView;
@property (strong, nonatomic) UIPanGestureRecognizer *pan;

@property (nonatomic, assign) UIEdgeInsets scrollViewOriginalInset;
@property (nonatomic, assign) CGFloat pullingPercent;

@property (nonatomic, assign) WYRefreshState state;

/** 慢速动画时间(一般用在刷新结束后的回弹动画), 默认 0.4*/
@property (nonatomic) NSTimeInterval slowAnimationDuration;
/** 快速动画时间(一般用在刷新开始的回弹动画), 默认 0.25 */
@property (nonatomic) NSTimeInterval fastAnimationDuration;

@property (assign, nonatomic) CGFloat insetTDelta;

@property (nonatomic, copy) dispatch_block_t refreshingBlock;
@property (nonatomic, copy) dispatch_block_t enterSecondFloorBlock;
@property (nonatomic, copy) dispatch_block_t secondFloorGuideCompletionBlock;


@property (nonatomic, strong) UILabel *tipLabel;

@property (nonatomic, strong) UIImageView *guideImageView;
@property (nonatomic, assign) CGFloat guideH;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self setupUI];
    [self addObservers];
    self.state = WYRefreshStateIdle;
    self.slowAnimationDuration = 0.4;
    self.fastAnimationDuration = 0.25;
    
    __weak typeof(self) weakSelf = self;
    self.refreshingBlock = ^{
        NSLog(@"[Wing] 通知外部进行刷新的网络请求");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf endRefreshing];
        });
    };
    
    self.enterSecondFloorBlock = ^{
        NSLog(@"[Wing] 进入二楼完成");
        
        UIViewController *vc = [UIViewController new];
        vc.view.backgroundColor = [UIColor whiteColor];
        [weakSelf.navigationController pushViewController:vc animated:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf endRefreshing];
        });
    };
    
    self.secondFloorGuideCompletionBlock = ^{
        NSLog(@"[Wing] 二楼引导展示完成");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf endRefreshing];
        });
    };
}

- (void)setupUI {
    UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.bounds];
    tableView.dataSource = self;
    tableView.delegate = self;
    [self.view addSubview:tableView];
    self.tableview = tableView;
    
    CGFloat ScreenH = CGRectGetHeight(self.view.bounds);
    CGFloat ScreenW = CGRectGetWidth(self.view.bounds);
    
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, -60, self.view.bounds.size.width, 60)];
    headerView.backgroundColor = [UIColor cyanColor];
    [tableView insertSubview:headerView atIndex:0];
    
    self.tipLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, headerView.bounds.size.width, headerView.bounds.size.height)];
    self.tipLabel.textAlignment = NSTextAlignmentCenter;
    self.tipLabel.text = @"下拉刷新";
    [headerView addSubview:self.tipLabel];

    self.headerView = headerView;
    
    UIView *secondFloorView = [[UIView alloc] initWithFrame:CGRectMake(0, -self.view.bounds.size.height, self.view.bounds.size.width, self.view.bounds.size.height)];
    [tableView insertSubview:secondFloorView atIndex:0];
    
    UIImage *guideImg = [UIImage imageNamed:@"guide"];
    self.guideImageView = [[UIImageView alloc] initWithImage:guideImg];
    self.guideH = ScreenW * guideImg.size.height / guideImg.size.width;
    self.guideImageView.frame = CGRectMake(0, ScreenH - self.guideH, ScreenW, self.guideH);
    [secondFloorView addSubview:self.guideImageView];
}

- (IBAction)secondFloorBtnClick:(UIBarButtonItem *)sender {
    if (self.state != WYRefreshStateIdle) return;
    self.state = WYRefreshStateSecondFloorGuide;
}

- (IBAction)refreshBtnClick:(UIBarButtonItem *)sender {
    [self beginRefreshing];
}

#pragma mark - UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 40;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ID = @"example";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    if (!cell) {
        cell = [UITableViewCell new];
    }
    
    cell.textLabel.text = [NSString stringWithFormat:@"row - %@", @(indexPath.row)];
    
    return cell;
}


#pragma mark - KVO监听
- (void)addObservers
{
    NSKeyValueObservingOptions options = NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld;
    [self.tableview addObserver:self forKeyPath:MJRefreshKeyPathContentOffset options:options context:nil];
    [self.tableview addObserver:self forKeyPath:MJRefreshKeyPathContentSize options:options context:nil];
    self.pan = self.tableview.panGestureRecognizer;
    [self.pan addObserver:self forKeyPath:MJRefreshKeyPathPanState options:options context:nil];
    

}

- (void)removeObservers
{
    [self.tableview removeObserver:self forKeyPath:MJRefreshKeyPathContentOffset];
    [self.tableview removeObserver:self forKeyPath:MJRefreshKeyPathContentSize];
    [self.pan removeObserver:self forKeyPath:MJRefreshKeyPathPanState];
    self.pan = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    // 遇到这些情况就直接返回
    if (!self.view.userInteractionEnabled) return;
    
    // 这个就算看不见也需要处理
    if ([keyPath isEqualToString:MJRefreshKeyPathContentSize]) {
        [self scrollViewContentSizeDidChange:change];
    }
    
    // 看不见
    if (self.view.hidden) return;
    if ([keyPath isEqualToString:MJRefreshKeyPathContentOffset]) {
        [self scrollViewContentOffsetDidChange:change];
    } else if ([keyPath isEqualToString:MJRefreshKeyPathPanState]) {
        [self scrollViewPanStateDidChange:change];
    }
}

- (void)scrollViewContentOffsetDidChange:(NSDictionary *)change {
    
    // 在刷新的refreshing状态
    if (self.state == WYRefreshStateRefreshing || self.state == WYRefreshStateSecondFloorProcessing || self.state == WYRefreshStateSecondFloorGuide) {
        [self resetInset];
        return;
    }
    
    // 当前的contentOffset
    CGFloat offsetY = self.tableview.contentOffset.y;
    
    // 跳转到下一个控制器时，contentInset可能会变
    _scrollViewOriginalInset = [self wy_inset];
//    NSLog(@"[Wing] offsetY = %@", @(offsetY));
    
    // 头部控件刚好出现的offsetY
    CGFloat happenOffsetY = - self.scrollViewOriginalInset.top;
    
    // 如果是向上滚动到看不见头部控件，直接返回
    if (offsetY > happenOffsetY) return;
    
    // 普通 和 即将刷新 的临界点
    CGFloat normal2pullingOffsetY = happenOffsetY - self.headerView.bounds.size.height;

    // 松手进入二楼 的临界点
    CGFloat secondFloorOffsetY = normal2pullingOffsetY - WYSecondFloorLimit;
    
    CGFloat pullingPercent = (happenOffsetY - offsetY) / self.headerView.bounds.size.height;
    
    if (self.tableview.isDragging) { // 正在拖拽中
        self.pullingPercent = pullingPercent;
        if ((self.state == WYRefreshStateIdle && offsetY < normal2pullingOffsetY) || (self.state == WYRefreshStateSecondFloor && offsetY >= secondFloorOffsetY) ) {
            // 转为即将刷新状态
            self.state = WYRefreshStatePulling;
            NSLog(@"[Wing] 转为即将刷新状态");
            self.tipLabel.text = @"松手刷新，下拉进入二楼";
        } else if (self.state == WYRefreshStatePulling && offsetY >= normal2pullingOffsetY) {
            // 转为普通状态
            self.state = WYRefreshStateIdle;
            NSLog(@"[Wing] 转为普通状态");
            self.tipLabel.text = @"下拉刷新";
        } else if (self.state == WYRefreshStatePulling && offsetY < secondFloorOffsetY) {
            // 转为进入二楼状态
            self.state = WYRefreshStateSecondFloor;
            NSLog(@"[Wing] 转为进入二楼状态");
            self.tipLabel.text = @"松手进入二楼";
            
            UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [feedback impactOccurred];
        }
    } else if (self.state == WYRefreshStatePulling) { // 即将刷新 && 手松开
        NSLog(@"[Wing] 开始刷新");
        self.tipLabel.text = @"刷新中...";
        // 开始刷新
        [self beginRefreshing];
    } else if (self.state == WYRefreshStateSecondFloor) { // 即将进入二楼 && 手松开
        NSLog(@"[Wing] 开始进入二楼");
        self.state = WYRefreshStateSecondFloorProcessing;
    } else if (pullingPercent < 1) {
        self.pullingPercent = pullingPercent;
    }
    
    NSLog(@"[Wing] pullingPercent = %@", @(self.pullingPercent));
}
- (void)scrollViewContentSizeDidChange:(NSDictionary *)change{}
- (void)scrollViewPanStateDidChange:(NSDictionary *)change{}

#pragma mark - 进入刷新状态
- (void)beginRefreshing {
    if (self.headerView.window) {
        self.state = WYRefreshStateRefreshing;
    } else {
        // 预防正在刷新中时，调用本方法使得header inset回置失败
        if (self.state != WYRefreshStateRefreshing) {
            self.state = WYRefreshStateWillRefresh;
            // 刷新(预防从另一个控制器回到这个控制器的情况，回来要重新刷新一下)
            [self.headerView setNeedsDisplay];
        }
    }
}

- (void)setState:(WYRefreshState)state {
    WYRefreshState oldState = _state;
    if (oldState == state) return;
    _state = state;
    
    // 根据状态做事情
    if (state == WYRefreshStateIdle) {
//        if (oldState != WYRefreshStateRefreshing) return;
        if (oldState == WYRefreshStateRefreshing || oldState == WYRefreshStateSecondFloorProcessing || oldState == WYRefreshStateSecondFloorGuide) {
            [self headerEndingAction];
        }
    } else if (state == WYRefreshStateRefreshing) {
        [self headerRefreshingAction];
    } else if (state == WYRefreshStateSecondFloorProcessing) {
        [self headerEnterSecondFloor];
    } else if (state == WYRefreshStateSecondFloorGuide) {
        [self headerSecondFloorGuide];
    }
}

- (void)headerSecondFloorGuide {
    self.headerView.hidden = YES;
    [UIView animateWithDuration:self.fastAnimationDuration animations:^{
        if (self.tableview.panGestureRecognizer.state != UIGestureRecognizerStateCancelled) {
            CGFloat top = self.scrollViewOriginalInset.top + self.guideH;
            // 增加滚动区域top
            [self setInsetT:top];
            // 设置滚动位置
            CGPoint offset = self.tableview.contentOffset;
            offset.y = -top;
            [self.tableview setContentOffset:offset animated:NO];
        }
    } completion:^(BOOL finished) {
        if (self.secondFloorGuideCompletionBlock) {
            self.secondFloorGuideCompletionBlock();
        }
    }];
}

- (void)headerEnterSecondFloor {
    [UIView animateWithDuration:self.fastAnimationDuration animations:^{
        if (self.tableview.panGestureRecognizer.state != UIGestureRecognizerStateCancelled) {
            CGFloat top = self.scrollViewOriginalInset.top + self.view.bounds.size.height - 88;
            // 增加滚动区域top
            [self setInsetT:top];
            // 设置滚动位置
            CGPoint offset = self.tableview.contentOffset;
            offset.y = -top;
            [self.tableview setContentOffset:offset animated:NO];
//            self.tabBarController.tabBar.hidden = YES;
        }
    } completion:^(BOOL finished) {
        if (self.enterSecondFloorBlock) {
            self.enterSecondFloorBlock();
        }
    }];
}

- (void)endRefreshing {
    self.state = WYRefreshStateIdle;
    self.tipLabel.text = @"下拉刷新";
}

- (void)headerEndingAction {
    // 恢复inset和offset
    [UIView animateWithDuration:self.slowAnimationDuration animations:^{
        CGFloat top = [self wy_inset].top + self.insetTDelta;
        [self setInsetT:top];
    } completion:^(BOOL finished) {
        self.headerView.hidden = NO;
        self.pullingPercent = 0;
    }];
}

- (void)headerRefreshingAction {
    [UIView animateWithDuration:self.fastAnimationDuration animations:^{
        if (self.tableview.panGestureRecognizer.state != UIGestureRecognizerStateCancelled) {
            CGFloat top = self.scrollViewOriginalInset.top + self.headerView.bounds.size.height;
            // 增加滚动区域top
            [self setInsetT:top];
            // 设置滚动位置
            CGPoint offset = self.tableview.contentOffset;
            offset.y = -top;
            [self.tableview setContentOffset:offset animated:NO];
        }
    } completion:^(BOOL finished) {
        if (self.refreshingBlock) {
            self.refreshingBlock();
        }
    }];
}

#pragma mark - Inset
- (void)resetInset {
    if (@available(iOS 11.0, *)) {
    } else {
        // 如果 iOS 10 及以下系统在刷新时, push 新的 VC, 等待刷新完成后回来, 会导致顶部 Insets.top 异常, 不能 resetInset, 检查一下这种特殊情况
        if (!self.headerView.window) { return; }
    }
    
    // sectionheader停留解决
    CGFloat insetT = - self.tableview.contentOffset.y > _scrollViewOriginalInset.top ? - self.tableview.contentOffset.y : _scrollViewOriginalInset.top;
    
    if (self.state == WYRefreshStateRefreshing) {
        insetT = insetT > self.headerView.bounds.size.height + _scrollViewOriginalInset.top ? self.headerView.bounds.size.height + _scrollViewOriginalInset.top : insetT;
    } else if (self.state == WYRefreshStateSecondFloorProcessing) {
        CGFloat top = self.scrollViewOriginalInset.top + self.view.bounds.size.height - 88;
        insetT = insetT > top ? top : insetT;
    }
    
    self.insetTDelta = _scrollViewOriginalInset.top - insetT;
    // 避免 CollectionView 在使用根据 Autolayout 和 内容自动伸缩 Cell, 刷新时导致的 Layout 异常渲染问题
    
    NSLog(@"[Wing] resetInset top = %@, delta = %@", @(insetT), @(self.insetTDelta));
    UIEdgeInsets inset = [self wy_inset];
    if (inset.top != insetT) {
        [self setInsetT:insetT];
    }
}

- (UIEdgeInsets)wy_inset
{
#ifdef __IPHONE_11_0
    if ([self.tableview respondsToSelector:@selector(adjustedContentInset)]) {
        return self.tableview.adjustedContentInset;
    }
#endif
    return self.tableview.contentInset;
}

- (void)setInsetT:(CGFloat)top {
    
    UIEdgeInsets inset = self.tableview.contentInset;
    inset.top = top;
#ifdef __IPHONE_11_0
    if ([self.tableview respondsToSelector:@selector(adjustedContentInset)]) {
        inset.top -= (self.tableview.adjustedContentInset.top - self.tableview.contentInset.top);
    }
#endif
    self.tableview.contentInset = inset;
}

@end
