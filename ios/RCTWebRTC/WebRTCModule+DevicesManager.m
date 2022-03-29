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

static NSString const *DEVICE_KIND_VIDEO_INPUT = @"videoinput";
static NSString const *DEVICE_KIND_AUDIO_INPUT = @"audioinput";
static NSString const *DEVICE_KIND_AUDIO_OUTPUT = @"audiooutput";

enum DeviceType {
    BLUETOOTH=1,
    SPEAKER=2,
    EARPIECE_HEADSET=3,
    BUILT_IN_MICROPHONE=4,
    BUILT_IN_MICROPHONE_SPEAKER=5,
    CAMERA_USER=6,
    CAMERA_ENVIRONMENT=7,
};

enum AudioRoute {
    ROUTE_BUILT_IN=1,
    ROUTE_SPEAKER=2,
    ROUTE_BLUETOOTH=3,
};

- (NSNumber*)getAudioRouteFromDeviceType:(enum DeviceType)deviceType {
    switch (deviceType) {
        case EARPIECE_HEADSET:
        case BUILT_IN_MICROPHONE:
            return [NSNumber numberWithInt:ROUTE_BUILT_IN];
        case BUILT_IN_MICROPHONE_SPEAKER:
        case SPEAKER:
            return [NSNumber numberWithInt:ROUTE_SPEAKER];
        case BLUETOOTH:
            return [NSNumber numberWithInt:ROUTE_BLUETOOTH];
        default:
            return 0;
    }
}

RCT_EXPORT_METHOD(enumerateDevices:(RCTResponseSenderBlock)callback)
{
    NSLog(@"[Daily] enumerateDevice from DevicesManager");
    NSMutableArray *devices = [NSMutableArray array];
    
    [self fillVideoInputDevices:devices];
    [self fillAudioInputDevices:devices];
    [self fillAudioOutputDevices:devices];
    
    callback(@[devices]);
}

// Whenever any headphones plugged in, it becomes the default audio route even if there is also bluetooth device.
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
            position = @"user";
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
                             @"kind": DEVICE_KIND_VIDEO_INPUT,
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
                             @"kind": DEVICE_KIND_AUDIO_INPUT,
                             @"audioRoute": [self getAudioRouteFromDeviceType:BUILT_IN_MICROPHONE],
                             }];
    }
    [devices addObject:@{
                         @"deviceId": [NSString stringWithFormat:@"%i", BUILT_IN_MICROPHONE_SPEAKER],
                         @"groupId": @"",
                         @"label": @"Built in speaker microphone",
                         @"kind": DEVICE_KIND_AUDIO_INPUT,
                         @"audioRoute": [self getAudioRouteFromDeviceType:BUILT_IN_MICROPHONE_SPEAKER],
                         }];
    if(self.hasBluetoothDevice){
        [devices addObject:@{
                             @"deviceId": [NSString stringWithFormat:@"%i", BLUETOOTH],
                             @"groupId": @"",
                             @"label": @"Bluetooth",
                             @"kind": DEVICE_KIND_AUDIO_INPUT,
                             @"audioRoute": [self getAudioRouteFromDeviceType:BLUETOOTH],
                             }];
    }
}

- (void)fillAudioOutputDevices:(NSMutableArray *)devices {
    
    [devices addObject:@{
                         @"deviceId": [NSString stringWithFormat:@"%i",EARPIECE_HEADSET],
                         @"groupId": @"",
                         @"label": @"Earpiece/Headset",
                         @"kind": DEVICE_KIND_AUDIO_OUTPUT,
                         @"audioRoute": [self getAudioRouteFromDeviceType:EARPIECE_HEADSET],
                         }];
    
    [devices addObject:@{
                         @"deviceId": [NSString stringWithFormat:@"%i",SPEAKER],
                         @"groupId": @"",
                         @"label": @"Speaker",
                         @"kind": DEVICE_KIND_AUDIO_OUTPUT,
                         @"audioRoute": [self getAudioRouteFromDeviceType:SPEAKER],
                         }];
    
    if(self.hasBluetoothDevice){
        [devices addObject:@{
                         @"deviceId": [NSString stringWithFormat:@"%i",BLUETOOTH],
                         @"groupId": @"",
                         @"label": @"Bluetooth",
                         @"kind": DEVICE_KIND_AUDIO_OUTPUT,
                         @"audioRoute": [self getAudioRouteFromDeviceType:BLUETOOTH],
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

- (BOOL)isBuiltInSpeaker:(NSString*)portType {
    return [portType isEqualToString:AVAudioSessionPortBuiltInSpeaker];
}

- (BOOL)isBuiltInEarpieceHeadset:(NSString*)portType {
    return ([portType isEqualToString:AVAudioSessionPortBuiltInReceiver] ||
            [portType isEqualToString:AVAudioSessionPortHeadphones]);
}


RCT_EXPORT_METHOD(getAudioRoute: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"[Daily] getAudioRoute");
    AVAudioSession *audioSession = AVAudioSession.sharedInstance;
    NSArray<AVAudioSessionPortDescription *> *currentRoutes = [[audioSession currentRoute] outputs];
    if([currentRoutes count] > 0){
        NSString* currentPortType = [currentRoutes[0] portType];
        NSLog(@"[Daily] currentPortType: %@", currentPortType);
        if([self isBluetoothDevice:currentPortType]){
            return resolve([NSNumber numberWithInt:ROUTE_BLUETOOTH]);
        } else if([self isBuiltInSpeaker:currentPortType]){
            return resolve([NSNumber numberWithInt:ROUTE_SPEAKER]);
        } else if([self isBuiltInEarpieceHeadset:currentPortType]){
            return resolve([NSNumber numberWithInt:ROUTE_BUILT_IN]);
        }
    }
    return resolve([NSNumber numberWithInt:ROUTE_SPEAKER]);
}

// Some reference links explaining how the audio from IOs works and sample code
// https://stephen-chen.medium.com/how-to-add-audio-device-action-sheet-to-your-ios-app-e6bc401ccdbc
// https://github.com/xialin/AudioSessionManager/blob/master/AudioSessionManager.m
RCT_EXPORT_METHOD(setAudioRoute:(nonnull NSNumber*)audioRoute) {
    NSLog(@"[Daily] setAudioRoute: %@", audioRoute);
    
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
    switch ([audioRoute intValue]) {
        case ROUTE_BUILT_IN:
            //we dont need to add anything more
            NSLog(@"[Daily] configuring output to EARPIECE_HEADSET");
            break;
        case ROUTE_SPEAKER:
            NSLog(@"[Daily] configuring output to SPEAKER");
            categoryOptions |= AVAudioSessionCategoryOptionDefaultToSpeaker;
            mode = AVAudioSessionModeVideoChat;
            break;
        case ROUTE_BLUETOOTH:
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
    if([audioRoute intValue] == ROUTE_SPEAKER){
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
