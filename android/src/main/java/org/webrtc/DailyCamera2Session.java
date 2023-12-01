package org.webrtc;

import android.content.Context;
import android.graphics.Matrix;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureFailure;
import android.hardware.camera2.CaptureRequest;
import android.os.Handler;
import android.util.Log;
import android.util.Range;
import android.view.OrientationEventListener;
import android.view.Surface;
import androidx.annotation.Nullable;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.TimeUnit;

public class DailyCamera2Session implements CameraSession{

    private static final String TAG = "DailyCamera2Session";
    private static final Histogram camera2StartTimeMsHistogram = Histogram.createCounts("WebRTC.Android.Camera2.StartTimeMs", 1, 10000, 50);
    private static final Histogram camera2StopTimeMsHistogram = Histogram.createCounts("WebRTC.Android.Camera2.StopTimeMs", 1, 10000, 50);
    private static final Histogram camera2ResolutionHistogram;
    private final Handler cameraThreadHandler;
    private final CameraSession.CreateSessionCallback callback;
    private final CameraSession.Events events;
    private final Context applicationContext;
    private final CameraManager cameraManager;
    private final SurfaceTextureHelper surfaceTextureHelper;
    private final String cameraId;
    private final int width;
    private final int height;
    private final int framerate;
    private CameraCharacteristics cameraCharacteristics;
    private int cameraOrientation;
    private boolean isCameraFrontFacing;
    private int fpsUnitFactor;
    private CameraEnumerationAndroid.CaptureFormat captureFormat;
    @Nullable
    private CameraDevice cameraDevice;
    @Nullable
    private Surface surface;
    @Nullable
    private CameraCaptureSession captureSession;
    private SessionState state;
    private boolean firstFrameReported;
    private final long constructionTimeNs;

    public static void create(CameraSession.CreateSessionCallback callback, CameraSession.Events events, Context applicationContext, CameraManager cameraManager, SurfaceTextureHelper surfaceTextureHelper, String cameraId, int width, int height, int framerate) {
        new DailyCamera2Session(callback, events, applicationContext, cameraManager, surfaceTextureHelper, cameraId, width, height, framerate);
        Logging.d(TAG, "CREATED DailyCamera2Session");
    }

    private DailyCamera2Session(CameraSession.CreateSessionCallback callback, CameraSession.Events events, Context applicationContext, CameraManager cameraManager, SurfaceTextureHelper surfaceTextureHelper, String cameraId, int width, int height, int framerate) {
        this.state = DailyCamera2Session.SessionState.RUNNING;
        Logging.d("Camera2Session", "Create new camera2 session on camera " + cameraId);
        this.constructionTimeNs = System.nanoTime();
        this.cameraThreadHandler = new Handler();
        this.callback = callback;
        this.events = events;
        this.applicationContext = applicationContext;
        this.cameraManager = cameraManager;
        this.surfaceTextureHelper = surfaceTextureHelper;
        this.cameraId = cameraId;
        this.width = width;
        this.height = height;
        this.framerate = framerate;
        this.start();
        this.startOrientationListener();
    }

    private OrientationEventListener orientatationListener;
    private int angleRotation = 0;


    //TODO see if we are going to use for something
    private int calculateOrientation(int angle) {
        if ((angle >= 45 && angle <= 135)) {
            return 90; //landscape
        } else if ((angle > 135 && angle < 225)) {
            return 180; //"Reverse Landscape";
        } else if ((angle >= 225 && angle <= 315)) {
            return 270; // "Portrait";
        } else if (angle > 315 || angle < 45) {
            return 0; //"Reverse Portrait";
        } else {
            return 0;
        }
    }

    private void startOrientationListener(){
        this.orientatationListener = new OrientationEventListener(this.applicationContext) {
            @Override
            public void onOrientationChanged(int angle) {
                // On the latest versions of Android, 11 and 12, we keep receiving this listener
                // all the time, each time the orientation has changed just a little bit.
                // This way we are preventing to just change the capture format
                // when it changes between landscape and portrait.
                //int newOrientation = applicationContext.getResources().getConfiguration().orientation;
                Logging.d(TAG, "ORIENTATION LISTENER NEW ORIENTATION: " + angle);
                angleRotation = angle;
                /*if (currentOrientation == newOrientation) {
                    return
                }
                currentOrientation = newOrientation
                try {
                    val screenDimensions = getScreenDimension()
                    changeCaptureFormat(screenDimensions)
                } catch (ex: Exception) {
                    Log.e(TAG, "Failed when trying to change the capture format!")
                }*/
            }
        };
        if (this.orientatationListener.canDetectOrientation()) {
            this.orientatationListener.enable();
        }
    }

    private void start() {
        this.checkIsOnCameraThread();
        Logging.d("Camera2Session", "start");

        try {
            this.cameraCharacteristics = this.cameraManager.getCameraCharacteristics(this.cameraId);
        } catch (IllegalArgumentException | CameraAccessException var2) {
            this.reportError("getCameraCharacteristics(): " + var2.getMessage());
            return;
        }

        this.cameraOrientation = (Integer)this.cameraCharacteristics.get(CameraCharacteristics.SENSOR_ORIENTATION);
        this.isCameraFrontFacing = (Integer)this.cameraCharacteristics.get(CameraCharacteristics.LENS_FACING) == 0;
        this.findCaptureFormat();
        if (this.captureFormat != null) {
            this.openCamera();
        }
    }

    private void findCaptureFormat() {
        this.checkIsOnCameraThread();
        Range<Integer>[] fpsRanges = (Range[])this.cameraCharacteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES);
        this.fpsUnitFactor = Camera2Enumerator.getFpsUnitFactor(fpsRanges);
        List<CameraEnumerationAndroid.CaptureFormat.FramerateRange> framerateRanges = Camera2Enumerator.convertFramerates(fpsRanges, this.fpsUnitFactor);
        List<Size> sizes = Camera2Enumerator.getSupportedSizes(this.cameraCharacteristics);
        Logging.d("Camera2Session", "Available preview sizes: " + sizes);
        Logging.d("Camera2Session", "Available fps ranges: " + framerateRanges);
        if (!framerateRanges.isEmpty() && !sizes.isEmpty()) {
            CameraEnumerationAndroid.CaptureFormat.FramerateRange bestFpsRange = CameraEnumerationAndroid.getClosestSupportedFramerateRange(framerateRanges, this.framerate);
            Size bestSize = CameraEnumerationAndroid.getClosestSupportedSize(sizes, this.width, this.height);
            CameraEnumerationAndroid.reportCameraResolution(camera2ResolutionHistogram, bestSize);
            this.captureFormat = new CameraEnumerationAndroid.CaptureFormat(bestSize.width, bestSize.height, bestFpsRange);
            Logging.d("Camera2Session", "Using capture format: " + this.captureFormat);
        } else {
            this.reportError("No supported capture formats.");
        }
    }

    private void openCamera() {
        this.checkIsOnCameraThread();
        Logging.d("Camera2Session", "Opening camera " + this.cameraId);
        this.events.onCameraOpening();

        try {
            this.cameraManager.openCamera(this.cameraId, new CameraStateCallback(), this.cameraThreadHandler);
        } catch (IllegalArgumentException | SecurityException | CameraAccessException var2) {
            this.reportError("Failed to open camera: " + var2);
        }
    }

    public void stop() {
        Logging.d("Camera2Session", "Stop camera2 session on camera " + this.cameraId);
        this.checkIsOnCameraThread();
        if (this.state != DailyCamera2Session.SessionState.STOPPED) {
            long stopStartTime = System.nanoTime();
            this.state = DailyCamera2Session.SessionState.STOPPED;
            this.stopInternal();
            int stopTimeMs = (int) TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - stopStartTime);
            camera2StopTimeMsHistogram.addSample(stopTimeMs);
        }
        if(this.orientatationListener != null){
            this.orientatationListener.disable();
        }
    }

    private void stopInternal() {
        Logging.d("Camera2Session", "Stop internal");
        this.checkIsOnCameraThread();
        this.surfaceTextureHelper.stopListening();
        if (this.captureSession != null) {
            this.captureSession.close();
            this.captureSession = null;
        }

        if (this.surface != null) {
            this.surface.release();
            this.surface = null;
        }

        if (this.cameraDevice != null) {
            this.cameraDevice.close();
            this.cameraDevice = null;
        }

        Logging.d("Camera2Session", "Stop done");
    }

    private void reportError(String error) {
        this.checkIsOnCameraThread();
        Logging.e("Camera2Session", "Error: " + error);
        boolean startFailure = this.captureSession == null && this.state != DailyCamera2Session.SessionState.STOPPED;
        this.state = DailyCamera2Session.SessionState.STOPPED;
        this.stopInternal();
        if (startFailure) {
            this.callback.onFailure(FailureType.ERROR, error);
        } else {
            this.events.onCameraError(this, error);
        }

    }


    /*PORTRAIT -> 0
    LANDSCAPE_RIGHT -> 90
    PORTRAIT_UPSIDE_DOWN -> 180
    LANDSCAPE_LEFT -> 270*/
    private int getFrameOrientation() {
        // TODO lock the expected orientation here
        int rotation = 360 - this.calculateOrientation(this.angleRotation);
        //int rotation = 90;
        //int rotation = CameraSession.getDeviceOrientation(this.applicationContext);

        if (!this.isCameraFrontFacing) {
            rotation = 360 - rotation;
        }

        int frameOrientation = (this.cameraOrientation + rotation) % 360;
        Log.d(TAG, "ROTATION: " + rotation + " CAMERA_ORIENTATION: " + this.cameraOrientation + " RESULT: " + frameOrientation);

        return frameOrientation;
    }

    private void checkIsOnCameraThread() {
        if (Thread.currentThread() != this.cameraThreadHandler.getLooper().getThread()) {
            throw new IllegalStateException("Wrong thread");
        }
    }

    static {
        camera2ResolutionHistogram = Histogram.createEnumeration("WebRTC.Android.Camera2.Resolution", CameraEnumerationAndroid.COMMON_RESOLUTIONS.size());
    }

    private static class CameraCaptureCallback extends CameraCaptureSession.CaptureCallback {
        private CameraCaptureCallback() {
        }

        public void onCaptureFailed(CameraCaptureSession session, CaptureRequest request, CaptureFailure failure) {
            Logging.d("Camera2Session", "Capture failed: " + failure);
        }
    }

    private class CaptureSessionCallback extends CameraCaptureSession.StateCallback {
        private CaptureSessionCallback() {
        }

        public void onConfigureFailed(CameraCaptureSession session) {
            DailyCamera2Session.this.checkIsOnCameraThread();
            session.close();
            DailyCamera2Session.this.reportError("Failed to configure capture session.");
        }

        public void onConfigured(CameraCaptureSession session) {
            DailyCamera2Session.this.checkIsOnCameraThread();
            Logging.d("Camera2Session", "Camera capture session configured.");
            DailyCamera2Session.this.captureSession = session;

            try {
                CaptureRequest.Builder captureRequestBuilder = DailyCamera2Session.this.cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_RECORD);
                captureRequestBuilder.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, new Range(DailyCamera2Session.this.captureFormat.framerate.min / DailyCamera2Session.this.fpsUnitFactor, DailyCamera2Session.this.captureFormat.framerate.max / DailyCamera2Session.this.fpsUnitFactor));
                captureRequestBuilder.set(CaptureRequest.CONTROL_AE_MODE, 1);
                captureRequestBuilder.set(CaptureRequest.CONTROL_AE_LOCK, false);
                this.chooseStabilizationMode(captureRequestBuilder);
                this.chooseFocusMode(captureRequestBuilder);
                captureRequestBuilder.addTarget(DailyCamera2Session.this.surface);
                session.setRepeatingRequest(captureRequestBuilder.build(), new CameraCaptureCallback(), DailyCamera2Session.this.cameraThreadHandler);
            } catch (CameraAccessException var3) {
                DailyCamera2Session.this.reportError("Failed to start capture request. " + var3);
                return;
            }

            DailyCamera2Session.this.surfaceTextureHelper.startListening((frame) -> {
                DailyCamera2Session.this.checkIsOnCameraThread();
                if (DailyCamera2Session.this.state != DailyCamera2Session.SessionState.RUNNING) {
                    Logging.d("Camera2Session", "Texture frame captured but camera is no longer running.");
                } else {
                    if (!DailyCamera2Session.this.firstFrameReported) {
                        DailyCamera2Session.this.firstFrameReported = true;
                        int startTimeMs = (int)TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - DailyCamera2Session.this.constructionTimeNs);
                        DailyCamera2Session.camera2StartTimeMsHistogram.addSample(startTimeMs);
                    }

                    //TODO lock the camera orientation here
                    //VideoFrame modifiedFrame = new VideoFrame(CameraSession.createTextureBufferWithModifiedTransformMatrix((TextureBufferImpl)frame.getBuffer(), DailyCamera2Session.this.isCameraFrontFacing, -DailyCamera2Session.this.cameraOrientation), DailyCamera2Session.this.getFrameOrientation(), frame.getTimestampNs());
                    int frameRotation = getFrameOrientation();
                    int matrixRotation = -(DailyCamera2Session.this.cameraOrientation);
                    VideoFrame modifiedFrame = new VideoFrame(fixedOrientationCreateTextureBufferWithModifiedTransformMatrix((TextureBufferImpl)frame.getBuffer(), DailyCamera2Session.this.isCameraFrontFacing, matrixRotation), frameRotation, frame.getTimestampNs());
                    DailyCamera2Session.this.events.onFrameCaptured(DailyCamera2Session.this, modifiedFrame);
                    modifiedFrame.release();
                }
            });
            Logging.d("Camera2Session", "Camera device successfully started.");
            DailyCamera2Session.this.callback.onDone(DailyCamera2Session.this);
        }

        VideoFrame.TextureBuffer fixedOrientationCreateTextureBufferWithModifiedTransformMatrix(TextureBufferImpl buffer, boolean mirror, int rotation) {
            Matrix transformMatrix = new Matrix();
            transformMatrix.preTranslate(0.5F, 0.5F);
            if (mirror) {
               transformMatrix.preScale(-1.0F, 1.0F);
            }
            /*if (!DailyCamera2Session.this.isCameraFrontFacing) {
                rotation = 360 - rotation;
            }*/
            transformMatrix.preRotate((float)rotation);
            transformMatrix.preTranslate(-0.5F, -0.5F);
            return buffer.applyTransformMatrix(transformMatrix, buffer.getWidth(), buffer.getHeight());
        }

        private void chooseStabilizationMode(CaptureRequest.Builder captureRequestBuilder) {
            int[] availableOpticalStabilization = (int[])DailyCamera2Session.this.cameraCharacteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION);
            int[] availableVideoStabilization;
            int var5;
            int mode;
            if (availableOpticalStabilization != null) {
                availableVideoStabilization = availableOpticalStabilization;
                int var4 = availableOpticalStabilization.length;

                for(var5 = 0; var5 < var4; ++var5) {
                    mode = availableVideoStabilization[var5];
                    if (mode == 1) {
                        captureRequestBuilder.set(CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE, 1);
                        captureRequestBuilder.set(CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE, 0);
                        Logging.d("Camera2Session", "Using optical stabilization.");
                        return;
                    }
                }
            }

            availableVideoStabilization = (int[])DailyCamera2Session.this.cameraCharacteristics.get(CameraCharacteristics.CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES);
            if (availableVideoStabilization != null) {
                int[] var8 = availableVideoStabilization;
                var5 = availableVideoStabilization.length;

                for(mode = 0; mode < var5; ++mode) {
                    int modex = var8[mode];
                    if (modex == 1) {
                        captureRequestBuilder.set(CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE, 1);
                        captureRequestBuilder.set(CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE, 0);
                        Logging.d("Camera2Session", "Using video stabilization.");
                        return;
                    }
                }
            }

            Logging.d("Camera2Session", "Stabilization not available.");
        }

        private void chooseFocusMode(CaptureRequest.Builder captureRequestBuilder) {
            int[] availableFocusModes = (int[])DailyCamera2Session.this.cameraCharacteristics.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES);
            int[] var3 = availableFocusModes;
            int var4 = availableFocusModes.length;

            for(int var5 = 0; var5 < var4; ++var5) {
                int mode = var3[var5];
                if (mode == 3) {
                    captureRequestBuilder.set(CaptureRequest.CONTROL_AF_MODE, 3);
                    Logging.d("Camera2Session", "Using continuous video auto-focus.");
                    return;
                }
            }

            Logging.d("Camera2Session", "Auto-focus is not available.");
        }
    }

    private class CameraStateCallback extends CameraDevice.StateCallback {
        private CameraStateCallback() {
        }

        private String getErrorDescription(int errorCode) {
            switch (errorCode) {
                case 1:
                    return "Camera device is in use already.";
                case 2:
                    return "Camera device could not be opened because there are too many other open camera devices.";
                case 3:
                    return "Camera device could not be opened due to a device policy.";
                case 4:
                    return "Camera device has encountered a fatal error.";
                case 5:
                    return "Camera service has encountered a fatal error.";
                default:
                    return "Unknown camera error: " + errorCode;
            }
        }

        public void onDisconnected(CameraDevice camera) {
            DailyCamera2Session.this.checkIsOnCameraThread();
            boolean startFailure = DailyCamera2Session.this.captureSession == null && DailyCamera2Session.this.state != DailyCamera2Session.SessionState.STOPPED;
            DailyCamera2Session.this.state = DailyCamera2Session.SessionState.STOPPED;
            DailyCamera2Session.this.stopInternal();
            if (startFailure) {
                DailyCamera2Session.this.callback.onFailure(FailureType.DISCONNECTED, "Camera disconnected / evicted.");
            } else {
                DailyCamera2Session.this.events.onCameraDisconnected(DailyCamera2Session.this);
            }

        }

        public void onError(CameraDevice camera, int errorCode) {
            DailyCamera2Session.this.checkIsOnCameraThread();
            DailyCamera2Session.this.reportError(this.getErrorDescription(errorCode));
        }

        public void onOpened(CameraDevice camera) {
            DailyCamera2Session.this.checkIsOnCameraThread();
            Logging.d("Camera2Session", "Camera opened.");
            DailyCamera2Session.this.cameraDevice = camera;
            DailyCamera2Session.this.surfaceTextureHelper.setTextureSize(DailyCamera2Session.this.captureFormat.width, DailyCamera2Session.this.captureFormat.height);
            DailyCamera2Session.this.surface = new Surface(DailyCamera2Session.this.surfaceTextureHelper.getSurfaceTexture());

            try {
                camera.createCaptureSession(Arrays.asList(DailyCamera2Session.this.surface), DailyCamera2Session.this.new CaptureSessionCallback(), DailyCamera2Session.this.cameraThreadHandler);
            } catch (CameraAccessException var3) {
                DailyCamera2Session.this.reportError("Failed to create capture session. " + var3);
            }
        }

        public void onClosed(CameraDevice camera) {
            DailyCamera2Session.this.checkIsOnCameraThread();
            Logging.d("Camera2Session", "Camera device closed.");
            DailyCamera2Session.this.events.onCameraClosed(DailyCamera2Session.this);
        }
    }

    private static enum SessionState {
        RUNNING,
        STOPPED;

        private SessionState() {
        }
    }
}
