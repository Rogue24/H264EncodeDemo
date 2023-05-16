//
//  VideoCaptureViewController.m
//  H264EncodeDemo
//
//  Created by 周健平 on 2023/5/15.
//

#import "VideoCaptureViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "JPH264Encoder.h"

@interface VideoCaptureViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (weak, nonatomic) IBOutlet UIView *contentView;
@property (weak, nonatomic) IBOutlet UIView *previewView;

@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) JPH264Encoder *encoder;

@property (nonatomic, assign) BOOL isAppear;
@property (nonatomic, assign) BOOL isBegin;
@end

@implementation VideoCaptureViewController

+ (VideoCaptureViewController *)build {
    VideoCaptureViewController *vc = [[UIStoryboard storyboardWithName:@"Main" bundle:nil] instantiateViewControllerWithIdentifier:@"VideoCaptureViewController"];
    vc.modalPresentationStyle = UIModalPresentationCustom;
    return vc;
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.previewView.hidden = YES;
    
    // ================== 采集视频 ==================
    // 1.创建session
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    session.sessionPreset = AVCaptureSessionPreset1280x720;
    self.session = session;
    
    // 2.设置视频的输入
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo]; // 默认是后置摄像头
    NSError *error;
    AVCaptureDeviceInput *input = [[AVCaptureDeviceInput alloc] initWithDevice:device error:&error];
    [session addInput:input];
    
    // 3.设置视频的输出
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    dispatch_queue_t queue = dispatch_queue_create("SERIAL", DISPATCH_QUEUE_SERIAL);
    [output setSampleBufferDelegate:self queue:queue];
    [output setAlwaysDiscardsLateVideoFrames:YES]; // 抛弃延迟的帧，节省内存，默认YES
    [session addOutput:output];
    
    // 视频输出方向
    // 注意：设置方向，必须在将output添加到session之后才有效
    AVCaptureConnection *connection = [output connectionWithMediaType:AVMediaTypeVideo];
    if (connection.isVideoOrientationSupported) {
        connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    } else {
        NSLog(@"不支持设置方向");
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if (self.isAppear) return;
    self.isAppear = YES;
    
    // 添加预览图层
    AVCaptureVideoPreviewLayer *layer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    layer.frame = self.previewView.bounds;
    [self.previewView.layer addSublayer:layer];
    
    // 开始采集
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self.session startRunning];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIView transitionWithView:self.previewView duration:0.5 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
                self.previewView.hidden = NO;
            } completion:nil];
        });
    });
}

#pragma mark - button action

- (IBAction)startCapture {
    if (self.encoder) {
        NSLog(@"已经开始了");
        return;
    }
    self.encoder = [[JPH264Encoder alloc] init];
    [self.encoder prepareEncodeWithWidth:720 height:1280];
}

- (IBAction)stopCapture {
    self.view.userInteractionEnabled = NO;
    [self.encoder endEncode];
    [self dismissViewControllerAnimated:YES completion:^{
        [self.session stopRunning];
    }];
}

#pragma mark - <AVCaptureVideoDataOutputSampleBufferDelegate>

// 出现丢帧就会调用该方法，给出丢失的帧
- (void)captureOutput:(AVCaptureOutput *)output didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    NSLog(@"丢失的视频画面");
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
//    NSLog(@"采集到视频画面");
    [self.encoder encodeFrame:sampleBuffer];
}

@end
