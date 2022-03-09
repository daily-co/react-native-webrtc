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
    // Whenever any headphones plugged in, it becomes the default audio route even there is also bluetooth device.
    // And it overwrites the handset(iPhone) option, which means you cannot change to the handset(iPhone).
    [self fillAudioInputDevices:devices];
    [self fillAudioOutputDevices:devices];
    
    callback(@[devices]);
}

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

//TODO implement
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

//FIXME all we need is to findout if bluetooth is or not connected
//    // FIXME looks like we will need to create the list of the output devices based on the input devices
//    // https://github.com/sonisuman/AudioPlayer-MultiRoute-Support/tree/master/AudioPlayerMultiRouteSupport/AudioPlayerMultiRouteSupport/AudioPlayerSupport
//    // https://stephen-chen.medium.com/how-to-add-audio-device-action-sheet-to-your-ios-app-e6bc401ccdbc
//    // https://github.com/xialin/AudioSessionManager/blob/master/AudioSessionManager.m
//    NSArray<AVAudioSessionPortDescription *> *availableInputs = [[AVAudioSession sharedInstance] availableInputs];
//
//    NSArray<AVAudioSessionPortDescription *> *outputs = [[[AVAudioSession sharedInstance] currentRoute] outputs];
//    for (AVAudioSessionPortDescription *output in outputs) {
//        NSLog(@"[Daily] Possible outuput %@s %@s", [output portName], [output portType]);
//        if( [output.dataSources count] ){
//            NSLog(@"%@",[NSString stringWithFormat:@"Port has %d data sources",(unsigned)[output.dataSources count] ]);
//            NSLog(@"%@",[NSString stringWithFormat:@"Selected data source:%@",  output.selectedDataSource.dataSourceName]);
//        }
//    }
}

- (BOOL)isBluetoothDevice:(NSString*)portType {
    BOOL isBluetooth;
    isBluetooth = ([portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
                   [portType isEqualToString:AVAudioSessionPortBluetoothHFP]);
    
    if ([[[UIDevice currentDevice] systemVersion] integerValue] > 6) {
        isBluetooth = (isBluetooth || [portType isEqualToString:AVAudioSessionPortBluetoothLE]);
    }
    
    return isBluetooth;
}


RCT_EXPORT_METHOD(setAudioOutputDevice:(nonnull NSNumber*)deviceId) {
    NSLog(@"[Daily] setAudioOutputDevice: %@", deviceId);
    
    // Ducking other apps' audio implicitly enables allowing mixing audio with
    // other apps, which allows this app to stay alive in the backgrounnd during
    // a call (assuming it has the voip background mode set).
    AVAudioSessionCategoryOptions categoryOptions = (AVAudioSessionCategoryOptionDuckOthers);

    switch ([deviceId intValue]) {
        case EARPIECE_HEADSET:
            //we dont need to add anything more
            NSLog(@"[Daily] configuring output to EARPIECE_HEADSET");
            break;
        case SPEAKER:
            NSLog(@"[Daily] configuring output to SPEAKER");
            categoryOptions |= AVAudioSessionCategoryOptionDefaultToSpeaker;
            break;
        case BLUETOOTH:
            NSLog(@"[Daily] configuring output to BLUETOOTH");
            categoryOptions |= AVAudioSessionCategoryOptionAllowBluetooth;
            break;
        default:
            NSLog(@"[Daily] not recognized output type");
            break;
    }
    
    [self audioSessionSetCategory:AVAudioSessionCategoryPlayAndRecord toSession:[AVAudioSession sharedInstance] options:categoryOptions];
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

@end
