

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <GLKit/GLKit.h>
#import "OpenGLView.h"
#import <Accelerate/Accelerate.h>
#define kScreenWidth [UIScreen mainScreen].bounds.size.width
#define kScreenHeight [UIScreen mainScreen].bounds.size.height
#define currentResolutionW 1920
#define currentResolutionH 1080

@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate>
@property(nonatomic, strong)AVCaptureSession *session;
@property(nonatomic, strong)AVCaptureDeviceInput *videoInput;
@property(nonatomic, strong)AVCaptureDevice *videoDevice;
@property(nonatomic, strong)AVCaptureDevice *audioDevice;
@property(nonatomic, strong)AVCaptureDeviceInput *audioInput;

@property(nonatomic, strong)AVCaptureVideoDataOutput *videoOutput;
@property(nonatomic, strong)AVCaptureAudioDataOutput *audioOutput;

@property(nonatomic, strong)AVCaptureConnection *captureConnection;

@property(nonatomic, strong)AVCaptureMovieFileOutput *captureMovieFileOutput;

@property(nonatomic,strong)CAEAGLLayer *myEagLayer;
@property(nonatomic,strong)EAGLContext *myContext;
@property(nonatomic,assign)GLuint myProgram;
@property(nonatomic,assign)GLuint myColorRenderBuffer;
@property(nonatomic,assign)GLuint myColorFrameBuffer;

@property (nonatomic, strong)  OpenGLView *mGLView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    

    self.mGLView = (OpenGLView *)self.view;
    [self.mGLView setupGL];
    
    [self initAVCaptureSession];

    
    AVCaptureVideoPreviewLayer *previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    previewLayer.frame = CGRectMake(0, 0, self.view.frame.size.width/2, self.view.frame.size.height);
    [self.view.layer  addSublayer:previewLayer];
    
    [self.session startRunning];

}

///初始化会话管理对象
- (void)initAVCaptureSession {
    //初始化
    self.session = [[AVCaptureSession alloc] init];

// 设置分辨率
      if ([self.session canSetSessionPreset:AVCaptureSessionPresetHigh]){
          [self.session setSessionPreset:AVCaptureSessionPresetHigh];
      } else{
          [self.session setSessionPreset:AVCaptureSessionPreset1280x720];
      }

    /**
     注意: 配置AVCaptureSession 的时候, 必须先开始配置, beginConfiguration, 配置完成, 必须提交配置 commitConfiguration, 否则配置无效
     **/

    //开始配置
    [self.session beginConfiguration];

    // 设置视频 I/O 对象 并添加到session
    [self videoInputAndOutput];

    // 设置音频 I/O 对象 并添加到session
    [self audioInputAndOutput];

    // 提交配置
    [self.session commitConfiguration];

}

- (void)videoInputAndOutput{
    // 初始化视频设备对象
    self.videoDevice = nil;

    //获取视频设备管理对象 (由于分为前置摄像头 和 后置摄像头 所以返回的是数组)
    AVCaptureDeviceDiscoverySession *disSession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
        
    NSArray *videoDevices = disSession.devices;
    for (AVCaptureDevice *device in videoDevices) {
        ///默认先开启前置摄像头
        if (device.position == AVCaptureDevicePositionFront) {
            self.videoDevice = device;
        }
    }


    //视频输入
    //根据视频设备来初始化视频输入对象
    NSError *error;
    self.videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:self.videoDevice error:&error];
    if (error) {
        NSLog(@" 摄像头错误 ");
        return;
    }

    // 将输入对象添加到管理者 AVCaptureSession 中
    // 需要先判断是否能够添加输入对象
    if ([self.session canAddInput:self.videoInput]) {
        [self.session addInput:self.videoInput];
    }
    
    //视频输出对象
    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    //是否允许卡顿时丢帧
    self.videoOutput.alwaysDiscardsLateVideoFrames = NO;

    if ([self supportsFastTextureUpload]) {
        // 是否支持全频色彩编码 YUV 一种色彩编码方式, 即YCbCr, 现在视频一般采用该颜色空间, 可以分离亮度跟色彩, 在不影响清晰度的情况下来压缩视频
        BOOL supportFullYUVRange = NO;
        
        // 获取输出对象所支持的像素格式
        NSArray *supportedPixelFormats = self.videoOutput.availableVideoCVPixelFormatTypes;
        for (NSNumber *currentPixelFormat in supportedPixelFormats) {
            if ([currentPixelFormat integerValue] == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
                supportFullYUVRange = YES;
            }
        }
        
        // 根据是否支持全频色彩编码 YUV 来设置输出对象的视频像素压缩格式
        if (supportFullYUVRange) {
            [self.videoOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
        } else {
            [self.videoOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
        }
    } else {
        [self.videoOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    }

    // 创建设置代理是所需要的线程队列 优先级设为高
    dispatch_queue_t videoQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    // 设置代理
    [self.videoOutput setSampleBufferDelegate:self queue:videoQueue];

    // 判断session 是否可添加视频输出对象
    if ([self.session canAddOutput:self.videoOutput]) {
        [self.session addOutput:self.videoOutput];
        
        // 链接视频 I/O 对象
        [self connectionVideoInputVideoOutput];
    }
}

- (void)audioInputAndOutput{
    // 初始音频设备对象
    self.audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];

    // 音频输入对象
    NSError *error;
    self.audioInput = [[AVCaptureDeviceInput alloc] initWithDevice:self.audioDevice error:&error];
    if (error) {
        NSLog(@"== 录音设备出错  %@", error);
    }

    // 判断session 是否可以添加 音频输入对象
    if ([self.session canAddInput:self.audioInput]) {
        [self.session addInput:self.audioInput];
    }

    // 音频输出对象
    self.audioOutput = [[AVCaptureAudioDataOutput alloc] init];

    // 判断是否可以添加音频输出对象
    if ([self.session canAddOutput:self.audioOutput]) {
        [self.session addOutput:self.audioOutput];
    }
}

- (void)connectionVideoInputVideoOutput{
    //设置链接管理对象
     AVCaptureConnection *captureConnection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
     self.captureConnection = captureConnection;
     //
    [captureConnection setVideoOrientation:AVCaptureVideoOrientationPortraitUpsideDown];

     captureConnection.videoScaleAndCropFactor = captureConnection.videoMaxScaleAndCropFactor;
     //视频稳定设置
     if ([captureConnection isVideoStabilizationSupported]){
         captureConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
     }
}

- (BOOL)supportsFastTextureUpload{
    return YES;
}


#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
// 获取帧数据
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // captureSession 会话如果没有强引用,这里不会得到执行

    //1.从sampleBuffer 获取视频像素缓存区对象
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);

    //2.获取捕捉视频的宽和高
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);

    CMSampleBufferRef cropSampleBuffer;
    CFRetain(sampleBuffer);
    cropSampleBuffer = [self cropSampleBufferByHardware:sampleBuffer];
    dispatch_async(dispatch_get_main_queue(), ^{
        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(cropSampleBuffer);
        [self.mGLView displayPixelBuffer:pixelBuffer];
        CFRelease(sampleBuffer);
    });
    CFRelease(cropSampleBuffer);
}

// hardware crop
- (CMSampleBufferRef)cropSampleBufferByHardware:(CMSampleBufferRef)buffer {
    // a CMSampleBuffer's CVImageBuffer of media data.
    int _cropX = 0 ;
    int _cropY = 0 ;
    CGFloat g_width_size = 1080/4;//1280;
    CGFloat g_height_size = 1920/4;//720;
    CGRect cropRect    = CGRectMake(_cropX, _cropY, g_width_size, g_height_size);
    //        log4cplus_debug("Crop", "dropRect x: %f - y : %f - width : %zu - height : %zu", cropViewX, cropViewY, width, height);
    
    /*
     First, to render to a texture, you need an image that is compatible with the OpenGL texture cache. Images that were created with the camera API are already compatible and you can immediately map them for inputs. Suppose you want to create an image to render on and later read out for some other processing though. You have to have create the image with a special property. The attributes for the image must have kCVPixelBufferIOSurfacePropertiesKey as one of the keys to the dictionary.
      如果要进行页面渲染,需要一个和OpenGL缓冲兼容的图像。用相机API创建的图像已经兼容,您可以马上映射他们进行输入。假设你从已有画面中截取一个新的画面,用作其他处理,你必须创建一种特殊的属性用来创建图像。对于图像的属性必须有kCVPixelBufferIOSurfacePropertiesKey 作为字典的Key.因此以下步骤不可省略
     */
    
    OSStatus status;
    
    /* Only resolution has changed we need to reset pixBuffer and videoInfo so that reduce calculate count */
    static CVPixelBufferRef            pixbuffer = NULL;
    static CMVideoFormatDescriptionRef videoInfo = NULL;
    
    if (pixbuffer == NULL) {
        NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                                 [NSNumber numberWithInt:g_width_size],     kCVPixelBufferWidthKey,
                                 [NSNumber numberWithInt:g_height_size],    kCVPixelBufferHeightKey, nil];
        
        CFDictionaryRef empty; // empty value for attr value.
        CFMutableDictionaryRef attrs;
        empty = CFDictionaryCreate(kCFAllocatorDefault, // our empty IOSurface properties dictionary
                                   NULL,
                                   NULL,
                                   0,
                                   &kCFTypeDictionaryKeyCallBacks,
                                   &kCFTypeDictionaryValueCallBacks);
        attrs = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                          1,
                                          &kCFTypeDictionaryKeyCallBacks,
                                          &kCFTypeDictionaryValueCallBacks);

        CFDictionarySetValue(attrs,
                             kCVPixelBufferIOSurfacePropertiesKey,
                             empty);
        status = CVPixelBufferCreate(kCFAllocatorSystemDefault, g_width_size, g_height_size, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attrs/*(__bridge CFDictionaryRef)options*/, &pixbuffer);
        // ensures that the CVPixelBuffer is accessible in system memory. This should only be called if the base address is going to be used and the pixel data will be accessed by the CPU
        if (status != noErr) {
            NSLog(@"Crop CVPixelBufferCreate error %d",(int)status);
            return NULL;
        }
    }
    
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(buffer);
    
    CIImage *ciImage = [CIImage imageWithCVImageBuffer:imageBuffer];
    ciImage = [ciImage imageByCroppingToRect:cropRect];
    // Ciimage get real image is not in the original point  after excute crop. So we need to pan.
    ciImage = [ciImage imageByApplyingTransform:CGAffineTransformMakeTranslation(-_cropX, -_cropY)];
    
    static CIContext *ciContext = nil;
    if (ciContext == nil) {
                NSMutableDictionary *options = [[NSMutableDictionary alloc] init];
                [options setObject:[NSNull null] forKey:kCIContextWorkingColorSpace];
                [options setObject:@0            forKey:kCIContextUseSoftwareRenderer];
        EAGLContext *eaglContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
        ciContext = [CIContext contextWithEAGLContext:eaglContext options:options];
    }
        [ciContext render:ciImage toCVPixelBuffer:pixbuffer bounds:cropRect colorSpace:nil];
    
    CMSampleTimingInfo sampleTime = {
        .duration               = CMSampleBufferGetDuration(buffer),
        .presentationTimeStamp  = CMSampleBufferGetPresentationTimeStamp(buffer),
        .decodeTimeStamp        = CMSampleBufferGetDecodeTimeStamp(buffer)
    };
    
    if (videoInfo == NULL) {
        status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixbuffer, &videoInfo);
        if (status != 0) NSLog(@"Crop CMVideoFormatDescriptionCreateForImageBuffer error %d",(int)status);
    }
    
    CMSampleBufferRef cropBuffer;
    status = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixbuffer, true, NULL, NULL, videoInfo, &sampleTime, &cropBuffer);
    if (status != 0) NSLog(@"Crop CMSampleBufferCreateForImageBuffer error %d",(int)status);
    
    return cropBuffer;
}
- (CMSampleBufferRef)cropSampleBufferBySoftware:(CMSampleBufferRef)sampleBuffer {
    OSStatus status;
    int _cropX = 320    ;
    int _cropY = 180;
    CGFloat g_width_size = 1280;
    CGFloat g_height_size = 720;
    
    
    //    CVPixelBufferRef pixelBuffer = [self modifyImage:buffer];
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // Lock the image buffer
    CVPixelBufferLockBaseAddress(imageBuffer,0);
    // Get information about the image
    uint8_t *baseAddress     = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
    size_t  bytesPerRow      = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t  width            = CVPixelBufferGetWidth(imageBuffer);
    // size_t  height           = CVPixelBufferGetHeight(imageBuffer);
    NSInteger bytesPerPixel  =  bytesPerRow/width;
    
    // YUV 420 Rule
    if (_cropX % 2 != 0) _cropX += 1;
    NSInteger baseAddressStart = _cropY*bytesPerRow+bytesPerPixel*_cropX;
    static NSInteger lastAddressStart = 0;
    lastAddressStart = baseAddressStart;
    
    // pixbuffer 与 videoInfo 只有位置变换或者切换分辨率或者相机重启时需要更新,其余情况不需要,Demo里只写了位置更新,其余情况自行添加
    // NSLog(@"demon pix first : %zu - %zu - %@ - %d - %d - %d -%d",width, height, self.currentResolution,_cropX,_cropY,self.currentResolutionW,self.currentResolutionH);
    static CVPixelBufferRef            pixbuffer = NULL;
    static CMVideoFormatDescriptionRef videoInfo = NULL;
    
    // x,y changed need to reset pixbuffer and videoinfo
    if (lastAddressStart != baseAddressStart) {
        if (pixbuffer != NULL) {
            CVPixelBufferRelease(pixbuffer);
            pixbuffer = NULL;
        }
        
        if (videoInfo != NULL) {
            CFRelease(videoInfo);
            videoInfo = NULL;
        }
    }
    
    if (pixbuffer == NULL) {
        NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                                 [NSNumber numberWithBool : YES],           kCVPixelBufferCGImageCompatibilityKey,
                                 [NSNumber numberWithBool : YES],           kCVPixelBufferCGBitmapContextCompatibilityKey,
                                 [NSNumber numberWithInt  : g_width_size],  kCVPixelBufferWidthKey,
                                 [NSNumber numberWithInt  : g_height_size], kCVPixelBufferHeightKey,
                                 nil];
        
        status = CVPixelBufferCreateWithBytes(kCFAllocatorDefault, g_width_size, g_height_size, kCVPixelFormatType_32BGRA, &baseAddress[baseAddressStart], bytesPerRow, NULL, NULL, (__bridge CFDictionaryRef)options, &pixbuffer);
        if (status != 0) {
            NSLog(@"Crop CVPixelBufferCreateWithBytes error %d",(int)status);
            return NULL;
        }
    }
    
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    CMSampleTimingInfo sampleTime = {
        .duration               = CMSampleBufferGetDuration(sampleBuffer),
        .presentationTimeStamp  = CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
        .decodeTimeStamp        = CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
    };
    
    if (videoInfo == NULL) {
        status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixbuffer, &videoInfo);
        if (status != 0) NSLog(@"Crop CMVideoFormatDescriptionCreateForImageBuffer error %d",(int)status);
    }
    
    CMSampleBufferRef cropBuffer = NULL;
    status = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixbuffer, true, NULL, NULL, videoInfo, &sampleTime, &cropBuffer);
    if (status != 0) NSLog(@"Crop CMSampleBufferCreateForImageBuffer error %d",(int)status);
    
    lastAddressStart = baseAddressStart;
    
    return cropBuffer;
}


- (CMSampleBufferRef)test:(CMSampleBufferRef)sampleBuffer{
    CGRect cropRect = CGRectMake(0, 0, 1280, 720);

    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:(CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer)]; //options: [NSDictionary dictionaryWithObjectsAndKeys:[NSNull null], kCIImageColorSpace, nil]];
    ciImage = [ciImage imageByCroppingToRect:cropRect];

    
    CFDictionaryRef empty; // empty value for attr value.
    CFMutableDictionaryRef attrs;
    empty = CFDictionaryCreate(kCFAllocatorDefault, // our empty IOSurface properties dictionary
                               NULL,
                               NULL,
                               0,
                               &kCFTypeDictionaryKeyCallBacks,
                               &kCFTypeDictionaryValueCallBacks);
    attrs = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                      1,
                                      &kCFTypeDictionaryKeyCallBacks,
                                      &kCFTypeDictionaryValueCallBacks);

    CFDictionarySetValue(attrs,
                         kCVPixelBufferIOSurfacePropertiesKey,
                         empty);
    
    
    CVPixelBufferRef pixelBuffer;
    CVPixelBufferCreate(kCFAllocatorSystemDefault, 1280, 720, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attrs, &pixelBuffer);

    CVPixelBufferLockBaseAddress( pixelBuffer, 0 );

    CIContext * ciContext = [CIContext contextWithOptions: nil];
    [ciContext render:ciImage toCVPixelBuffer:pixelBuffer];
    CVPixelBufferUnlockBaseAddress( pixelBuffer, 0 );

    CMSampleTimingInfo sampleTime = {
        .duration = CMSampleBufferGetDuration(sampleBuffer),
        .presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
        .decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
    };

    CMVideoFormatDescriptionRef videoInfo = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &videoInfo);

    CMSampleBufferRef oBuf;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, NULL, NULL, videoInfo, &sampleTime, &oBuf);
    
    return oBuf;
}
@end

