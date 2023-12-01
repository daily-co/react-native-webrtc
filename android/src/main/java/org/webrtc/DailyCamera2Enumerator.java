package org.webrtc;

import android.content.Context;

public class DailyCamera2Enumerator extends Camera2Enumerator {

    final Context context;

    public DailyCamera2Enumerator(Context context) {
        super(context);
        this.context = context;
    }

    public CameraVideoCapturer createCapturer(String deviceName, CameraVideoCapturer.CameraEventsHandler eventsHandler) {
        return new DailyCamera2Capturer(this.context, deviceName, eventsHandler);
    }

}
