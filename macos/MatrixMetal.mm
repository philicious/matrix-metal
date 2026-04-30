#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#include <cstdlib>
#include <ctime>

#import "MatrixRenderer.h"



int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    srand((unsigned)time(nullptr));

    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        NSRect frame = NSMakeRect(0, 0, 1280, 800);
        NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
        [window setTitle:@"matrixgl-metal"];

        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        MatrixRenderer *renderer = [[MatrixRenderer alloc] initWithDevice:device];
        MTKView *view = [[MTKView alloc] initWithFrame:frame device:device];
        view.clearColor = MTLClearColorMake(0, 0, 0, 1);
        view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        view.preferredFramesPerSecond = 60;
        view.enableSetNeedsDisplay = NO;
        view.paused = NO;
        view.delegate = renderer;

        [window setContentView:view];
        [window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];

        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
            NSString *c = event.charactersIgnoringModifiers.lowercaseString;
            if ([c isEqualToString:@"q"] || event.keyCode == 53) {
                [NSApp terminate:nil];
            } else if ([c isEqualToString:@"s"]) {
                [renderer toggleClassic];
            } else if ([c isEqualToString:@"p"]) {
                [renderer togglePause];
            } else if ([c isEqualToString:@"n"]) {
                [renderer nextPicture];
            }
            return event;
        }];

        [NSApp run];
    }

    return 0;
}
