package com.oney.WebRTCModule;

import android.media.AudioDeviceInfo;

final class DailyAudioDeviceUtils {
    private DailyAudioDeviceUtils() {}

    static boolean isWiredHeadsetLikeDevice(AudioDeviceInfo device) {
        switch (device.getType()) {
            case AudioDeviceInfo.TYPE_WIRED_HEADSET:
            case AudioDeviceInfo.TYPE_WIRED_HEADPHONES:
            case AudioDeviceInfo.TYPE_USB_HEADSET:
            case AudioDeviceInfo.TYPE_USB_DEVICE:
            case AudioDeviceInfo.TYPE_USB_ACCESSORY:
                return true;
            default:
                return false;
        }
    }
}
