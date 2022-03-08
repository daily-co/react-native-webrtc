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

RCT_EXPORT_METHOD(enumerateDevices:(RCTResponseSenderBlock)callback)
{
    NSLog(@"[Daily] enumerateDevice from DevicesManager");
    NSMutableArray *devices = [NSMutableArray array];
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
    
    // FIXME looks like we will need to create the list of the output devices based on the input devices
    // https://github.com/sonisuman/AudioPlayer-MultiRoute-Support/tree/master/AudioPlayerMultiRouteSupport/AudioPlayerMultiRouteSupport/AudioPlayerSupport
    // https://stephen-chen.medium.com/how-to-add-audio-device-action-sheet-to-your-ios-app-e6bc401ccdbc
    NSArray<AVAudioSessionPortDescription *> *availableInputs = [[AVAudioSession sharedInstance] availableInputs];
    NSArray<AVAudioSessionCategory> *availableCategories = [[AVAudioSession sharedInstance] availableCategories];
    
    NSArray<AVAudioSessionPortDescription *> *outputs = [[[AVAudioSession sharedInstance] currentRoute] outputs];
    for (AVAudioSessionPortDescription *output in outputs) {
        NSLog(@"[Daily] Possible outuput %@s %@s", [output portName], [output portType]);
        if( [output.dataSources count] ){
            NSLog(@"%@",[NSString stringWithFormat:@"Port has %d data sources",(unsigned)[output.dataSources count] ]);
            NSLog(@"%@",[NSString stringWithFormat:@"Selected data source:%@",  output.selectedDataSource.dataSourceName]);
        }
    }
    
    callback(@[devices]);
}


RCT_EXPORT_METHOD(setAudioOutputDevice:(NSString *)deviceId) {
    NSLog(@"[Daily] setAudioOutputDevice: %@", deviceId);
}

@end
