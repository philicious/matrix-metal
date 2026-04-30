#import <ScreenSaver/ScreenSaver.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#import "MatrixRenderer.h"

@interface MatrixMetalScreenSaverView : ScreenSaverView
@end

@implementation MatrixMetalScreenSaverView {
    MTKView *_mtkView;
    MatrixRenderer *_renderer;
    NSPanel *_configSheet;
    NSButton *_imagesCheckbox;
    BOOL _hasAppliedImagesEnabled;
    BOOL _appliedImagesEnabled;
}

static NSString * const kSaverImagesEnabledKey = @"imagesEnabled";

- (NSString *)defaultsModuleName {
    NSString *bundleID = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
    return bundleID.length > 0 ? bundleID : @"com.matrixmetal.saver.configurable";
}

- (BOOL)imagesEnabledFromDefaults {
    ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:[self defaultsModuleName]];
    [defaults registerDefaults:@{kSaverImagesEnabledKey: @YES}];
    [defaults synchronize];
    return [defaults boolForKey:kSaverImagesEnabledKey];
}

- (void)saveImagesEnabledToDefaults:(BOOL)enabled {
    ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:[self defaultsModuleName]];
    [defaults setBool:enabled forKey:kSaverImagesEnabledKey];
    [defaults synchronize];
}

- (void)applyDefaultsToRenderer {
    if (_renderer) {
        BOOL enabled = [self imagesEnabledFromDefaults];
        if (!_hasAppliedImagesEnabled || _appliedImagesEnabled != enabled) {
            [_renderer setImagesEnabled:enabled];
            _appliedImagesEnabled = enabled;
            _hasAppliedImagesEnabled = YES;
        }
    }
}

- (void)commonInit {
    if (_mtkView) return;

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return;

    _renderer = [[MatrixRenderer alloc] initWithDevice:device];
    if (!_renderer) return;
    _mtkView = [[MTKView alloc] initWithFrame:self.bounds device:device];
    _mtkView.translatesAutoresizingMaskIntoConstraints = NO;
    _mtkView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    _mtkView.autoResizeDrawable = YES;
    _mtkView.clearColor = MTLClearColorMake(0, 0, 0, 1);
    _mtkView.preferredFramesPerSecond = 30;
    _mtkView.enableSetNeedsDisplay = YES;
    _mtkView.paused = YES;
    _mtkView.delegate = _renderer;

    [self addSubview:_mtkView];
    [NSLayoutConstraint activateConstraints:@[
        [_mtkView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_mtkView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_mtkView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_mtkView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    [self syncDrawableSize];
    [self applyDefaultsToRenderer];
}

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview {
    self = [super initWithFrame:frame isPreview:isPreview];
    if (!self) return nil;

    [self setAnimationTimeInterval:(1.0 / 30.0)];
    [self commonInit];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (!self) return nil;

    [self commonInit];
    return self;
}

- (void)layout {
    [super layout];
    [self syncDrawableSize];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self syncDrawableSize];
}

- (void)startAnimation {
    [super startAnimation];
    [self syncDrawableSize];
    [self applyDefaultsToRenderer];
}

- (void)stopAnimation {
    [super stopAnimation];
}

- (void)animateOneFrame {
    [self applyDefaultsToRenderer];
    [self syncDrawableSize];
    [_mtkView draw];
}

- (BOOL)hasConfigureSheet {
    return YES;
}

- (NSWindow *)configureSheet {
    if (_configSheet) {
        _imagesCheckbox.state = [self imagesEnabledFromDefaults] ? NSControlStateValueOn : NSControlStateValueOff;
        return _configSheet;
    }

    NSRect frame = NSMakeRect(0, 0, 320, 120);
    _configSheet = [[NSPanel alloc] initWithContentRect:frame
                                               styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    _configSheet.floatingPanel = YES;
    _configSheet.becomesKeyOnlyIfNeeded = YES;
    [_configSheet setTitle:@"MatrixMetal Options"];

    NSView *content = _configSheet.contentView;
    _imagesCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(24, 64, 260, 24)];
    _imagesCheckbox.buttonType = NSButtonTypeSwitch;
    _imagesCheckbox.title = @"Show images";
    _imagesCheckbox.state = [self imagesEnabledFromDefaults] ? NSControlStateValueOn : NSControlStateValueOff;
    [content addSubview:_imagesCheckbox];

    NSButton *okButton = [[NSButton alloc] initWithFrame:NSMakeRect(220, 20, 80, 28)];
    okButton.bezelStyle = NSBezelStyleRounded;
    okButton.title = @"OK";
    okButton.keyEquivalent = @"\r";
    okButton.target = self;
    okButton.action = @selector(okClick:);
    [content addSubview:okButton];

    NSButton *cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(130, 20, 80, 28)];
    cancelButton.bezelStyle = NSBezelStyleRounded;
    cancelButton.title = @"Cancel";
    cancelButton.keyEquivalent = @"\u001b";
    cancelButton.target = self;
    cancelButton.action = @selector(cancelClick:);
    [content addSubview:cancelButton];

    return _configSheet;
}

- (IBAction)configureSheet:(id)sender {
    (void)sender;

    NSWindow *sheet = [self configureSheet];
    if (!sheet) return;

    NSWindow *parent = self.window;
    if (!parent) {
        [sheet makeKeyAndOrderFront:nil];
        return;
    }

    if (sheet.sheetParent == parent) return;
    [parent beginSheet:sheet completionHandler:nil];
}

- (IBAction)okClick:(id)sender {
    (void)sender;
    BOOL enabled = (_imagesCheckbox.state == NSControlStateValueOn);
    [self saveImagesEnabledToDefaults:enabled];
    [self applyDefaultsToRenderer];
    [[NSApplication sharedApplication] endSheet:_configSheet];
    [_configSheet orderOut:nil];
}

- (IBAction)cancelClick:(id)sender {
    (void)sender;
    _imagesCheckbox.state = [self imagesEnabledFromDefaults] ? NSControlStateValueOn : NSControlStateValueOff;
    [[NSApplication sharedApplication] endSheet:_configSheet];
    [_configSheet orderOut:nil];
}

- (void)syncDrawableSize {
    if (!_mtkView) return;

    CGFloat scale = self.window ? self.window.backingScaleFactor : NSScreen.mainScreen.backingScaleFactor;
    if (scale <= 0.0) scale = 2.0;

    CGSize size = CGSizeMake(self.bounds.size.width * scale, self.bounds.size.height * scale);
    if (size.width < 1.0) size.width = 1.0;
    if (size.height < 1.0) size.height = 1.0;
    _mtkView.drawableSize = size;
}

@end

@interface MatrixMetalScreensaverView : MatrixMetalScreenSaverView
@end

@implementation MatrixMetalScreensaverView
@end
