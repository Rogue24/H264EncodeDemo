//
//  JPH264Encoder.h
//  H264EncodeDemo
//
//  Created by 周健平 on 2023/5/15.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface JPH264Encoder : NSObject

- (void)prepareEncodeWithWidth:(int)width height:(int)height;
- (void)encodeFrame:(CMSampleBufferRef)sampleBuffer;
- (void)endEncode;

@end
