package org.webrtc;

import android.content.Context;
import android.hardware.camera2.CameraManager;

public class DailyCamera2Capturer extends Camera2Capturer {

    private final CameraManager cameraManager;

    private static final String TAG = "DailyCamera2Capturer";

    public DailyCamera2Capturer(Context context, String cameraName, CameraEventsHandler eventsHandler) {
        super(context, cameraName, eventsHandler);
        this.cameraManager = (CameraManager)context.getSystemService(Context.CAMERA_SERVICE);
        Logging.d(TAG, "CREATED DailyCamera2Capturer");
    }

    protected void createCameraSession(CameraSession.CreateSessionCallback createSessionCallback, CameraSession.Events events, Context applicationContext, SurfaceTextureHelper surfaceTextureHelper, String cameraName, int width, int height, int framerate) {
        DailyCamera2Session.create(createSessionCallback, events, applicationContext, this.cameraManager, surfaceTextureHelper, cameraName, width, height, framerate);
    }

}
