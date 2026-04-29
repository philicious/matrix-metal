#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <ctime>
#include <vector>

#include "data/fonts.h"
#include "data/images.h"

static const int kRTextX = 90;
static const int kTextY = 70;
static const int kNumPics = 10;

struct Glyph {
    uint8_t num;
    uint8_t alpha;
    float z;
};

struct Vertex {
    float x;
    float y;
    float u;
    float v;
    float r;
    float g;
    float b;
    float a;
};

static inline int clampi(int x, int low, int high) {
    return x > high ? high : (x < low ? low : x);
}

@interface MatrixRenderer : NSObject <MTKViewDelegate>
@end

@implementation MatrixRenderer {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    id<MTLSamplerState> _glyphSampler;
    id<MTLSamplerState> _flareSampler;
    id<MTLBuffer> _vertexBuffer;
    id<MTLTexture> _fontTexGreen;
    id<MTLTexture> _flareTex;

    std::vector<Glyph> _glyphs;
    std::vector<uint8_t> _speeds;
    std::vector<Vertex> _verts;

    int _textX;
    int _picOffset;
    long _timer;
    int _picFade;
    bool _classic;
    bool _paused;
    int _rainIntensity;
    int _updateDivider;
    int _updateTick;
}

- (void)glyphUVForNum:(uint8_t)num u0:(float *)u0 v0:(float *)v0 u1:(float *)u1 v1:(float *)v1 {
    const float cols = 10.0f;
    const float rows = 6.0f;
    const float texW = 512.0f;
    const float texH = 256.0f;
    const float cellU = 1.0f / cols;
    const float cellV = 1.0f / rows;
    const float insetU = 0.5f / texW;
    const float insetV = 0.5f / texH;
    const int col = num % 10;
    const int row = num / 10;

    *u0 = col * cellU + insetU;
    *u1 = (col + 1) * cellU - insetU;

    /* The source atlas is addressed from the top row downward. */
    float top = 1.0f - row * cellV;
    float bottom = top - cellV;
    *v0 = top - insetV;
    *v1 = bottom + insetV;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    _device = MTLCreateSystemDefaultDevice();
    _queue = [_device newCommandQueue];
    _timer = 40;
    _picFade = 0;
    _classic = true;
    _paused = false;
    _rainIntensity = 1;
    _updateDivider = 2;
    _updateTick = 0;

    [self setupPipeline];
    [self setupStateForSize:1280 height:800];
    [self setupTextures];
    [self warmup];
    return self;
}

- (void)setupPipeline {
    NSError *error = nil;
    NSString *src = @"using namespace metal;"
    "struct VIn { float2 pos [[attribute(0)]]; float2 uv [[attribute(1)]]; float4 color [[attribute(2)]]; };"
    "struct VOut { float4 pos [[position]]; float2 uv; float4 color; };"
    "vertex VOut vs_main(VIn in [[stage_in]]) { VOut o; o.pos=float4(in.pos,0,1); o.uv=in.uv; o.color=in.color; return o; }"
    "fragment float4 fs_main(VOut in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]]) {"
    " float a = t.sample(s, in.uv).r; return float4(in.color.rgb * a, in.color.a * a); }";

    id<MTLLibrary> lib = [_device newLibraryWithSource:src options:nil error:&error];
    if (!lib) {
        NSLog(@"Shader compile error: %@", error);
        abort();
    }

    MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
    d.vertexFunction = [lib newFunctionWithName:@"vs_main"];
    d.fragmentFunction = [lib newFunctionWithName:@"fs_main"];
    d.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    d.colorAttachments[0].blendingEnabled = YES;
    d.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    d.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    d.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    d.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
    d.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    d.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;

    MTLVertexDescriptor *vd = [MTLVertexDescriptor vertexDescriptor];
    vd.attributes[0].format = MTLVertexFormatFloat2;
    vd.attributes[0].offset = 0;
    vd.attributes[0].bufferIndex = 0;
    vd.attributes[1].format = MTLVertexFormatFloat2;
    vd.attributes[1].offset = sizeof(float) * 2;
    vd.attributes[1].bufferIndex = 0;
    vd.attributes[2].format = MTLVertexFormatFloat4;
    vd.attributes[2].offset = sizeof(float) * 4;
    vd.attributes[2].bufferIndex = 0;
    vd.layouts[0].stride = sizeof(Vertex);
    d.vertexDescriptor = vd;

    _pipeline = [_device newRenderPipelineStateWithDescriptor:d error:&error];
    if (!_pipeline) {
        NSLog(@"Pipeline error: %@", error);
        abort();
    }

    MTLSamplerDescriptor *glyphSD = [MTLSamplerDescriptor new];
    glyphSD.minFilter = MTLSamplerMinMagFilterLinear;
    glyphSD.magFilter = MTLSamplerMinMagFilterLinear;
    glyphSD.sAddressMode = MTLSamplerAddressModeClampToEdge;
    glyphSD.tAddressMode = MTLSamplerAddressModeClampToEdge;
    _glyphSampler = [_device newSamplerStateWithDescriptor:glyphSD];

    MTLSamplerDescriptor *flareSD = [MTLSamplerDescriptor new];
    flareSD.minFilter = MTLSamplerMinMagFilterLinear;
    flareSD.magFilter = MTLSamplerMinMagFilterLinear;
    flareSD.sAddressMode = MTLSamplerAddressModeClampToEdge;
    flareSD.tAddressMode = MTLSamplerAddressModeClampToEdge;
    _flareSampler = [_device newSamplerStateWithDescriptor:flareSD];
}

- (void)setupStateForSize:(int)w height:(int)h {
    _textX = (int)std::ceil(kTextY * ((float)w / (float)h));
    if (_textX & 1) _textX++;
    if (_textX < 90) _textX = 90;

    _speeds.assign(_textX, 0);
    _glyphs.assign(_textX * kTextY, Glyph{0, 253, 0});
    for (Glyph &g : _glyphs) {
        g.num = rand() % 60;
    }

    for (int i = 0; i < _textX; i++) {
        _speeds[i] = rand() & 1;
        if (i && _speeds[i] == _speeds[i - 1]) _speeds[i] = 2;
    }

    _picOffset = (kRTextX * kTextY) * (rand() % kNumPics);
}

- (id<MTLTexture>)makeTextureW:(int)w h:(int)h bytes:(const uint8_t *)bytes {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm width:w height:h mipmapped:NO];
    id<MTLTexture> tex = [_device newTextureWithDescriptor:d];
    [tex replaceRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0 withBytes:bytes bytesPerRow:w];
    return tex;
}

- (void)setupTextures {
    std::vector<uint8_t> fontGreen(512 * 256);
    for (int i = 0; i < 512 * 256; i++) {
        fontGreen[i] = (uint8_t)std::min(255, (int)font[i] + 20);
    }

    uint8_t flare[16] = {
        0, 0, 0, 0,
        0, 180, 180, 0,
        0, 180, 180, 0,
        0, 0, 0, 0
    };

    _fontTexGreen = [self makeTextureW:512 h:256 bytes:fontGreen.data()];
    _flareTex = [self makeTextureW:4 h:4 bytes:flare];
}

- (void)warmup {
    for (int i = 0; i < 500; i++) {
        [self makeChange];
        [self scrollState];
    }
}

- (void)makeChange {
    for (int i = 0; i < _rainIntensity; i++) {
        int r = rand() % (_textX * kTextY);
        _glyphs[r].num = rand() % 60;

        r = rand() % (_textX * 5);
        if (r < _textX && _glyphs[r].alpha != 0) _glyphs[r].alpha = 255;
    }
}

- (void)scrollState {
    static bool odd = false;
    odd = !odd;

    for (int speed = odd ? 1 : 0; speed <= 2; speed++) {
        int col = 0;
        for (int i = _textX * kTextY - 1; i >= _textX; i--) {
            if (_speeds[col] >= speed) _glyphs[i].alpha = _glyphs[i - _textX].alpha;
            if (++col >= _textX) col = 0;
        }
    }

    for (int i = 0; i < _textX; i++) _glyphs[i].alpha = 253;

    int col = 0;
    for (int i = (_textX * kTextY) / 2; i < (_textX * kTextY); i++) {
      if (_glyphs[i].alpha == 255) _glyphs[col].alpha = _glyphs[col + _textX].alpha >> 1;
      if (++col >= _textX) col = 0;
    }

    if (!_classic) {
        _timer++;
        if (_timer < 250) {
            _picFade += 3;
            if (_picFade > 255) _picFade = 255;
        } else {
            _picFade -= 3;
            if (_picFade < 0) _picFade = 0;
            if (_picOffset == (kNumPics + 1) * (kRTextX * kTextY)) {
                _picOffset += kRTextX * kTextY;
                _timer = 120;
            }
        }

        if (_timer > 400) {
            _picOffset += kRTextX * kTextY;
            _picOffset %= (kRTextX * kTextY) * kNumPics;
            _timer = 0;
        }
    }
}

- (void)addQuadX0:(float)x0 y0:(float)y0 x1:(float)x1 y1:(float)y1 z:(float)z
               u0:(float)u0 v0:(float)v0 u1:(float)u1 v1:(float)v1
               r:(float)r g:(float)g b:(float)b a:(float)a
            width:(float)w height:(float)h {
    float aspect = w / h;
    const float f = 1.0f / std::tan(45.0f * (float)M_PI / 360.0f);

    auto proj = [&](float x, float y) {
        float vz = z - 89.0f;
        float nx = (x * f / aspect) / -vz;
        float ny = (y * f) / -vz;
        return std::pair<float, float>(nx, ny);
    };

    auto p0 = proj(x0, y0);
    auto p1 = proj(x1, y0);
    auto p2 = proj(x1, y1);
    auto p3 = proj(x0, y1);

    Vertex v0a{p0.first, p0.second, u0, v0, r, g, b, a};
    Vertex v1a{p1.first, p1.second, u1, v0, r, g, b, a};
    Vertex v2a{p2.first, p2.second, u1, v1, r, g, b, a};
    Vertex v3a{p3.first, p3.second, u0, v1, r, g, b, a};

    _verts.push_back(v0a);
    _verts.push_back(v1a);
    _verts.push_back(v2a);
    _verts.push_back(v0a);
    _verts.push_back(v2a);
    _verts.push_back(v3a);
}

- (void)buildPass1WithWidth:(float)w height:(float)h {
    int b = 0;
    int i = 0;
    for (int y = kTextY / 2; y > -kTextY / 2; y--) {
        for (int x = -_textX / 2; x < _textX / 2; x++, i++) {
            int light = clampi(_glyphs[i].alpha + _picFade, 0, 255);
            int depth = 0;
            if (x >= -kRTextX / 2 && x < kRTextX / 2) {
                depth = clampi(pic[b + _picOffset] + (_picFade - 255), 0, 255);
                b++;
                /* Keep streams readable while depth images are active. */
                light -= depth;
                if (light < 0) light = 0;
                int floorLight = clampi((int)_glyphs[i].alpha / 3, 20, 110);
                if (light < floorLight) light = floorLight;
            }

            _glyphs[i].z = (float)(255 - depth) / 32.0f;
            float u0, v0, u1, v1;
            [self glyphUVForNum:_glyphs[i].num u0:&u0 v0:&v0 u1:&u1 v1:&v1];
            float a = (float)light / 255.0f;
            [self addQuadX0:(float)x y0:(float)y x1:(float)x + 1 y1:(float)y - 1 z:_glyphs[i].z
                         u0:u0 v0:v0 u1:u1 v1:v1
                         r:0.2f g:0.95f b:0.35f a:a width:w height:h];
        }
    }
}

- (void)buildPass2WithMode:(int)mode width:(float)w height:(float)h {
    std::vector<int> chosenRows(_textX, -1);

    /* Single deterministic tip per column: bottom-most high-intensity edge. */
    for (int cx = 0; cx < _textX; cx++) {
        for (int row = 0; row < kTextY - 1; row++) {
            int i = row * _textX + cx;
            if (_glyphs[i].alpha >= 252 && _glyphs[i + _textX].alpha == 0) {
                chosenRows[cx] = row;
            }
        }
    }

    /* Strong neighborhood suppression: keep only isolated heads. */
    std::vector<char> keep(_textX, 1);
    for (int cx = 0; cx < _textX; cx++) {
        if (chosenRows[cx] < 0) continue;
        for (int nx = std::max(0, cx - 2); nx <= std::min(_textX - 1, cx + 2); nx++) {
            if (nx == cx || chosenRows[nx] < 0) continue;
            if (std::abs(chosenRows[nx] - chosenRows[cx]) <= 3) {
                if (nx < cx) {
                    keep[cx] = 0;
                    break;
                }
            }
        }
    }

    for (int cx = 0; cx < _textX; cx++) {
        int chosenRow = chosenRows[cx];
        if (chosenRow < 0 || !keep[cx]) continue;

        int i = chosenRow * _textX + cx;
        int x = cx - (_textX / 2);
        int y = (kTextY / 2 - 1) - chosenRow;
        float u0, v0, u1, v1;
        [self glyphUVForNum:_glyphs[i].num u0:&u0 v0:&v0 u1:&u1 v1:&v1];
        if (!mode) {
            [self addQuadX0:(float)x y0:(float)y x1:(float)x + 1 y1:(float)y - 1 z:_glyphs[i].z
                         u0:u0 v0:v0 u1:u1 v1:v1
                         r:0.84f g:1.0f b:0.52f a:1.9f width:w height:h];
        } else {
            [self addQuadX0:(float)x - 0.12f y0:(float)y + 0.12f x1:(float)x + 1.12f y1:(float)y - 1.12f z:_glyphs[i].z
                         u0:u0 v0:v0 u1:u1 v1:v1
                         r:0.62f g:1.0f b:0.42f a:0.68f width:w height:h];
            [self addQuadX0:(float)x - 0.24f y0:(float)y + 0.24f x1:(float)x + 1.24f y1:(float)y - 1.24f z:_glyphs[i].z
                         u0:u0 v0:v0 u1:u1 v1:v1
                         r:0.46f g:1.0f b:0.34f a:0.30f width:w height:h];
        }
    }
}

- (void)drawInMTKView:(MTKView *)view {
    if (!_paused) {
        _updateTick++;
        if (_updateTick >= _updateDivider) {
            _updateTick = 0;
            [self makeChange];
            [self scrollState];
        }
    }

    id<CAMetalDrawable> drawable = view.currentDrawable;
    MTLRenderPassDescriptor *rpd = view.currentRenderPassDescriptor;
    if (!drawable || !rpd) return;

    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rpd];
    [enc setRenderPipelineState:_pipeline];

    _verts.clear();
    [self buildPass1WithWidth:view.drawableSize.width height:view.drawableSize.height];
    NSUInteger size = _verts.size() * sizeof(Vertex);
    if (!_vertexBuffer || _vertexBuffer.length < size) {
        _vertexBuffer = [_device newBufferWithLength:std::max((NSUInteger)4096, size) options:MTLResourceStorageModeShared];
    }
    memcpy(_vertexBuffer.contents, _verts.data(), size);
    [enc setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
    [enc setFragmentSamplerState:_glyphSampler atIndex:0];
    [enc setFragmentTexture:_fontTexGreen atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:(NSUInteger)_verts.size()];

    _verts.clear();
    [self buildPass2WithMode:0 width:view.drawableSize.width height:view.drawableSize.height];
    size = _verts.size() * sizeof(Vertex);
    if (_vertexBuffer.length < size) {
        _vertexBuffer = [_device newBufferWithLength:size options:MTLResourceStorageModeShared];
    }
    memcpy(_vertexBuffer.contents, _verts.data(), size);
    [enc setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
    [enc setFragmentSamplerState:_glyphSampler atIndex:0];
    [enc setFragmentTexture:_fontTexGreen atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:(NSUInteger)_verts.size()];

    _verts.clear();
    [self buildPass2WithMode:1 width:view.drawableSize.width height:view.drawableSize.height];
    size = _verts.size() * sizeof(Vertex);
    if (_vertexBuffer.length < size) {
        _vertexBuffer = [_device newBufferWithLength:size options:MTLResourceStorageModeShared];
    }
    memcpy(_vertexBuffer.contents, _verts.data(), size);
    [enc setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
    [enc setFragmentSamplerState:_glyphSampler atIndex:0];
    [enc setFragmentTexture:_fontTexGreen atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:(NSUInteger)_verts.size()];

    [enc endEncoding];
    [cb presentDrawable:drawable];
    [cb commit];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    (void)view;
    [self setupStateForSize:(int)size.width height:(int)size.height];
}

- (void)toggleClassic { _classic = !_classic; _picFade = 0; }
- (void)togglePause { _paused = !_paused; }
- (void)nextPicture {
    if (_classic || _paused) return;
    _picOffset += kRTextX * kTextY;
    _picOffset %= (kRTextX * kTextY) * kNumPics;
    _timer = 0;
}

@end

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

        MatrixRenderer *renderer = [MatrixRenderer new];
        MTKView *view = [[MTKView alloc] initWithFrame:frame device:MTLCreateSystemDefaultDevice()];
        view.clearColor = MTLClearColorMake(0, 0, 0, 1);
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
