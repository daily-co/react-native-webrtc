import { NativeModules } from 'react-native';

import { addListener } from './EventEmitter';
import getDisplayMedia, { Constraints as DisplayMediaConstraints } from './getDisplayMedia';
import getUserMedia, { Constraints as UserMediaConstraints } from './getUserMedia';
import { Event, EventTarget, getEventAttributeValue, setEventAttributeValue } from './vendor/event-target-shim';

const { WebRTCModule } = NativeModules;

type MediaDevicesEventMap = {
    devicechange: Event<'devicechange'>
}

class MediaDevices extends EventTarget<MediaDevicesEventMap> {
    constructor() {
        super();
        this._registerEvents();
    }

    get ondevicechange() {
        return getEventAttributeValue(this, 'devicechange');
    }

    set ondevicechange(value) {
        setEventAttributeValue(this, 'devicechange', value);
    }

    /**
     * W3C "Media Capture and Streams" compatible {@code enumerateDevices}
     * implementation.
     */
    enumerateDevices() {
        return new Promise(resolve => WebRTCModule.enumerateDevices(resolve));
    }

    /**
     * W3C "Screen Capture" compatible {@code getDisplayMedia} implementation.
     * See: https://w3c.github.io/mediacapture-screen-share/
     *
     * @param {*} constraints
     * @returns {Promise}
     */
    getDisplayMedia(constraints: DisplayMediaConstraints) {
        return getDisplayMedia(constraints);
    }

    /**
     * W3C "Media Capture and Streams" compatible {@code getUserMedia}
     * implementation.
     * See: https://www.w3.org/TR/mediacapture-streams/#dom-mediadevices-enumeratedevices
     *
     * @param {*} constraints
     * @returns {Promise}
     */
    getUserMedia(constraints: UserMediaConstraints) {
        return getUserMedia(constraints);
    }

    _registerEvents(): void {
        console.log('MediaDevices _registerEvents invoked');
        WebRTCModule.startMediaDevicesEventMonitor();
        addListener(this,'mediaDevicesOnDeviceChange', () => {
            console.log('MediaDevices => mediaDevicesOnDeviceChange');
            // @ts-ignore
            this.dispatchEvent(new Event('devicechange'));
        });
    }
}

export default new MediaDevices();
