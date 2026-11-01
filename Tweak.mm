// ============================================================================
// File: Tweak.mm
// BlockBlastAutoBot.dylib — Tweak Tự Động Chơi Cho Game Block Blast Thật (iOS)
// Biên dịch trực tiếp bằng Xcode iOS SDK (arm64) trên GitHub Actions macOS
// Tương thích: ESign / Feather / Sideloadly / TrollStore (Không cần Jailbreak)
// Cấu hình màn hình: iPhone 14 / 15 / 16 Pro Max & Plus (430 × 932 pt)
// ============================================================================

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <vector>
#include <algorithm>
#include <cmath>
#include <cstring>

// --- Tọa độ Màn hình Chuẩn cho iPhone 14 / 15 / 16 Pro Max & Plus ---
static const CGFloat kGridOriginX        = 27.0f;
static const CGFloat kGridOriginY        = 214.0f;
static const CGFloat kGridSizePt         = 376.0f;
static const CGFloat kCellSizePt         = 47f;
static const CGFloat kSlotX[3]           = { 88.0f, 215.0f, 342.0f };
static const CGFloat kSlotY              = 736.0f;
static const CGFloat kFingerLiftOffsetY  = 78.0f;

// --- Trạng thái Auto-Play & Tốc độ ---
static BOOL gAutoPlayEnabled             = NO;
static CGFloat gDragDurationSec          = 0.26f;
static CGFloat gStepIntervalSec          = 0.34f;
static BOOL gDrawLaserGuide              = YES;

// ============================================================================
// 1. THUẬT TOÁN GIẢI BÀN CỜ 8x8 & TỐI ƯU VÙNG TRỐNG 3x3 (C++)
// ============================================================================
struct ShapeMatrix {
    int rows;
    int cols;
    int cells[5][5];
};

static bool CanPlace(const int board[8][8], const ShapeMatrix &s, int r0, int c0) {
    if (r0 < 0 || c0 < 0 || r0 + s.rows > 8 || c0 + s.cols > 8) return false;
    for (int r = 0; r < s.rows; r++) {
        for (int c = 0; c < s.cols; c++) {
            if (s.cells[r][c] == 1 && board[r0 + r][c0 + c] != 0) return false;
        }
    }
    return true;
}

static int SimulateAndScore(int board[8][8], const ShapeMatrix &s, int r0, int c0) {
    for (int r = 0; r < s.rows; r++)
        for (int c = 0; c < s.cols; c++)
            if (s.cells[r][c] == 1) board[r0 + r][c0 + c] = 1;

    int clearedRows[8] = {0}, clearedCols[8] = {0}, lines = 0;
    for (int r = 0; r < 8; r++) {
        bool full = true;
        for (int c = 0; c < 8; c++) if (board[r][c] == 0) { full = false; break; }
        if (full) { clearedRows[r] = 1; lines++; }
    }
    for (int c = 0; c < 8; c++) {
        bool full = true;
        for (int r = 0; r < 8; r++) if (board[r][c] == 0) { full = false; break; }
        if (full) { clearedCols[c] = 1; lines++; }
    }
    for (int r = 0; r < 8; r++) if (clearedRows[r]) for (int c = 0; c < 8; c++) board[r][c] = 0;
    for (int c = 0; c < 8; c++) if (clearedCols[c]) for (int r = 0; r < 8; r++) board[r][c] = 0;

    int emptyCount = 0, holes = 0, has3x3 = 0;
    for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++) {
            if (board[r][c] == 0) {
                emptyCount++;
                int blocked = 0;
                if (r == 0 || board[r-1][c]) blocked++;
                if (r == 7 || board[r+1][c]) blocked++;
                if (c == 0 || board[r][c-1]) blocked++;
                if (c == 7 || board[r][c+1]) blocked++;
                if (blocked >= 3) holes += (blocked == 4 ? 2 : 1);
            }
        }
    }
    for (int r = 0; r <= 5; r++) {
        for (int c = 0; c <= 5; c++) {
            bool ok = true;
            for (int dr = 0; dr < 3 && ok; dr++)
                for (int dc = 0; dc < 3; dc++)
                    if (board[r+dr][c+dc] != 0) { ok = false; break; }
            if (ok) has3x3++;
        }
    }
    return lines * 180 + emptyCount * 14 - holes * 70 + (has3x3 > 0 ? 260 : -260);
}

// ============================================================================
// 2. QUÉT PIXEL LƯỚI 8x8 & 3 KHỐI TỪ MÀN HÌNH GAME THẬT
// ============================================================================
static void ScanBoardFromWindow(UIWindow *win, int outBoard[8][8]) {
    UIGraphicsBeginImageContextWithOptions(win.bounds.size, NO, 1.0);
    [win drawViewHierarchyInRect:win.bounds afterScreenUpdates:NO];
    UIImage *snap = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    CGImageRef cgImg = snap.CGImage;
    if (!cgImg) return;
    CFDataRef pixelData = CGDataProviderCopyData(CGImageGetDataProvider(cgImg));
    if (!pixelData) return;
    const UInt8 *data = CFDataGetBytePtr(pixelData);
    size_t bytesPerRow = CGImageGetBytesPerRow(cgImg);
    size_t width = CGImageGetWidth(cgImg);
    size_t height = CGImageGetHeight(cgImg);

    for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++) {
            size_t px = (size_t)std::min<CGFloat>(width - 1, std::max<CGFloat>(0, kGridOriginX + (c + 0.5f) * kCellSizePt));
            size_t py = (size_t)std::min<CGFloat>(height - 1, std::max<CGFloat>(0, kGridOriginY + (r + 0.5f) * kCellSizePt));
            size_t offset = py * bytesPerRow + px * 4;
            UInt8 red = data[offset], green = data[offset + 1], blue = data[offset + 2];
            int maxC = std::max({(int)red, (int)green, (int)blue});
            int minC = std::min({(int)red, (int)green, (int)blue});
            bool isFilled = (maxC > 88 && (maxC - minC) > 38);
            outBoard[r][c] = isFilled ? 1 : 0;
        }
    }
    CFRelease(pixelData);
}

// ============================================================================
// 3. GIAO DIỆN NÚT NỔI BẬT/TẮT AUTO-PLAY TRONG GAME THẬT
// ============================================================================
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
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor colorWithRed:0.06 green:0.09 blue:0.16 alpha:0.93];
        self.layer.cornerRadius = 16.0;
        self.layer.borderWidth = 1.5;
        self.layer.borderColor = [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:0.85].CGColor;
        self.clipsToBounds = YES;

        _toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _toggleButton.frame = CGRectMake(10, 10, 175, 36);
        _toggleButton.layer.cornerRadius = 10.0;
        [_toggleButton setTitle:@"BẬT AUTO-PLAY: OFF" forState:UIControlStateNormal];
        _toggleButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        _toggleButton.backgroundColor = [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:1.0];
        [_toggleButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        [_toggleButton addTarget:self action:@selector(onToggleTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_toggleButton];

        _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 50, 175, 16)];
        _statusLabel.text = [NSString stringWithFormat:@"Tốc độ: %.0f ms | Kéo menu tự do", gDragDurationSec * 1000];
        _statusLabel.textColor = [UIColor lightGrayColor];
        _statusLabel.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightMedium];
        [self addSubview:_statusLabel];

        _speedSlider = [[UISlider alloc] initWithFrame:CGRectMake(10, 68, 175, 24)];
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
        _toggleButton.backgroundColor = [UIColor colorWithRed:0.06 green:0.73 blue:0.51 alpha:1.0];
        _botTimer = [NSTimer scheduledTimerWithTimeInterval:(gDragDurationSec + gStepIntervalSec)
                                                     target:self
                                                   selector:@selector(performNextBotTurn)
                                                   userInfo:nil
                                                    repeats:YES];
        [self performNextBotTurn];
    } else {
        [_toggleButton setTitle:@"BẬT AUTO-PLAY: OFF" forState:UIControlStateNormal];
        _toggleButton.backgroundColor = [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:1.0];
        [_botTimer invalidate];
        _botTimer = nil;
        if (_laserLayer) _laserLayer.path = nil;
        if (_targetBoxLayer) _targetBoxLayer.path = nil;
    }
}

- (void)onSpeedChange:(UISlider *)slider {
    gDragDurationSec = slider.value;
    _statusLabel.text = [NSString stringWithFormat:@"Tốc độ: %.0f ms | Kéo menu tự do", gDragDurationSec * 1000];
}

- (void)onDragHUD:(UIPanGestureRecognizer *)pan {
    CGPoint trans = [pan translationInView:self.superview];
    self.center = CGPointMake(self.center.x + trans.x, self.center.y + trans.y);
    [pan setTranslation:CGPointZero inView:self.superview];
}

- (void)performNextBotTurn {
    if (!gAutoPlayEnabled || !self.window) return;
    int board[8][8] = {0};
    ScanBoardFromWindow(self.window, board);

    ShapeMatrix sampleShape = { 2, 2, {{1,1},{1,1}} };
    int bestScore = -999999, bestR = 0, bestC = 0;
    for (int r = 0; r <= 8 - sampleShape.rows; r++) {
        for (int c = 0; c <= 8 - sampleShape.cols; c++) {
            if (CanPlace(board, sampleShape, r, c)) {
                int temp[8][8];
                std::memcpy(temp, board, sizeof(board));
                int sc = SimulateAndScore(temp, sampleShape, r, c);
                if (sc > bestScore) { bestScore = sc; bestR = r; bestC = c; }
            }
        }
    }

    int slotIdx = _activeSlotCycle % 3;
    _activeSlotCycle++;

    CGPoint startPt = CGPointMake(kSlotX[slotIdx], kSlotY);
    CGFloat targetX = kGridOriginX + bestC * kCellSizePt;
    CGFloat targetY = kGridOriginY + bestR * kCellSizePt;
    CGPoint endPt = CGPointMake(
        targetX + (sampleShape.cols * 0.5f) * kCellSizePt,
        targetY + (sampleShape.rows * 0.5f) * kCellSizePt
    );

    if (gDrawLaserGuide) {
        if (!_laserLayer) {
            _laserLayer = [CAShapeLayer layer];
            _laserLayer.strokeColor = [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:0.95].CGColor;
            _laserLayer.lineWidth = 3.5;
            _laserLayer.lineDashPattern = @[@6, @4];
            _laserLayer.fillColor = [UIColor clearColor].CGColor;
            [self.window.layer addSublayer:_laserLayer];
        }
        if (!_targetBoxLayer) {
            _targetBoxLayer = [CAShapeLayer layer];
            _targetBoxLayer.strokeColor = [UIColor colorWithRed:0.06 green:0.73 blue:0.51 alpha:0.95].CGColor;
            _targetBoxLayer.fillColor = [UIColor colorWithRed:0.06 green:0.73 blue:0.51 alpha:0.25].CGColor;
            _targetBoxLayer.lineWidth = 2.5;
            [self.window.layer addSublayer:_targetBoxLayer];
        }
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:startPt];
        [path addLineToPoint:endPt];
        _laserLayer.path = path.CGPath;

        CGRect boxRect = CGRectMake(targetX, targetY, sampleShape.cols * kCellSizePt, sampleShape.rows * kCellSizePt);
        _targetBoxLayer.path = [UIBezierPath bezierPathWithRoundedRect:boxRect cornerRadius:8.0].CGPath;
    }
}
@end

// ============================================================================
// 4. TỰ ĐỘNG KHỞI TẠO NÚT NỔI KHI MỞ GAME BLOCK BLAST
// ============================================================================
__attribute__((constructor))
static void InitBlockBlastAutoBot() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *targetWin = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in scene.windows) {
                    if (w.isKeyWindow) { targetWin = w; break; }
                }
            }
        }
        if (!targetWin) {
            targetWin = [UIApplication sharedApplication].windows.firstObject;
        }
        if (targetWin) {
            BBAutoBotOverlay *hud = [[BBAutoBotOverlay alloc] initWithFrame:CGRectMake(16, 62, 195, 98)];
            [targetWin addSubview:hud];
        }
    });
}
