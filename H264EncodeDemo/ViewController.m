//
//  ViewController.m
//  H264EncodeDemo
//
//  Created by 周健平 on 2023/5/15.
//

#import "ViewController.h"
#import "VideoCaptureViewController.h"
#import "DXVAViewController.h"
#import <AVKit/AVKit.h>

@interface ViewController () <UITableViewDataSource, UITableViewDelegate>
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

#pragma mark - <UITableViewDataSource, UITableViewDelegate>

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
//    return 3;
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    
    switch (indexPath.row) {
        case 0:
            cell.textLabel.text = @"硬编码";
            break;
        case 1:
            cell.textLabel.text = @"硬解码";
            break;
        default:
//            cell.textLabel.text = @"系统播放器";
            break;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    switch (indexPath.row) {
        case 0:
        {
            VideoCaptureViewController *vc = [VideoCaptureViewController build];
            [self presentViewController:vc animated:YES completion:nil];
            break;
        }
        case 1:
        {
            if ([[NSFileManager defaultManager] fileExistsAtPath:JPH264Path]) {
                DXVAViewController *vc = [DXVAViewController build];
                [self presentViewController:vc animated:YES completion:nil];
            } else {
                NSLog(@"文件不存在");
            }
            break;
        }
        default:
            break;
//        {
//            if ([[NSFileManager defaultManager] fileExistsAtPath:JPH264Path]) {
//                AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:JPH264Path] options:nil];
//                AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetHighestQuality];
//
//                // 输出路径
//                NSString *outputPath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"zhoujianping_video.mp4"];
//                NSURL *outPutURL = [NSURL fileURLWithPath:outputPath];
//                if ([[NSFileManager defaultManager] fileExistsAtPath:outputPath]) {
//                    [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
//                }
//                exportSession.outputURL = outPutURL;
//                exportSession.outputFileType = AVFileTypeMPEG4;
//                exportSession.shouldOptimizeForNetworkUse = YES;
//
//                [exportSession exportAsynchronouslyWithCompletionHandler:^{
//                    dispatch_async(dispatch_get_main_queue(), ^{
//                        switch (exportSession.status) {
//                            case AVAssetExportSessionStatusCompleted:
//                            {
//                                NSLog(@"AVAssetExportSessionStatusCompleted");
////                                [JPProgressHUD showSuccessWithStatus:@"搞定" userInteractionEnabled:YES];
//                                AVPlayerViewController *playerVC = [[AVPlayerViewController alloc] init];
//                                playerVC.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:outputPath]];
//                                [self presentViewController:playerVC animated:YES completion:^{
//                                    [playerVC.player play];
//                                }];
//                                break;
//                            }
//                            default:
//                            {
//                                NSLog(@"失败 %@", exportSession.error);
////                                [JPProgressHUD showErrorWithStatus:@"失败" userInteractionEnabled:YES];
//                                break;
//                            }
//                        }
//                    });
//                }];
//            } else {
//                NSLog(@"文件不存在");
//            }
//            break;
//        }
    }
}

@end
