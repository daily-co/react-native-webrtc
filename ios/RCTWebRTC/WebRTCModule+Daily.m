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

@property (nonatomic, strong) NSString *audioMode;

@end

@implementation WebRTCModule (Daily)

#pragma mark - enableNoOpRecordingEnsuringBackgroundContinuity

RCT_EXPORT_METHOD(enableNoOpRecordingEnsuringBackgroundContinuity:(BOOL)enable) {
  // Listen for RTCAudioSession didSetActive so we can apply our audioMode
  [RTCAudioSession.sharedInstance removeDelegate:self];
  if (enable) {
    [RTCAudioSession.sharedInstance addDelegate:self];
  }
}

#pragma mark - setDailyAudioMode

- (void)setAudioMode:(NSString *)audioMode {
  objc_setAssociatedObject(self,
                           @selector(audioMode),
                           audioMode,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSString *)audioMode {
  return  objc_getAssociatedObject(self, @selector(audioMode));
}

- (void)audioSession:(RTCAudioSession *)audioSession didSetActive:(BOOL)active {
  // The audio session has become active either for the first time or again
  // after being reset by WebRTC's audio module (for example, after a Wifi -> LTE
  // switch), so (re-)apply the currently chosen audio mode to the session.
  [self applyAudioMode:self.audioMode toSession:audioSession];
}

RCT_EXPORT_METHOD(setDailyAudioMode:(NSString *)audioMode) {
  // Validate input
  if (![@[AUDIO_MODE_VIDEO_CALL, AUDIO_MODE_VOICE_CALL, AUDIO_MODE_IDLE] containsObject:audioMode]) {
    NSLog(@"[Daily] invalid argument to setDailyAudioMode: %@", audioMode);
    return;
  }

  self.audioMode = audioMode;

  // Apply the chosen audio mode right away if the audio session is already
  // active. Otherwise, it will be applied when the session becomes active.
  RTCAudioSession *audioSession = RTCAudioSession.sharedInstance;
  if (audioSession.isActive) {
    [self applyAudioMode:audioMode toSession:audioSession];
  }
}

- (void)applyAudioMode:(NSString *)audioMode toSession:(RTCAudioSession *)audioSession {
  dispatch_async(self.workerQueue, ^{
    // Do nothing if we're attempting to "unset" the in-call audio mode (for now
    // it doesn't seem like there's anything to do).
    if ([audioMode isEqualToString:AUDIO_MODE_IDLE]) {
      return;
    }

    // Ducking other apps' audio implicitly enables allowing mixing audio with
    // other apps, which allows this app to stay alive in the backgrounnd during
    // a call (assuming it has the voip background mode set).
    AVAudioSessionCategoryOptions categoryOptions = (AVAudioSessionCategoryOptionAllowBluetooth |
                                                   AVAudioSessionCategoryOptionDuckOthers);
    if ([audioMode isEqualToString:AUDIO_MODE_VIDEO_CALL]) {
      categoryOptions |= AVAudioSessionCategoryOptionDefaultToSpeaker;
    }
    [self audioSessionSetCategory:AVAudioSessionCategoryPlayAndRecord toSession:audioSession options:categoryOptions];


    NSString *mode = ([audioMode isEqualToString:AUDIO_MODE_VIDEO_CALL] ?
                     AVAudioSessionModeVideoChat :
                     AVAudioSessionModeVoiceChat);
    [self audioSessionSetMode:mode toSession:audioSession];
  });
}

- (void)audioSessionSetCategory:(NSString *)audioCategory
                        toSession:(RTCAudioSession *)audioSession
                        options:(AVAudioSessionCategoryOptions)options
{
    @try {
        [audioSession setCategory:audioCategory
                       withOptions:options
                             error:nil];
        NSLog(@"Daily: audioSession.setCategory: %@, withOptions: %lu success", audioCategory, (unsigned long)options);
    } @catch (NSException *e) {
        NSLog(@"Daily: audioSession.setCategory: %@, withOptions: %lu fail: %@", audioCategory, (unsigned long)options, e.reason);
    }
}

- (void)audioSessionSetMode:(NSString *)audioMode
                 toSession:(RTCAudioSession *)audioSession
{
    @try {
        [audioSession setMode:audioMode error:nil];
        NSLog(@"Daily: audioSession.setMode(%@) success", audioMode);
    } @catch (NSException *e) {
        NSLog(@"Daily: audioSession.setMode(%@) fail: %@", audioMode, e.reason);
    }
}

@end
