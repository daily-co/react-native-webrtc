//
//  WebRTCModule+DevicesManager.m
//  react-native-webrtc
//
//  Created by Filipi Fuchter on 08/03/22.
//

#import "WebRTCModule.h"

@interface WebRTCModule (DevicesManager)

@end

@implementation WebRTCModule (DevicesManager)

enum DeviceType {
    BLUETOOTH,
    SPEAKER,
    EARPIECE_HEADSET,
    BUILT_IN_MICROPHONE,
    CAMERA_USER,
    CAMERA_ENVIRONMENT,
};

RCT_EXPORT_METHOD(enumerateDevices:(RCTResponseSenderBlock)callback)
{
    NSLog(@"[Daily] enumerateDevice from DevicesManager");
    NSMutableArray *devices = [NSMutableArray array];
    
    [self fillVideoInputDevices:devices];
    [self fillAudioInputDevices:devices];
    [self fillAudioOutputDevices:devices];
    
    callback(@[devices]);
}

// Whenever any headphones plugged in, it becomes the default audio route even there is also bluetooth device.
// And it overwrites the handset(iPhone) option, which means you cannot change to the handset(iPhone).
- (void)fillVideoInputDevices:(NSMutableArray *)devices {
    AVCaptureDeviceDiscoverySession *videoevicesSession
        = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInWideAngleCamera ]
                                                                 mediaType:AVMediaTypeVideo
                                                                  position:AVCaptureDevicePositionUnspecified];
    for (AVCaptureDevice *device in videoevicesSession.devices) {
        NSString *position = @"unknown";
        if (device.position == AVCaptureDevicePositionBack) {
            position = @"environment";
        } else if (device.position == AVCaptureDevicePositionFront) {
            position = @"front";
        }
        NSString *label = @"Unknown video device";
        if (device.localizedName != nil) {
            label = device.localizedName;
        }
        [devices addObject:@{
                             @"facing": position,
                             @"deviceId": device.uniqueID,
                             @"groupId": @"",
                             @"label": label,
                             @"kind": @"videoinput",
                             }];
    }
}

- (void)fillAudioInputDevices:(NSMutableArray *)devices {
    AVCaptureDeviceDiscoverySession *audioDevicesSession
        = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInMicrophone ]
                                                                 mediaType:AVMediaTypeAudio
                                                                  position:AVCaptureDevicePositionUnspecified];
    for (AVCaptureDevice *device in audioDevicesSession.devices) {
        NSString *label = @"Unknown audio device";
        if (device.localizedName != nil) {
            label = device.localizedName;
        }
        [devices addObject:@{
                             @"deviceId": device.uniqueID,
                             @"groupId": @"",
                             @"label": label,
                             @"kind": @"audioinput",
                             }];
    }
}

- (void)fillAudioOutputDevices:(NSMutableArray *)devices {
    [devices addObject:@{
                         @"deviceId": [NSNumber numberWithInt:EARPIECE_HEADSET],
                         @"groupId": @"",
                         @"label": @"Earpiece\Headset",
                         @"kind": @"audiooutput",
                         }];
    
    [devices addObject:@{
                         @"deviceId": [NSNumber numberWithInt:SPEAKER],
                         @"groupId": @"",
                         @"label": @"Speaker",
                         @"kind": @"audiooutput",
                         }];
    
    if(self.hasBluetoothDevice){
        [devices addObject:@{
                             @"deviceId": [NSNumber numberWithInt:BLUETOOTH],
                             @"groupId": @"",
                             @"label": @"Bluetooth",
                             @"kind": @"audiooutput",
                             }];
    }
}

- (BOOL)hasBluetoothDevice {
    AVAudioSession *audioSession = AVAudioSession.sharedInstance;

    NSArray<AVAudioSessionPortDescription *> *availableInputs = [audioSession availableInputs];
    for (AVAudioSessionPortDescription *device in availableInputs) {
        if([self isBluetoothDevice:[device portType]]){
            return true;
        }
    }

    NSArray<AVAudioSessionPortDescription *> *outputs = [[audioSession currentRoute] outputs];
    for (AVAudioSessionPortDescription *device in outputs) {
        if([self isBluetoothDevice:[device portType]]){
            return true;
        }
    }
    return false;
}

- (BOOL)isBluetoothDevice:(NSString*)portType {
    BOOL isBluetooth;
    isBluetooth = ([portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
                   [portType isEqualToString:AVAudioSessionPortBluetoothHFP]);
    if (@available(iOS 7.0, *)) {
        isBluetooth |= [portType isEqualToString:AVAudioSessionPortBluetoothLE];
    }
    return isBluetooth;
}


// Some reference links explaining how the audio from IOs works and sample code
// https://stephen-chen.medium.com/how-to-add-audio-device-action-sheet-to-your-ios-app-e6bc401ccdbc
// https://github.com/xialin/AudioSessionManager/blob/master/AudioSessionManager.m
RCT_EXPORT_METHOD(setAudioOutputDevice:(nonnull NSNumber*)deviceId) {
    NSLog(@"[Daily] setAudioOutputDevice: %@", deviceId);
    
    // Ducking other apps' audio implicitly enables allowing mixing audio with
    // other apps, which allows this app to stay alive in the backgrounnd during
    // a call (assuming it has the voip background mode set).
    AVAudioSessionCategoryOptions categoryOptions = (AVAudioSessionCategoryOptionDuckOthers);
    NSString *mode = AVAudioSessionModeVoiceChat;
    
    // Earpiece: is default route for a call.
    // Speaker: the speaker is the default output audio for like music, video, ring tone.
    // Bluetooth: whenever a bluetooth device connected, the bluetooth device will become the default audio route.
    // Headphones: whenever any headphones plugged in, it becomes the default audio route even there is also bluetooth device.
    //  And it overwrites the handset(iPhone) option, which means you cannot change to the earpiece, bluetooth.
    switch ([deviceId intValue]) {
        case EARPIECE_HEADSET:
            //we dont need to add anything more
            NSLog(@"[Daily] configuring output to EARPIECE_HEADSET");
            break;
        case SPEAKER:
            NSLog(@"[Daily] configuring output to SPEAKER");
            categoryOptions |= AVAudioSessionCategoryOptionDefaultToSpeaker;
            mode = AVAudioSessionModeVideoChat;
            break;
        case BLUETOOTH:
            NSLog(@"[Daily] configuring output to BLUETOOTH");
            categoryOptions |= AVAudioSessionCategoryOptionAllowBluetooth;
            break;
        default:
            NSLog(@"[Daily] not recognized output type");
            break;
    }
    
    AVAudioSession *audioSession = AVAudioSession.sharedInstance;
    // We need to set the mode before set the category, because when setting the node It can automatically change the categories.
    // This way we can enforce the categories that we want later.
    [self audioSessionSetMode:mode toSession:audioSession];
    [self audioSessionSetCategory:AVAudioSessionCategoryPlayAndRecord toSession:audioSession options:categoryOptions];
    
    // Force to speaker. We only need to do that the cases a wired headset is connected, but we still want to force to speaker
    if([deviceId intValue] == SPEAKER){
        [audioSession overrideOutputAudioPort: AVAudioSessionPortOverrideSpeaker error: nil];
    }
}

- (void)audioSessionSetCategory:(NSString *)audioCategory
                      toSession:(AVAudioSession *)audioSession
                        options:(AVAudioSessionCategoryOptions)options
{
  @try {
    [audioSession setCategory:audioCategory
                  withOptions:options
                        error:nil];
    NSLog(@"[Daily] audioSession.setCategory: %@, withOptions: %lu success", audioCategory, (unsigned long)options);
  } @catch (NSException *e) {
    NSLog(@"[Daily] audioSession.setCategory: %@, withOptions: %lu fail: %@", audioCategory, (unsigned long)options, e.reason);
  }
}

- (void)audioSessionSetMode:(NSString *)audioMode
                  toSession:(AVAudioSession *)audioSession
{
  @try {
    [audioSession setMode:audioMode error:nil];
    NSLog(@"[Daily] audioSession.setMode(%@) success", audioMode);
  } @catch (NSException *e) {
    NSLog(@"[Daily] audioSession.setMode(%@) fail: %@", audioMode, e.reason);
  }
}

@end
