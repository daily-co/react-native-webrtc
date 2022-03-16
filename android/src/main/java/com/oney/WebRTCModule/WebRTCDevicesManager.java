package com.oney.WebRTCModule;

import android.content.Context;
import android.media.AudioDeviceInfo;
import android.media.AudioManager;
import android.os.Build;
import android.util.Log;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;

import org.webrtc.Camera1Enumerator;
import org.webrtc.Camera2Enumerator;
import org.webrtc.CameraEnumerator;

import java.util.Arrays;

public class WebRTCDevicesManager {

    static final String TAG = WebRTCDevicesManager.class.getCanonicalName();

    public enum DeviceKind {
        // Those constants are defined on the webrtc specification
        // https://w3c.github.io/mediacapture-main/#dom-mediadevicekind
        VIDEO_INPUT("videoinput"),
        AUDIO_INPUT("audioinput"),
        AUDIO_OUTPUT("audiooutput");

        private String kind;

        DeviceKind(String kind){
            this.kind = kind;
        }

        public String getKind() {
            return this.kind;
        }
    }

    private enum DeviceType {
        BLUETOOTH,
        HEADSET,
        SPEAKER,
        EARPIECE,
        BUILT_IN_MICROPHONE,
        CAMERA_USER,
        CAMERA_ENVIRONMENT,
    }

    private final CameraEnumerator cameraEnumerator;
    private AudioManager audioManager;
    private ReactApplicationContext reactContext;

    public WebRTCDevicesManager(ReactApplicationContext reactContext) {
        this.reactContext = reactContext;
        this.audioManager = (AudioManager) reactContext.getSystemService(Context.AUDIO_SERVICE);
        this.cameraEnumerator = this.createCameraEnumerator();
    }

    private CameraEnumerator createCameraEnumerator() {
        boolean camera2supported = false;
        try {
            camera2supported = Camera2Enumerator.isSupported(this.reactContext);
        } catch (Throwable tr) {
            // Some devices will crash here with: Fatal Exception: java.lang.AssertionError: Supported FPS ranges cannot be null.
            // Make sure we don't.
            Log.w(TAG, "Error checking for Camera2 API support.", tr);
        }
        CameraEnumerator cameraEnumerator = null;
        if (camera2supported) {
            Log.d(TAG, "Creating video capturer using Camera2 API.");
            cameraEnumerator = new Camera2Enumerator(this.reactContext);
        } else {
            Log.d(TAG, "Creating video capturer using Camera1 API.");
            cameraEnumerator = new Camera1Enumerator(false);
        }
        return cameraEnumerator;
    }

    ReadableArray enumerateDevices() {
        WritableArray devicesArray = Arguments.createArray();
        this.fillVideoInputDevices(devicesArray);
        this.fillAudioInputDevices(devicesArray);
        this.fillAudioOutputDevices(devicesArray);
        return devicesArray;
    }

    private void fillVideoInputDevices(WritableArray enumerateDevicesArray){
        String[] devices = cameraEnumerator.getDeviceNames();
        for (int i = 0; i < devices.length; ++i) {
            String deviceName = devices[i];
            boolean isFrontFacing;
            try {
                // This can throw an exception when using the Camera 1 API.
                isFrontFacing = cameraEnumerator.isFrontFacing(deviceName);
            } catch (Exception e) {
                Log.e(TAG, "Failed to check the facing mode of camera");
                continue;
            }
            String label = isFrontFacing ? "Front camera" : "Rear camera";
            DeviceType deviceId = isFrontFacing ? DeviceType.CAMERA_USER : DeviceType.CAMERA_ENVIRONMENT;
            WritableMap params = this.createWritableMap(deviceId, label, DeviceKind.VIDEO_INPUT.getKind());
            params.putString("facing", isFrontFacing ? "user" : "environment");
            enumerateDevicesArray.pushMap(params);
        }
    }

    private void fillAudioInputDevices(WritableArray enumerateDevicesArray){
        AudioDeviceInfo[] audioInputDevices = this.audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS);

        boolean isWiredHeadsetPlugged = Arrays.stream(audioInputDevices).anyMatch(device -> device.getType() == AudioDeviceInfo.TYPE_WIRED_HEADSET);
        // At Android, if the Wired headset is plugged, we are unable to choose to use the built-in microphone. We can only choose to use the bluetooth or the default.
        if(isWiredHeadsetPlugged){
            WritableMap params = this.createWritableMap(DeviceType.HEADSET, "Wired headset", DeviceKind.AUDIO_INPUT.getKind());
            enumerateDevicesArray.pushMap(params);
        }else {
            WritableMap params = this.createWritableMap(DeviceType.BUILT_IN_MICROPHONE, "Built in microphone", DeviceKind.AUDIO_INPUT.getKind());
            enumerateDevicesArray.pushMap(params);
        }

        boolean isBluetoothHeadsetPlugged = Arrays.stream(audioInputDevices).anyMatch(device -> device.getType() == AudioDeviceInfo.TYPE_BLUETOOTH_SCO);
        if(isBluetoothHeadsetPlugged){
            WritableMap params = this.createWritableMap(DeviceType.BLUETOOTH, "Bluetooth microphone", DeviceKind.AUDIO_INPUT.getKind());
            enumerateDevicesArray.pushMap(params);
        }
    }

    private void fillAudioOutputDevices(WritableArray enumerateDevicesArray){
        AudioDeviceInfo[] audioOutputDevices = this.audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS);

        boolean isWiredHeadsetPlugged = Arrays.stream(audioOutputDevices).anyMatch(
                device -> device.getType() == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                        device.getType() == AudioDeviceInfo.TYPE_WIRED_HEADPHONES
        );

        WritableMap params = null;
        // At Android, if the Wired headset is plugged, we are unable to choose to use the built-in microphone. We can only choose to use the bluetooth or the default.
        if(isWiredHeadsetPlugged){
            params = this.createWritableMap(DeviceType.HEADSET, "Wired headset", DeviceKind.AUDIO_OUTPUT.getKind());
        }else {
            params = this.createWritableMap(DeviceType.EARPIECE, "Phone Earpiece", DeviceKind.AUDIO_OUTPUT.getKind());
        }
        enumerateDevicesArray.pushMap(params);

        //speaker
        params = this.createWritableMap(DeviceType.SPEAKER, "Speaker", DeviceKind.AUDIO_OUTPUT.getKind());
        enumerateDevicesArray.pushMap(params);

        boolean isBluetoothHeadsetPlugged = Arrays.stream(audioOutputDevices).anyMatch(device -> device.getType() == AudioDeviceInfo.TYPE_BLUETOOTH_SCO);
        if(isBluetoothHeadsetPlugged){
            params = this.createWritableMap(DeviceType.BLUETOOTH, "Bluetooth", DeviceKind.AUDIO_OUTPUT.getKind());
            enumerateDevicesArray.pushMap(params);
        }
    }

    private WritableMap createWritableMap(DeviceType deviceId, String label, String kind){
        WritableMap audioMap = Arguments.createMap();
        audioMap.putString("deviceId", deviceId.toString());
        audioMap.putString("groupId", "");
        audioMap.putString("label", label);
        audioMap.putString("kind", kind);
        return audioMap;
    }

    /** Changes selection of the currently active audio device. */
    public void setAudioRoute(String deviceId) {
        Log.d(TAG, "setAudioDevice(device=" + deviceId + ")");
        DeviceType deviceType = null;
        try{
            deviceType = DeviceType.valueOf(deviceId);
        } catch (Exception e){
            //TODO should we throw some exception ?
            Log.d(TAG, "The selected device is not available!");
            return;
        }
        switch (deviceType) {
            case SPEAKER:
                toggleBluetooth(false);
                audioManager.setSpeakerphoneOn(true);
                break;
            //If we have a wired headset plugged, It is not possible we send the audio to the earpiece
            case HEADSET:
            case EARPIECE:
                toggleBluetooth(false);
                audioManager.setSpeakerphoneOn(false);
                break;
            case BLUETOOTH:
                audioManager.setSpeakerphoneOn(false);
                toggleBluetooth(true);
                break;
            default:
                Log.e(TAG, "Invalid audio device selection");
                break;
        }
    }

    private void toggleBluetooth(boolean on) {
        if (on) {
            audioManager.startBluetoothSco();
            audioManager.setBluetoothScoOn(true);
        } else {
            audioManager.setBluetoothScoOn(false);
            audioManager.stopBluetoothSco();
        }
    }

}
