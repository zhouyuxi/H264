//
//  ViewController.m
//  CC_VideoToolBoxLearning_1
//
//  Created by CC老师 on 2017/6/26.
//  Copyright © 2017年 Miss CC. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>


@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate>

@property(nonatomic,strong)UILabel *cLabel;
@property(nonatomic,strong)AVCaptureSession *cCapturesession;
@property(nonatomic,strong)AVCaptureDeviceInput *cCaptureDeviceInput;
@property(nonatomic,strong)AVCaptureVideoDataOutput *cCaptureDataOutput;
@property(nonatomic,strong)AVCaptureVideoPreviewLayer *cPreviewLayer;

@end

@implementation ViewController
{
    int  frameID; //帧ID 每一张图片都有一个session
    dispatch_queue_t cCaptureQueue; //捕获队列
    dispatch_queue_t cEncodeQueue; //编码队列
    VTCompressionSessionRef cEncodeingSession; // 设置参数
    CMFormatDescriptionRef format; // 编码的格式
    NSFileHandle *fileHandele; //形成h264文件
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    //基础UI实现
    _cLabel = [[UILabel alloc]initWithFrame:CGRectMake(20, 20, 200, 100)];
    _cLabel.text = @"cc课堂之H.264硬编码";
    _cLabel.textColor = [UIColor redColor];
    [self.view addSubview:_cLabel];
    
    UIButton *cButton = [[UIButton alloc]initWithFrame:CGRectMake(200, 20, 100, 100)];
    [cButton setTitle:@"play" forState:UIControlStateNormal];
    [cButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [cButton setBackgroundColor:[UIColor orangeColor]];
    [cButton addTarget:self action:@selector(buttonClick:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:cButton];
}


-(void)buttonClick:(UIButton *)button
{
    if (!_cCapturesession || !_cCapturesession.isRunning ) {
        
        [button setTitle:@"Stop" forState:UIControlStateNormal];
        [self startCapture];
        
        
    }else
    {
        [button setTitle:@"Play" forState:UIControlStateNormal];
        [self stopCapture];
    }

}

//开始捕捉
- (void)startCapture
{
    self.cCapturesession = [[AVCaptureSession alloc]init];
    
    self.cCapturesession.sessionPreset = AVCaptureSessionPreset640x480;
    
    cCaptureQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    cEncodeQueue  = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    AVCaptureDevice *inputCamera = nil;
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {

        if ([device position] == AVCaptureDevicePositionBack) {
            
            inputCamera = device;
        }
    }
    
    self.cCaptureDeviceInput = [[AVCaptureDeviceInput alloc]initWithDevice:inputCamera error:nil];
    
    if ([self.cCapturesession canAddInput:self.cCaptureDeviceInput]) {
        
        [self.cCapturesession addInput:self.cCaptureDeviceInput];
        
        
    }
    
    self.cCaptureDataOutput = [[AVCaptureVideoDataOutput alloc]init];

    [self.cCaptureDataOutput setAlwaysDiscardsLateVideoFrames:NO];
    
    [self.cCaptureDataOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    
    [self.cCaptureDataOutput setSampleBufferDelegate:self queue:cCaptureQueue];
    
    if ([self.cCapturesession canAddOutput:self.cCaptureDataOutput]) {
        
        [self.cCapturesession addOutput:self.cCaptureDataOutput];
    }
    
    AVCaptureConnection *connection = [self.cCaptureDataOutput connectionWithMediaType:AVMediaTypeVideo];
    
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    
    self.cPreviewLayer = [[AVCaptureVideoPreviewLayer alloc]initWithSession:self.cCapturesession];

    [self.cPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
    
    [self.cPreviewLayer setFrame:self.view.bounds];
    
    [self.view.layer addSublayer:self.cPreviewLayer];
    
    NSString *filePath = [NSHomeDirectory()stringByAppendingPathComponent:@"/Documents/cc_video.h264"];

    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    
    BOOL createFile = [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
    if (!createFile) {
        
        NSLog(@"create file failed");
    }else
    {
        NSLog(@"create file success");
    }
    
    NSLog(@"filePaht = %@",filePath);
    fileHandele = [NSFileHandle fileHandleForWritingAtPath:filePath];
    
    //初始化videoToolbBox
    [self initVideoToolBox];
    
    //开始捕捉
    [self.cCapturesession startRunning];
}


//停止捕捉
- (void)stopCapture
{
    [self.cCapturesession stopRunning];
    
    [self.cPreviewLayer removeFromSuperlayer];
    
    [self endVideoToolBox];
    
    [fileHandele closeFile];
    
    fileHandele = NULL;
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    dispatch_sync(cEncodeQueue, ^{
        [self encode:sampleBuffer];
    });
    
}


//初始化videoToolBox
-(void)initVideoToolBox
{
    dispatch_sync(cEncodeQueue, ^{
        frameID = 0;
        int width = 400,height = 480; //像素
        
        // 创建session
        OSStatus status = VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, didCompressH264, (__bridge void *)(self),&cEncodeingSession);
        
        if (status != 0) {
            return ;
        }
        
        // 设置实时编码输出
        VTSessionSetProperty(cEncodeingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        VTSessionSetProperty(cEncodeingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
        
        // 设置关键帧间隔
        int frameInterval = 10;
        CFNumberRef frameIntervalRaf = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
        VTSessionSetProperty(cEncodeingSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRaf);
        
        // 设置期望帧率，不是实际帧率
        int fps = 10;
        CFNumberRef fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &fps);
        VTSessionSetProperty(cEncodeingSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
        
        // 设置码率、均值、单位byte
        int bigRateLimit = width *height * 3 *4;
        CFNumberRef bitRateLimitRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bigRateLimit);
        VTSessionSetProperty(cEncodeingSession, kVTCompressionPropertyKey_DataRateLimits, bitRateLimitRef);
        
        // 开始编码
        VTCompressionSessionPrepareToEncodeFrames(cEncodeingSession);
        
    });
}


//编码
- (void)encode:(CMSampleBufferRef )sampleBuffer
{
    // 1 拿到每一帧数据
    CVImageBufferRef imageBuffer  = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    // 2 设置时间
    // 编码
    CMTime pTime = CMTimeMake(frameID ++, 1000);
    VTEncodeInfoFlags flags;
    OSStatus status = VTCompressionSessionEncodeFrame(cEncodeingSession, imageBuffer, pTime, kCMTimeInvalid, NULL, NULL, &flags);
    
    
    // 将数据形成H264文件->推流 H264码流中第一个流是SPS&PPS
    if (status != noErr) {
        VTCompressionSessionInvalidate(cEncodeingSession);
        CFRelease(cEncodeingSession);
        cEncodeingSession = NULL;
        return;
    }
    
}


//编码完成回调
void didCompressH264(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer)
{
    // 状态
    if (status != 0) {
        return;
    }
    
    // 没准备好
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        return;
    }
    
    ViewController *encoder = (__bridge ViewController *)outputCallbackRefCon;
    
    // 判断当前帧是否为关键帧
    bool  keyFrame = !CFDictionaryContainsKey(CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0), kCMSampleAttachmentKey_NotSync);
    
    // pps,sps
    
    if (keyFrame) {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        
        //sps
        
        size_t spsSize,spsCount;
        const uint8_t *spsSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &spsSet, &spsSize, &spsCount, 0);
        
        if (statusCode == noErr) {
            //pps
            size_t ppsSize,ppsCount;
            const uint8_t *ppsSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &ppsSet, &ppsSize, &ppsCount, 0);
            
            if (statusCode == noErr) {
                // pps,sps写入文件
                NSData *spsData = [NSData dataWithBytes:spsSet length:spsSize];
                NSData *ppsData = [NSData dataWithBytes:ppsSet length:ppsSize];
                
                [encoder gotSpsPps:spsData pps:ppsData];
            }
        }
    }
    
    
    // 将流数据写入H264文件
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length,totolLength;
    char *dataPointer;
    OSStatus statusCodeRef = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totolLength, &dataPointer);
    if (statusCodeRef == noErr) {
        size_t bufferOffset = 0;
        static const int AVH = 4;
        //循环获取数据
        
        while (bufferOffset < totolLength - AVH) {
            uint32_t NAlength = 0;
            memcpy(&NAlength, dataPointer+bufferOffset,AVH);
            // 大端模式转系统端模式
            NAlength = CFSwapInt32BigToHost(NAlength);
            // 获取数据
            NSData *data = [[NSData alloc] initWithBytes:dataPointer + bufferOffset + AVH length:NAlength];
            
            // 拿到数据写入文件
            [encoder gotEncodedData:data isKeyFrame:keyFrame];
        }
    }
}

// 让sps 和 pps前面插入一个间隔 00 00 00 01
- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps
{
    NSLog(@"%d-- %d",(int)[sps length],(int)[pps length]);
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1;
    NSData *BythHeader = [NSData dataWithBytes:bytes length:length];
    
     [fileHandele writeData:BythHeader];
     [fileHandele writeData:sps];
     [fileHandele writeData:BythHeader];
     [fileHandele writeData:pps];
}


- (void)gotEncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame
{
    NSLog(@"%d",(int)[data length]);
    if (fileHandele != NULL) {
        const char bytes[]="\x00\x00\x00\x01";
        // 长度
        size_t length = (sizeof bytes) - 1;
        // 头字节
         NSData *BythHeader = [NSData dataWithBytes:bytes length:length];
        // 写入头字节
         [fileHandele writeData:BythHeader];
        // 写入H264文件
         [fileHandele writeData:data];
    }
    
}

//结束VideoToolBox
-(void)endVideoToolBox
{
    VTCompressionSessionCompleteFrames(cEncodeingSession, kCMTimeInvalid);
    VTCompressionSessionInvalidate(cEncodeingSession);
    CFRelease(cEncodeingSession);
    cEncodeingSession = NULL;
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
