//
//  JPH264Encoder.m
//  H264EncodeDemo
//
//  Created by 周健平 on 2023/5/15.
//

#import "JPH264Encoder.h"
#import <VideoToolbox/VideoToolbox.h>

@interface JPH264Encoder ()
@property (nonatomic, assign) VTCompressionSessionRef compressionSession;
@property (nonatomic, assign) int frameIndex;
@property (nonatomic, strong) NSFileHandle *fileHandle;
@end

@implementation JPH264Encoder

- (void)prepareEncodeWithWidth:(int)width height:(int)height {
    
    // 创建写入文件的NSFileHandle对象
    NSString *filePath = JPH264Path;
    
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
    
    self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    
    // 设置默认是第0帧
    self.frameIndex = 0;
    
    /**
     * 创建VTCompressionSessionRef
     * 参数1：CFAllocatorRef -> 用于CoreFoundation分配内存的模式
        - nil：使用默认的分配模式
     * 参数2：width -> 编码出来视频的宽度
     * 参数3：height -> 编码出来视频的高度
     * 参数4：CMVideoCodecType -> 编码标准
        - kCMVideoCodecType_H264：使用 H.264（AVC）
     * 参数5/6/7：一般传NULL
     * 参数8：编码成功后的回调函数
        - didCompressionOutputCallback：自定义的函数（函数格式可以点击参数进去看）
     * 参数9：outputCallbackRefCon -> 可以传递到回调函数中的参数（参数8那个函数的第一个参数）
        - self：将当前对象传入（C语言函数里面用不了self，这里传self即函数里面的outputCallbackRefCon参数就是self）
     * 参数10：创建好的VTCompressionSessionRef的地址（给属性赋值）
     */
    VTCompressionSessionCreate(nil, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, didCompressionOutputCallback, (__bridge void * _Nullable)(self), &_compressionSession);
    
    // 2.设置属性
    // 2.1 设置实时输出
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_RealTime, (__bridge CFTypeRef _Nullable)(@YES));
    
    // 2.2 设置帧率
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_ExpectedFrameRate, (__bridge CFTypeRef _Nullable)(@24));
    
    // 2.3 设置比特率（码率）
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef _Nullable)(@1500000)); // 这里的单位是bit
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFTypeRef _Nullable)(@[@(1500000/8), @1])); // 这里的单位是byte，要除以8（1500000/s：设置为1秒钟最大1500000的比特）
    
    // 2.4 设置GOP的大小，关键帧（GOPsize)间隔
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef _Nullable)(@20));
    
    // 3.准备编码
    VTCompressionSessionPrepareToEncodeFrames(_compressionSession);
}

- (void)encodeFrame:(CMSampleBufferRef)sampleBuffer {
    
    // 1.将CMSampleBufferRef转成CVImageBufferRef
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    // 开始编码
    // 参数1：compressionSession
    // 参数2：CVImageBufferRef
    // 参数3：PTS(presentationTimeStamp：展示时间戳)/DTS(DecodeTimeStamp：编码时间戳)
    // 参数4：kCMTimeInvalid（固定参数，传这个好了）
    // 参数5：一般用不到，传NULL
    // 参数6：编码成功后的回调函数（didCompressionOutputCallback）的第二个参数（sourceFrameRefCon）
    // 参数7：编码成功后的回调函数（didCompressionOutputCallback）的第四个参数（infoFlags）
    CMTime pts = CMTimeMake(self.frameIndex, 24); // 这是第几帧，一秒多少帧
    VTEncodeInfoFlags infoFlagsOut;
    VTCompressionSessionEncodeFrame(self.compressionSession, imageBuffer, pts, kCMTimeInvalid, NULL, NULL, &infoFlagsOut);
    
//    NSLog(@"开始编码一帧数据");
    
}

#pragma mark - 获取编码后的数据
void didCompressionOutputCallback(void * CM_NULLABLE outputCallbackRefCon,
                                  void * CM_NULLABLE sourceFrameRefCon,
                                  OSStatus status,
                                  VTEncodeInfoFlags infoFlags,
                                  CM_NULLABLE CMSampleBufferRef sampleBuffer) {
    
    // 0.获取当前对象
    JPH264Encoder *encoder = (__bridge JPH264Encoder *)(outputCallbackRefCon);
    
    // 1.判断该帧是否为关键帧（I帧）
    // 获取附件
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES); // 数组
    
    CFDictionaryRef dic = CFArrayGetValueAtIndex(attachments, 0); // 字典
    
    // CFDictionaryContainsKey：字典是否包含这个键
    // kCMSampleAttachmentKey_NotSync：如果包含了这个键就不是关键帧，不包含就是关键帧
    BOOL isKeyFrame = !CFDictionaryContainsKey(dic, kCMSampleAttachmentKey_NotSync);
    
    // 2.如果是关键帧，获取SPS/PPS数据，并且写入文件
    if (isKeyFrame) {
        // 2.1 从CMSampleBufferRef获取CMFormatDescriptionRef，里面存储了SPS和PPS的信息
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        
        // 2.2 获取SPS信息（下标为0）
        const uint8_t *spsOut;
        size_t spsSize, spsCount;
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &spsOut, &spsSize, &spsCount, NULL);
        
        // 2.3 获取PPS信息（下标为1）
        const uint8_t *ppsOut;
        size_t ppsSize, ppsCount;
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &ppsOut, &ppsSize, &ppsCount, NULL);
        
        // 2.4 将SPS和PPS转成NSData，并写入文件
        NSData *spsData = [NSData dataWithBytes:spsOut length:spsSize];
        NSData *ppsData = [NSData dataWithBytes:ppsOut length:ppsSize];
        
        // 2.5 写入文件
        [encoder writeData:spsData];
        [encoder writeData:ppsData];
        
        NSLog(@"这是关键帧");
    } else {
        NSLog(@"不是关键帧");
    }
    
    // 3.获取编码后的数据，写入文件
    // 3.1 获取CMBlockBufferRef
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    
    // 3.2 从blockBuffer中获取【起始位置】的内存地址和【总长度】
    size_t totalLength = 0; // 从长度
    char *dataPointer; // 起始位置
    CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &totalLength, &dataPointer);
    
    /**
     * NAL的封装方式：
        - NAL是将每一帧数据写入到一个NAL单元中，进行传输或存储的
        - NALU分为NAL头和NAL体
        - NALU头通常为00 00 00 01，作为一个新的NALU的起始标识
        - NALU体封装着VCL编码后的信息或者其他信息
     */
    
    // 3.3 一帧的图像可能需要写入多个NALU单元（1个可能写不完） --> Slice切片
    static const int H264HeaderLength = 4; // NALU单元头部为4个字节长度，记录着之后那一段数据（NALU体）的长度
    
    // 一般不止一个切片，循环切片
    int sliceCount = 0;
    size_t bufferOffet = 0;
    while (bufferOffet < totalLength - H264HeaderLength) {
        
        // 每一段前4位（H264HeaderLength）字节（NALU头），存放的是之后那一段数据（NALU体）的长度（NALULength），获取这个长度，之后使用NSData的dataWithBytes方法，从第几个字节开始，获取多少长度的data，然后再叠加偏移量（bufferOffet），下一轮根据起始位置和偏移量（dataPointer + bufferOffet）继续获取下一段的data
        
        // 3.4 从起始位置开始拷贝H264HeaderLength长度的地址，计算NALULength
        // 拷贝内存地址，获取数据长度（拷贝出来的这个地址是一个数字，这个数字就是记录之后那一段数据（NALU体）的长度）
        int NALULength = 0;
        memcpy(&NALULength, dataPointer + bufferOffet, H264HeaderLength);
        
        // 系统模式：有可能是小端也有可能是大端
        // H264编码的数据是【大端模式】（字节序）
        
        // 将大端模式转成系统Host模式（大端模式/小端模式）
        NALULength = CFSwapInt32BigToHost(NALULength);
        
        // 3.5 从dataPointer开始，根据长度创建NSData
        // 从第几个字节开始，获取多少长度的data
        // 要加上H264HeaderLength，前4位记录的只是长度（NALULength）
        NSData *data = [NSData dataWithBytes:dataPointer + bufferOffet + H264HeaderLength length:NALULength];
        
        // 3.6 写入文件
        [encoder writeData:data];
        
        // 3.7 重新设置bufferOffet
        bufferOffet += (H264HeaderLength + NALULength);
        
        sliceCount += 1;
        
        // 通俗点来说：内存地址从"dataPointer + bufferOffet"这个位置开始，拷贝（memcpy）长度为"H264HeaderLength"的内存地址（NALU头），这4位内存地址记录的是之后那一段数据（NALU体）的长度值"NALULength"
        // 这时候后面那段数据（NALU体）的起始位置就是"dataPointer + bufferOffet + H264HeaderLength"
        // 有了这个起始位置和长度，就可以调用【dataWithBytes】方法创建对应"data"，再将其写入文件
        // 这个"data"就是PPS或SPS或I\B\P帧的实际数据
        // 更新偏移量"bufferOffet"，继续往前挪"H264HeaderLength + NALULength"，到下一个切片的起始位置（NALU头）循环操作
    }
    
    NSLog(@"这一帧共切了%d次", sliceCount);
    NSLog(@"------------------");
}

- (void)writeData:(NSData *)data {
    // 0x01：十六进制，这里的1位代表4个比特，2位就是8个比特，即1个字节
    // ---> 0000 0001
    
    // NALU单元头部：0x00 00 00 01
    // NALU单元数据：XX XX ... XX
    // NALU = (NALU start code) + (Data)
    
    // 如果有关键帧的话就先拼接SPS和PPS，再拼接帧图片数据
    // 0x00 00 00 01 + XX XX ... XX --> SPS
    // 0x00 00 00 01 + XX XX ... XX --> PPS
    // 拼接帧图片数据
    // 0x00 00 00 01 + XX XX ... XX --> Picture Data
    
    // 1.获取startCode
    const char bytes[] = "\x00\x00\x00\x01";
    
    // 2.获取headerData
    NSData *headerData = [NSData dataWithBytes:bytes length:sizeof(bytes) - 1];
    // sizeof(bytes) - 1：字符串最后都会有一个"\0"，sizeof获取字符串的长度会比正确的长度多1
    
    // 3.写入文件
    [self.fileHandle writeData:headerData];
    [self.fileHandle writeData:data];
}

- (void)endEncode {
    VTCompressionSessionInvalidate(_compressionSession);
    CFRelease(_compressionSession);
}

/*
 0000 <-> 0
 0001 <-> 1
 0010 <-> 2
 0011 <-> 3
 0100 <-> 4
 0101 <-> 5
 0110 <-> 6
 0111 <-> 7
 1000 <-> 8
 1001 <-> 9
 1010 <-> A
 1011 <-> B
 1100 <-> C
 1101 <-> D
 1110 <-> E
 1111 <-> F
 
 8位二进制为一个字节，范围为：0b00000000 ~ 0b11111111
 转换成十六进制，则为：0x00 ~ 0xFF
 0b：代表二进制，0x：代表十六进制
 0b11111111 = 2^7(128) + 2^6(64) + 2^5(32) + 2^4(16) + 2^3(8) + 2^2(4) + 2^1(2) + 2^0(1) = 255
 0xFF = 16^1*15(240) + 16^0*15(15) = 255
 0b11111111 == 0xFF：8位二进制 == 2位十六进制 == 1字节
 所以，0x00 00 00 01：这里就代表了4个字节（int类型大小为4个字节）
 
 
 大端模式：是指数据的【高字节】保存在内存的【低地址】中，而数据的【低字节】保存在内存的【高地址】中，这样的存储模式有点儿类似于把数据当作字符串顺序处理：地址由小向大增加，而数据从高位往低位放；这和我们的阅读习惯一致。
 小端模式：是指数据的【高字节】保存在内存的【高地址】中，而数据的【低字节】保存在内存的【低地址】中，这种存储模式将地址的高低和数据位权有效地结合起来，高地址部分权值高，低地址部分权值低。
 
 下面以unsigned int value = 0x12345678为例，分别看看在两种字节序下其存储情况，我们可以用unsigned char buf[4]来表示value
 
 0x12345678
 字节:高 -> 低
 
 Big-Endian: 低地址存放高位，如下：
    高地址
 　　---------------
 　　buf[3] (0x78) -- 低位
 　　buf[2] (0x56)
 　　buf[1] (0x34)
 　　buf[0] (0x12) -- 高位
 　　---------------
 　　低地址
 
 Little-Endian: 低地址存放低位，如下：
    高地址
 　　---------------
 　　buf[3] (0x12) -- 高位
 　　buf[2] (0x34)
 　　buf[1] (0x56)
 　　buf[0] (0x78) -- 低位
 　　--------------
    低地址
 */

@end
