//
//  DXVAViewController.m
//  H264EncodeDemo
//
//  Created by 周健平 on 2023/5/15.
//

#import "DXVAViewController.h"
#import "AAPLEAGLLayer.h"
#import <VideoToolbox/VideoToolbox.h>

@interface DXVAViewController ()
@property (weak, nonatomic) IBOutlet UIView *contentView;
@property (weak, nonatomic) IBOutlet UIView *previewView;

@property (nonatomic, weak) CADisplayLink *displayLink;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign) VTDecompressionSessionRef decompressionSession;
@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDescription;
@property (nonatomic, weak) AAPLEAGLLayer *aapLayer;

@property (nonatomic, assign) BOOL isAppear;
@property (nonatomic, assign) BOOL isBegin;
@end

@implementation DXVAViewController
{
    // 读取到的数据
    long _inputMaxSize;
    long _inputSize;
    uint8_t *_inputBuffer;
    
    // 即将解析的数据
    long _packetSize;
    uint8_t *_packetBuffer;
    
    long _spsSize;
    uint8_t *_pSPS;
    
    long _ppsSize;
    uint8_t *_pPPS;
}

const char pStartCode[] = "\x00\x00\x00\x01";

+ (DXVAViewController *)build {
    DXVAViewController *vc = [[UIStoryboard storyboardWithName:@"Main" bundle:nil] instantiateViewControllerWithIdentifier:@"DXVAViewController"];
    vc.modalPresentationStyle = UIModalPresentationCustom;
    return vc;
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1.创建CADisplayLink
    CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateFrame)];
    displayLink.preferredFramesPerSecond = 24; // 设置一秒内更新24次
    [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    displayLink.paused = YES;
    self.displayLink = displayLink;
    
    // 2.创建NSInputStream
    self.inputStream = [NSInputStream inputStreamWithFileAtPath:JPH264Path];
    
    // 3.创建队列
    self.queue = dispatch_queue_create("DXVA", DISPATCH_QUEUE_SERIAL);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.isAppear) return;
    self.isAppear = YES;
    
    // 创建用于渲染的layer
    AAPLEAGLLayer *aapLayer = [[AAPLEAGLLayer alloc] initWithFrame:self.previewView.bounds];
    [self.previewView.layer addSublayer:aapLayer];
    self.aapLayer = aapLayer;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // 1.初始化一次读取多少数据，以及数据的长度，数据存放在哪里
        self->_inputMaxSize = 720 * 1280; // 这是在硬编码那里自定义的分辨率（一帧最多有的像素数），一次读这么多，保证至少能有一段完整的帧数据
        
        self->_inputSize = 0;
        
        // 申请内存
        self->_inputBuffer = malloc(self->_inputMaxSize);
        
        // 2.打开inputStream
        [self.inputStream open];
        
        // 3.开始读取数据
        self.displayLink.paused = NO;
    });
}

#pragma mark - button action

- (IBAction)dismiss {
    self.view.userInteractionEnabled = NO;
    dispatch_async(self.queue, ^{
        if (self.inputStream) {
            self.displayLink.paused = YES;
            [self.displayLink invalidate];
            self.displayLink = nil;
            
            free(self->_inputBuffer);
            self->_inputBuffer = nil;
            
            [self.inputStream close];
            self.inputStream = nil;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES completion:nil];
        });
    });
}

#pragma mark - 开始读取数据（displayLink处理的事务）

- (void)updateFrame {
    dispatch_async(self.queue, ^{
        // 1.读取数据
        [self readPacket];
        
        // 2.判断数据的类型
        if (self->_packetSize == 0 && self->_packetBuffer == NULL) {
            NSLog(@"数据读完了");
            
            self.displayLink.paused = YES;
            [self.displayLink invalidate];
            self.displayLink = nil;
            
            free(self->_inputBuffer);
            self->_inputBuffer = nil;
            
            [self.inputStream close];
            self.inputStream = nil;
            
            self.isBegin = NO;
            return;
        }
        
//        NSLog(@"读到数据");
        
        // 3.解码
        // 现在读到的数据是在内存中，并且是系统模式，要转成大端模式
        // 系统模式：有可能是小端也有可能是大端
        // H264编码的数据是【大端模式】
        // 系统模式 -> 大端模式
        uint32_t nalSize = (uint32_t)(self->_packetSize - 4);
        uint32_t *pNAL = (uint32_t *)self->_packetBuffer;
        *pNAL = CFSwapInt32HostToBig(nalSize);
        
        // 4.获取类型
        int nalType = self->_packetBuffer[4] & 0x1F;
        /**
         * 例：_packetBuffer：00 00 00 0A 27 xx xx xx ...
         * 00 00 00 0A是分隔符（转成大端前是00 00 00 01），27就是代表这段数据类型的字节
         * 指针即数组，获取数组第四位：_packetBuffer[4] = 0x27
         * 再获取这个字节开始的前五位比特，进行类型判断
         * 大端模式的高位字节到低位字节是从低地址开始往高地址保存
         * 从字面上看，左边高地址，右边低地址，高位是从右边开始（往左顺序）
         * 所以这里的前五位就是从右往左开始获取：00 10 01 11(0x27) -> 0 01 11(0x07)
         * 0x27(00 10 01 11) <-前五位-> 0x07(00 00 01 11) <-> SPS
         * 0x28(00 10 10 00) <-前五位-> 0x08(00 00 10 00) <-> PPS
         * 0x25(00 10 01 01) <-前五位-> 0x05(00 00 01 01) <-> IDR（I帧）
         * 0xXX(XX XX XX XX) <-前五位-> 0xXX(00 0X XX XX) <-> P帧或B帧
         * 前五位比特的计算方式：
         * 0x27 & 0x1F = 0x07（&：且，只要不相同即0，相同为原来的值）
         * 且0x1F目的就是得到前五位只有1的部分，其余即0
         *    00 10 01 11 <-> 0x27
            & 00 01 11 11 <-> 0x1F
            = 00 00 01 11 <-> 0x07
         */
        
        switch (nalType) {
            case 0x07:
                self->_spsSize = self->_packetSize - 4;
                self->_pSPS = malloc(self->_spsSize);
                memcpy(self->_pSPS, self->_packetBuffer + 4, self->_spsSize);
                break;
            case 0x08:
                self->_ppsSize = self->_packetSize - 4;
                self->_pPPS = malloc(self->_ppsSize);
                memcpy(self->_pPPS, self->_packetBuffer + 4, self->_ppsSize);
                break;
            case 0x05:
                // 1.创建VTDecompressionSessionRef -> sps/pps -> gop
                [self initDecompressionSession];
                // 2.解码I帧
                [self decodeFrame];
//                NSLog(@"111 开始解码一帧数据");
                break;
            default:
                // 解码B/P帧
                [self decodeFrame];
//                NSLog(@"222 开始解码一帧数据");
                break;
        }
    });
}

#pragma mark - 从文件中读取一个NALU的数据

// AVFrame：编码前的帧数据
// AVPacket：编码后的帧数据
- (void)readPacket {
    // 1.每次读取的时候，必须保证之前的数据已经清除掉
    if (_packetSize || _packetBuffer) {
        _packetSize = 0;
        free(_packetBuffer);
        _packetBuffer = nil;
    }
    
    // 2.读取数据（inputStream：流，每一次都从上一次读完的位置接着往下读）
    // 读取 _inputMaxSize - _inputSize 长度的数据到 _inputBuffer + _inputSize 这个内存地址
    // 如果不是第一次，那此时的 _inputSize 为上一次读取的数据的剩余的数据长度，如果已经为最大长度 _inputMaxSize 那这一次就不需要读取
    // self.inputStream.hasBytesAvailable：是否还有数据可读
    if (_inputSize < _inputMaxSize && self.inputStream.hasBytesAvailable) {
        _inputSize += [self.inputStream read:(_inputBuffer + _inputSize) maxLength:(_inputMaxSize - _inputSize)];
    }
    
    // 3.获取解码想要的数据
    
    // 数据样式：
    // 00 00 00 01 27 xx xx xx xx xx ... 00 00 00 01 25 xx xx xx xx xx ...
    
    // 判断前4位是否为 0x00000001（每一段数据都以0x00000001开头）
    // memcmp：判断字节是否相等
    // C语言中：-1 = 非正常，0 = 正常
    if (memcmp(_inputBuffer, pStartCode, 4) == 0) { // pStartCode字符串最后都会有一个"\0"，因此pStartCode有5位长度，所以这里取4位
        uint8_t *pStart = _inputBuffer + 4; // 这里为27的位置，
        uint8_t *pEnd = _inputBuffer + _inputSize; // 这一段数据的末端
        while (pStart != pEnd) {
            // 判断是否到达到下一个 00000001 的末端（下一段数据的开头）
            if (memcmp(pStart - 3, pStartCode, 4) == 0) { // pStartCode字符串最后都会有一个"\0"，因此pStartCode有5位长度，所以这里取4位
                
                // 到这里说明已经获取到下一个 00000001
                // 此时从 _inputBuffer 到 pStart - 3 前的这一段数据为完整的PPS或SPS或I\P\B帧数据，正是要读取的一帧数据。
                
                // 获取这段数据的长度
                _packetSize = pStart - 3 - _inputBuffer;
                
                // 读取数据：从_inputBuffer中，拷贝数据到_packetBuffer
                // memcpy：拷贝内存地址
                // 参数1：目标地址
                // 参数2：源地址
                // 参数3：拷贝源地址的多少位
                _packetBuffer = malloc(_packetSize); // 申请内存
                memcpy(_packetBuffer, _inputBuffer, _packetSize);
                
                // 将剩余数据移动到最前方（除去已读取的数据）
                // memmove：也是拷贝内存地址，能重叠相同内存地址（替换），memcpy则不能重叠
                // 参数1：目标地址
                // 参数2：源地址
                // 参数3：移动源地址的多少位
                memmove(_inputBuffer, _inputBuffer + _packetSize, _inputSize - _packetSize);
                
                // 获取剩余数据的长度
                _inputSize -= _packetSize;
                
                break;
                
            } else {
                // 一位一位地往前挪，直到 pStart - 3 这个位置开始加上之后的4位为 \x00\x00\x00\x01 才停下，此时从 _inputBuffer 到 pStart - 3 前的这一段数据才算完整的PPS或SPS或I\P\B帧数据
                pStart += 1;
            }
        }
    }
}

#pragma mark - 初始化VTDecompressionSessionRef

- (void)initDecompressionSession {
    // 1.创建CMVideoFormatDescriptionRef
    const uint8_t *pParamSet[2] = {_pSPS, _pPPS};
    const size_t pParamSizes[2] = {_spsSize, _ppsSize};
    // 参数1：分配内存的模式（NULL 默认模式）
    // 参数2：几个参数集
    // 参数3：参数集的指针
    // 参数4：参数集的大小
    // 参数5：NALU单元头部大小（固定为4个字节长度，记录着NALU体的长度）
    // 参数6：赋值对象
    CMVideoFormatDescriptionCreateFromH264ParameterSets(NULL, 2, pParamSet, pParamSizes, 4, &_formatDescription);
    
    // 2.创建VTDecompressionSessionRef
    
    // 2.1 设置存储方式
    // YUV420P（YUV：是一种颜色空间，存储空间小）
    /**
     * yuv中，y表示亮度，单独只有y数据就可以形成一张图片，只不过这张图片是灰色的。u和v表示色差(u和v也被称为：Cb－蓝色差，Cr－红色差)
     * 一张yuv的图像，去掉uv，只保留y，这张图片就是黑白的。
     * yuv可以通过抛弃色差来进行带宽优化，比如yuv420格式图像相比RGB来说，要节省一半的字节大小，抛弃相邻的色差对于人眼来说，差别不大。
               y : u : v
       正常采集：4 : 4 : 4 = 12，大小相当于RGB（three plane）
       直播采集：4 : 1 : 1 =  6，这样采集是因为人眼只对亮度敏感，只需要亮度完全采集即可，看上去就差别不大，而大小比RGB小一半（YUV420 two plane）
     */
    NSDictionary *attrs = @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)};
    
    // 2.2 设置回调
    VTDecompressionOutputCallbackRecord callbackRecord;
    callbackRecord.decompressionOutputCallback = decodeCallback;
    
    // 3.创建VTDecompressionSessionRef
    VTDecompressionSessionCreate(NULL, self.formatDescription, NULL, (__bridge CFDictionaryRef)attrs, &callbackRecord, &_decompressionSession);
}

void decodeCallback(void * CM_NULLABLE decompressionOutputRefCon,
                    void * CM_NULLABLE sourceFrameRefCon,
                    OSStatus status,
                    VTDecodeInfoFlags infoFlags,
                    CM_NULLABLE CVImageBufferRef imageBuffer,
                    CMTime presentationTimeStamp,
                    CMTime presentationDuration) {
//    NSLog(@"解码出一帧数据");
    DXVAViewController *vc = (__bridge DXVAViewController *)(sourceFrameRefCon);
    vc.aapLayer.pixelBuffer = imageBuffer;
}

#pragma mark - 解码数据

- (void)decodeFrame {
    // 1.通过数据创建一个CMBlockBuffer（用于解码）
    CMBlockBufferRef blockBuffer;
    CMBlockBufferCreateWithMemoryBlock(NULL, (void *)_packetBuffer, _packetSize, kCFAllocatorNull, NULL, 0, _packetSize, 0, &blockBuffer);
    
    // 2.准备CMSampleBufferRef
    size_t sizeArray[] = {_packetSize};
    CMSampleBufferRef sampleBuffer;
    CMSampleBufferCreateReady(NULL, blockBuffer, self.formatDescription, 0, 0, NULL, 0, sizeArray, &sampleBuffer);
    
    // 3.开始解码操作
    VTDecompressionSessionDecodeFrame(self.decompressionSession, sampleBuffer, 0, (__bridge void * _Nullable)(self), NULL);
}

@end
