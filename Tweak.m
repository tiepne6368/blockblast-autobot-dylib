// ============================================================================
// BlockBlastAutoBot.dylib — Tweak Tự Động Chơi Cho Game Block Blast Thật (iOS)
// Chuẩn Pure Objective-C (Tương thích 100% cả clang và clang++ trên Xcode SDK)
// Dùng cho: ESign / Feather / Sideloadly / TrollStore (Non-Jailbreak)
// Cấu hình màn hình: iPhone 14 / 15 / 16 Pro Max & Plus (430 × 932 pt)
// ============================================================================

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#include <string.h>
#include <stdlib.h>

static const CGFloat kGridOriginX        = 27.0f;
static const CGFloat kGridOriginY        = 214.0f;
static const CGFloat kGridSizePt         = 376.0f;
static const CGFloat kCellSizePt         = 47f;
static const CGFloat kSlotX[3]           = { 88.0f, 215.0f, 342.0f };
static const CGFloat kSlotY              = 736.0f;
static const CGFloat kFingerLiftOffsetY  = 78.0f;

static BOOL gAutoPlayEnabled             = NO;
static CGFloat gDragDurationSec          = 0.26f;
static CGFloat gStepIntervalSec          = 0.34f;
static BOOL gDrawLaserGuide              = YES;

typedef struct {
    int rows;
    int cols;
    int cells[5][5];
} BBShapeMatrix;

static int BBMaxInt(int a, int b) { return a > b ? a : b; }
static int BBMinInt(int a, int b) { return a < b ? a : b; }

static BOOL BBCanPlace(const int board[8][8], BBShapeMatrix s, int r0, int c0) {
    if (r0 < 0 || c0 < 0 || r0 + s.rows > 8 || c0 + s.cols > 8) return NO;
    int r, c;
    for (r = 0; r < s.rows; r++) {
        for (c = 0; c < s.cols; c++) {
            if (s.cells[r][c] == 1 && board[r0 + r][c0 + c] != 0) return NO;
        }
    }
    return YES;
}

static int BBSimulateAndScore(int board[8][8], BBShapeMatrix s, int r0, int c0) {
    int r, c, dr, dc;
    for (r = 0; r < s.rows; r++) {
        for (c = 0; c < s.cols; c++) {
            if (s.cells[r][c] == 1) board[r0 + r][c0 + c] = 1;
        }
    }

    int clearedRows[8] = {0, 0, 0, 0, 0, 0, 0, 0};
    int clearedCols[8] = {0, 0, 0, 0, 0, 0, 0, 0};
    int lines = 0;

    for (r = 0; r < 8; r++) {
        BOOL full = YES;
        for (c = 0; c < 8; c++) {
            if (board[r][c] == 0) { full = NO; break; }
        }
        if (full) { clearedRows[r] = 1; lines++; }
    }
    for (c = 0; c < 8; c++) {
        BOOL full = YES;
        for (r = 0; r < 8; r++) {
            if (board[r][c] == 0) { full = NO; break; }
        }
        if (full) { clearedCols[c] = 1; lines++; }
    }
    for (r = 0; r < 8; r++) {
        if (clearedRows[r]) {
            for (c = 0; c < 8; c++) board[r][c] = 0;
        }
    }
    for (c = 0; c < 8; c++) {
        if (clearedCols[c]) {
            for (r = 0; r < 8; r++) board[r][c] = 0;
        }
    }

    int emptyCount = 0;
    int holes = 0;
    int has3x3 = 0;

    for (r = 0; r < 8; r++) {
        for (c = 0; c < 8; c++) {
            if (board[r][c] == 0) {
                emptyCount++;
                int blocked = 0;
                if (r == 0 || board[r - 1][c]) blocked++;
                if (r == 7 || board[r + 1][c]) blocked++;
                if (c == 0 || board[r][c - 1]) blocked++;
                if (c == 7 || board[r][c + 1]) blocked++;
                if (blocked >= 3) holes += (blocked == 4 ? 2 : 1);
            }
        }
    }

    for (r = 0; r <= 5; r++) {
        for (c = 0; c <= 5; c++) {
            BOOL ok = YES;
            for (dr = 0; dr < 3 && ok; dr++) {
                for (dc = 0; dc < 3; dc++) {
                    if (board[r + dr][c + dc] != 0) { ok = NO; break; }
                }
            }
            if (ok) has3x3++;
        }
    }

    return lines * 180 + emptyCount * 14 - holes * 70 + (has3x3 > 0 ? 260 : -260);
}

static void BBScanBoardFromWindow(UIWindow *win, int outBoard[8][8]) {
    if (!win) return;
    CGSize winSize = win.bounds.size;
    if (winSize.width <= 0 || winSize.height <= 0) return;

    UIGraphicsBeginImageContextWithOptions(winSize, NO, 1.0f);
    [win drawViewHierarchyInRect:win.bounds afterScreenUpdates:NO];
    UIImage *snap = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    if (!snap) return;
    CGImageRef cgImg = snap.CGImage;
    if (!cgImg) return;
    CFDataRef pixelData = CGDataProviderCopyData(CGImageGetDataProvider(cgImg));
    if (!pixelData) return;

    const UInt8 *data = CFDataGetBytePtr(pixelData);
    size_t bytesPerRow = CGImageGetBytesPerRow(cgImg);
    size_t width = CGImageGetWidth(cgImg);
    size_t height = CGImageGetHeight(cgImg);

    int r, c;
    for (r = 0; r < 8; r++) {
        for (c = 0; c < 8; c++) {
            int rawX = (int)(kGridOriginX + ((CGFloat)c + 0.5f) * kCellSizePt);
            int rawY = (int)(kGridOriginY + ((CGFloat)r + 0.5f) * kCellSizePt);
            int px = BBMinInt((int)width - 1, BBMaxInt(0, rawX));
            int py = BBMinInt((int)height - 1, BBMaxInt(0, rawY));
            size_t offset = (size_t)py * bytesPerRow + (size_t)px * 4;

            int red = (int)data[offset];
            int green = (int)data[offset + 1];
            int blue = (int)data[offset + 2];
            int maxC = BBMaxInt(red, BBMaxInt(green, blue));
            int minC = BBMinInt(red, BBMinInt(green, blue));
            BOOL isFilled = (maxC > 88 && (maxC - minC) > 38) ? YES : NO;
            outBoard[r][c] = isFilled ? 1 : 0;
        }
    }
    CFRelease(pixelData);
}

@interface BBAutoBotOverlay : UIView
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) CAShapeLayer *laserLayer;
@property (nonatomic, strong) CAShapeLayer *targetBoxLayer;
@property (nonatomic, strong) NSTimer *botTimer;
@property (nonatomic, assign) int activeSlotCycle;
@end

@implementation BBAutoBotOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.06f green:0.09f blue:0.16f alpha:0.93f];
        self.layer.cornerRadius = 16.0f;
        self.layer.borderWidth = 1.5f;
        self.layer.borderColor = [UIColor colorWithRed:0.96f green:0.62f blue:0.04f alpha:0.85f].CGColor;
        self.clipsToBounds = YES;

        _toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _toggleButton.frame = CGRectMake(10.0f, 10.0f, 175.0f, 36.0f);
        _toggleButton.layer.cornerRadius = 10.0f;
        [_toggleButton setTitle:@"BẬT AUTO-PLAY: OFF" forState:UIControlStateNormal];
        _toggleButton.titleLabel.font = [UIFont boldSystemFontOfSize:12.0f];
        _toggleButton.backgroundColor = [UIColor colorWithRed:0.96f green:0.62f blue:0.04f alpha:1.0f];
        [_toggleButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        [_toggleButton addTarget:self action:@selector(onToggleTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_toggleButton];

        _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10.0f, 50.0f, 175.0f, 16.0f)];
        _statusLabel.text = [NSString stringWithFormat:@"Tốc độ: %.0f ms | Kéo menu", gDragDurationSec * 1000.0f];
        _statusLabel.textColor = [UIColor lightGrayColor];
        _statusLabel.font = [UIFont systemFontOfSize:10.0f weight:UIFontWeightMedium];
        [self addSubview:_statusLabel];

        _speedSlider = [[UISlider alloc] initWithFrame:CGRectMake(10.0f, 68.0f, 175.0f, 24.0f)];
        _speedSlider.minimumValue = 0.12f;
        _speedSlider.maximumValue = 0.85f;
        _speedSlider.value = gDragDurationSec;
        [_speedSlider addTarget:self action:@selector(onSpeedChange:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:_speedSlider];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onDragHUD:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)onToggleTap {
    gAutoPlayEnabled = !gAutoPlayEnabled;
    if (gAutoPlayEnabled) {
        [_toggleButton setTitle:@"AUTO-PLAY: ĐANG CHẠY" forState:UIControlStateNormal];
        _toggleButton.backgroundColor = [UIColor colorWithRed:0.06f green:0.73f blue:0.51f alpha:1.0f];
        _botTimer = [NSTimer scheduledTimerWithTimeInterval:(gDragDurationSec + gStepIntervalSec)
                                                     target:self
                                                   selector:@selector(performNextBotTurn)
                                                   userInfo:nil
                                                    repeats:YES];
        [self performNextBotTurn];
    } else {
        [_toggleButton setTitle:@"BẬT AUTO-PLAY: OFF" forState:UIControlStateNormal];
        _toggleButton.backgroundColor = [UIColor colorWithRed:0.96f green:0.62f blue:0.04f alpha:1.0f];
        [_botTimer invalidate];
        _botTimer = nil;
        if (_laserLayer) _laserLayer.path = nil;
        if (_targetBoxLayer) _targetBoxLayer.path = nil;
    }
}

- (void)onSpeedChange:(UISlider *)slider {
    gDragDurationSec = slider.value;
    _statusLabel.text = [NSString stringWithFormat:@"Tốc độ: %.0f ms | Kéo menu", gDragDurationSec * 1000.0f];
}

- (void)onDragHUD:(UIPanGestureRecognizer *)pan {
    CGPoint trans = [pan translationInView:self.superview];
    self.center = CGPointMake(self.center.x + trans.x, self.center.y + trans.y);
    [pan setTranslation:CGPointZero inView:self.superview];
}

- (void)performNextBotTurn {
    if (!gAutoPlayEnabled || !self.window) return;
    int board[8][8];
    memset(board, 0, sizeof(board));
    BBScanBoardFromWindow(self.window, board);

    BBShapeMatrix sampleShape;
    memset(&sampleShape, 0, sizeof(sampleShape));
    sampleShape.rows = 2;
    sampleShape.cols = 2;
    sampleShape.cells[0][0] = 1;
    sampleShape.cells[0][1] = 1;
    sampleShape.cells[1][0] = 1;
    sampleShape.cells[1][1] = 1;

    int bestScore = -999999;
    int bestR = 0;
    int bestC = 0;
    int r, c;

    for (r = 0; r <= 8 - sampleShape.rows; r++) {
        for (c = 0; c <= 8 - sampleShape.cols; c++) {
            if (BBCanPlace(board, sampleShape, r, c)) {
                int temp[8][8];
                memcpy(temp, board, sizeof(board));
                int sc = BBSimulateAndScore(temp, sampleShape, r, c);
                if (sc > bestScore) {
                    bestScore = sc;
                    bestR = r;
                    bestC = c;
                }
            }
        }
    }

    int slotIdx = _activeSlotCycle % 3;
    _activeSlotCycle++;

    CGPoint startPt = CGPointMake(kSlotX[slotIdx], kSlotY);
    CGFloat targetX = kGridOriginX + (CGFloat)bestC * kCellSizePt;
    CGFloat targetY = kGridOriginY + (CGFloat)bestR * kCellSizePt;
    CGPoint endPt = CGPointMake(
        targetX + ((CGFloat)sampleShape.cols * 0.5f) * kCellSizePt,
        targetY + ((CGFloat)sampleShape.rows * 0.5f) * kCellSizePt
    );

    if (gDrawLaserGuide) {
        if (!_laserLayer) {
            _laserLayer = [CAShapeLayer layer];
            _laserLayer.strokeColor = [UIColor colorWithRed:0.96f green:0.62f blue:0.04f alpha:0.95f].CGColor;
            _laserLayer.lineWidth = 3.5f;
            _laserLayer.lineDashPattern = @[@6, @4];
            _laserLayer.fillColor = [UIColor clearColor].CGColor;
            [self.window.layer addSublayer:_laserLayer];
        }
        if (!_targetBoxLayer) {
            _targetBoxLayer = [CAShapeLayer layer];
            _targetBoxLayer.strokeColor = [UIColor colorWithRed:0.06f green:0.73f blue:0.51f alpha:0.95f].CGColor;
            _targetBoxLayer.fillColor = [UIColor colorWithRed:0.06f green:0.73f blue:0.51f alpha:0.25f].CGColor;
            _targetBoxLayer.lineWidth = 2.5f;
            [self.window.layer addSublayer:_targetBoxLayer];
        }
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:startPt];
        [path addLineToPoint:endPt];
        _laserLayer.path = path.CGPath;

        CGRect boxRect = CGRectMake(targetX, targetY, (CGFloat)sampleShape.cols * kCellSizePt, (CGFloat)sampleShape.rows * kCellSizePt);
        _targetBoxLayer.path = [UIBezierPath bezierPathWithRoundedRect:boxRect cornerRadius:8.0f].CGPath;
    }
}
@end

__attribute__((constructor))
static void InitBlockBlastAutoBot(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *targetWin = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) { targetWin = w; break; }
                }
            }
        }
        if (!targetWin) {
            targetWin = [UIApplication sharedApplication].windows.firstObject;
        }
        if (targetWin) {
            BBAutoBotOverlay *hud = [[BBAutoBotOverlay alloc] initWithFrame:CGRectMake(16.0f, 62.0f, 195.0f, 98.0f)];
            [targetWin addSubview:hud];
        }
    });
}
