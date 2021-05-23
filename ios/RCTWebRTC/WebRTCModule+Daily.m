//
//  WebRTCModule+Daily.m
//  react-native-webrtc
//
//  Created by daily-co on 7/10/20.
//

#import "WebRTCModule.h"

#import <objc/runtime.h>
#import <WebRTC/RTCAudioSession.h>
#import <WebRTC/RTCAudioSessionConfiguration.h>

NSString *const AUDIO_MODE_VIDEO_CALL = @"video";
NSString *const AUDIO_MODE_VOICE_CALL = @"voice";
NSString *const AUDIO_MODE_IDLE = @"idle";

@interface WebRTCModule (Daily) <RTCAudioSessionDelegate>

@property (nonatomic, strong) NSTimer *audioModeRetryTimer;

// Expects to only be accessed on captureSessionQueue
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong, readonly) dispatch_queue_t captureSessionQueue;

@end

@implementation WebRTCModule (Daily)

#pragma mark - enableNoOpRecordingEnsuringBackgroundContinuity

- (AVCaptureSession *)captureSession {
  return objc_getAssociatedObject(self, @selector(captureSession));
}

- (void)setCaptureSession:(AVCaptureSession *)captureSession {
  objc_setAssociatedObject(self, @selector(captureSession), captureSession, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (dispatch_queue_t)captureSessionQueue {
  dispatch_queue_t queue = objc_getAssociatedObject(self, @selector(captureSessionQueue));
  if (!queue) {
    queue = dispatch_queue_create("com.daily.noopcapturesession", DISPATCH_QUEUE_SERIAL);
    objc_setAssociatedObject(self, @selector(captureSessionQueue), queue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
  return queue;
}

- (void)audioSession:(RTCAudioSession *)audioSession willSetActive:(BOOL)active {
  // Stop audio recording before RTCAudioSession becomes active, to defend
  // against the capture session interfering with WebRTC-managed audio session.
  dispatch_sync(self.captureSessionQueue, ^{
    [self.captureSession stopRunning];
    self.captureSession = nil;
  });
}

RCT_EXPORT_METHOD(enableNoOpRecordingEnsuringBackgroundContinuity:(BOOL)enable) {
  // Listen for RTCAudioSession becoming active, so we can stop recording.
  // We only need to record until WebRTC audio unit spins up, to keep the app
  // alive in the background. Recording for longer is wasteful and seems to
  // interfere with the WebRTC-managed audio session's activation.
  [RTCAudioSession.sharedInstance removeDelegate:self];
  if (enable) {
    [RTCAudioSession.sharedInstance addDelegate:self];
  }
  
  dispatch_async(self.captureSessionQueue, ^{
    if (enable) {
      if (self.captureSession) {
        return;
      }
      AVCaptureSession *captureSession = [self configuredCaptureSession];
      [captureSession startRunning];
      self.captureSession = captureSession;
    }
    else {
      [self.captureSession stopRunning];
      self.captureSession = nil;
    }
  });
}

// Expects to be invoked from captureSessionQueue
- (AVCaptureSession *)configuredCaptureSession {
  AVCaptureSession *captureSession = [[AVCaptureSession alloc] init];
  // Don't automatically configure application audio session, to prevent
  // configuration "thrashing" once WebRTC audio unit takes the reins.
  captureSession.automaticallyConfiguresApplicationAudioSession = NO;
  AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
  if (!audioDevice) {
    return nil;
  }
  NSError *inputError;
  AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&inputError];
  if (inputError) {
    return nil;
  }
  if ([captureSession canAddInput:audioInput]) {
    [captureSession addInput:audioInput];
  }
  else {
    return nil;
  }
  AVCaptureAudioDataOutput *audioOutput = [[AVCaptureAudioDataOutput alloc] init];
  if ([captureSession canAddOutput:audioOutput]) {
    [captureSession addOutput:audioOutput];
  }
  else {
    return nil;
  }
  return captureSession;
}

#pragma mark - setDailyAudioMode

- (void)setAudioModeRetryTimer:(NSTimer *)audioModeRetryTimer {
  objc_setAssociatedObject(self,
                           @selector(audioModeRetryTimer),
                           audioModeRetryTimer,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSTimer *)audioModeRetryTimer {
  return  objc_getAssociatedObject(self, @selector(audioModeRetryTimer));
}

RCT_EXPORT_METHOD(setDailyAudioMode:(NSString *)audioMode) {
  // Validate input
  if (![@[AUDIO_MODE_VIDEO_CALL, AUDIO_MODE_VOICE_CALL, AUDIO_MODE_IDLE] containsObject:audioMode]) {
    NSLog(@"[Daily] invalid argument to setDailyAudioMode: %@", audioMode);
    return;
  }
  
  // Cancel retry timer (if any) for setting the in-call audio mode
  [self.audioModeRetryTimer invalidate];
  
  // Do nothing if we're attempting to "unset" the in-call audio mode (for now
  // it doesn't seem like there's anything to do).
  if ([audioMode isEqualToString:AUDIO_MODE_IDLE]) {
    return;
  }
  
  RTCAudioSession *audioSession = RTCAudioSession.sharedInstance;
  
  // If audioSession isn't active, configuring it won't work.
  // Instead, schedule a timer to try again.
  if (!audioSession.isActive) {
    self.audioModeRetryTimer = [NSTimer timerWithTimeInterval:1 repeats:NO block:^(NSTimer * _Nonnull timer) {
      [self setDailyAudioMode:audioMode];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.audioModeRetryTimer
                              forMode:NSRunLoopCommonModes];
    return;
  }
  
  [self applyAudioMode:audioMode toSession:audioSession];
}

- (void)applyAudioMode:(NSString *)audioMode toSession:(RTCAudioSession *)audioSession {
  [audioSession lockForConfiguration];
  
  RTCAudioSessionConfiguration *config = [[RTCAudioSessionConfiguration alloc] init];
  config.category = AVAudioSessionCategoryPlayAndRecord;
  config.mode = ([audioMode isEqualToString:AUDIO_MODE_VIDEO_CALL] ?
                 AVAudioSessionModeVideoChat :
                 AVAudioSessionModeVoiceChat);
  // Ducking other apps' audio implicitly enables allowing mixing audio with
  // other apps, which allows this app to stay alive in the backgrounnd during
  // a call (assuming it has the voip background mode set).
  AVAudioSessionCategoryOptions categoryOptions = (AVAudioSessionCategoryOptionAllowBluetooth |
                                                   AVAudioSessionCategoryOptionDuckOthers);
  if ([audioMode isEqualToString:AUDIO_MODE_VIDEO_CALL]) {
    categoryOptions |= AVAudioSessionCategoryOptionDefaultToSpeaker;
  }
  config.categoryOptions = categoryOptions;
  
  NSError *error;
  [audioSession setConfiguration:config error:&error];
  
//  NSString *inputName = audioSession.currentRoute.inputs.firstObject.portName ? audioSession.currentRoute.inputs.firstObject.portName : @"nil";
//  NSString *outputName = audioSession.currentRoute.outputs.firstObject.portName ? audioSession.currentRoute.outputs.firstObject.portName : @"nil";
  
//  NSLog(@"[pk] input count: %@", @(audioSession.currentRoute.inputs.count));
//  NSLog(@"[pk] input name: %@", inputName);
//  NSLog(@"[pk] output count: %@", @(audioSession.currentRoute.outputs.count));
//  NSLog(@"[pk] output name: %@", outputName);
//  NSLog(@"[pk] we still active? %@", @(audioSession.isActive));
  [audioSession unlockForConfiguration];
  
  if (error) {
    NSLog(@"[Daily] error applying in-call audio mode %@: %@", audioMode, error);
  }
}

@end