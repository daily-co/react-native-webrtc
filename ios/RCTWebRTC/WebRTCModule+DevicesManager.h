//
//  WebRTCModule+DevicesManager.m
//  react-native-webrtc
//
//  Created by Filipi Fuchter on 01/04/22.
//

#import "WebRTCModule.h"

@interface WebRTCModule (DevicesManager)

enum AudioRoute {
    ROUTE_BUILT_IN=1,
    ROUTE_SPEAKER=2,
    ROUTE_BLUETOOTH=3,
};

- (BOOL)hasBluetoothDevice;

- (void)setAudioRoute:(nonnull NSNumber*)audioRoute;

@end
