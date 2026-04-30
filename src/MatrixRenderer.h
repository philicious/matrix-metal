#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>

@interface MatrixRenderer : NSObject <MTKViewDelegate>
- (instancetype)initWithDevice:(id<MTLDevice>)device;
- (void)setImagesEnabled:(BOOL)enabled;
- (void)toggleClassic;
- (void)togglePause;
- (void)nextPicture;
@end
