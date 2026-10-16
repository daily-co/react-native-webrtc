#if !TARGET_OS_TV

#import <Foundation/Foundation.h>
#import <WebRTC/RTCCameraVideoCapturer.h>

#import "CaptureController.h"

@interface VideoCaptureController : CaptureController
@property(nonatomic, readonly, strong) RTCCameraVideoCapturer *capturer;
@property(nonatomic, readonly, strong) AVCaptureDeviceFormat *selectedFormat;
@property(nonatomic, readonly, assign) int frameRate;
@property(nonatomic, assign) BOOL enableMultitaskingCameraAccess;

- (instancetype)initWithCapturer:(RTCCameraVideoCapturer *)capturer andConstraints:(NSDictionary *)constraints;
- (void)startCapture;
- (void)stopCapture;
- (void)applyConstraints:(NSDictionary *)constraints error:(NSError **)outError;
-(NSString *)switchCamera;
-(NSString *)facingMode;
- (BOOL)isRunning;
- (BOOL)isTorchAvailable;
- (BOOL)setTorchEnabled:(BOOL)enabled error:(NSError **)outError;
- (nullable NSDictionary *)zoomInfo;
- (BOOL)setZoomFactor:(double)factor error:(NSError **)outError;

@end
#endif
