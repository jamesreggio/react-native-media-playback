import {NativeModules, NativeEventEmitter} from 'react-native';
import debounce from 'lodash.debounce';

const NativePlayback = NativeModules.RNMediaPlayback;
const NativeEvents = new NativeEventEmitter(NativePlayback);
const nativeDebounce = 50;

let nextKey = 0;
let activeItem = null;

export class PlaybackItem {
  constructor(url) {
    this.status = 'INITIALIZED';
    this.key = nextKey++;
    this.url = url;
  }

  requireStatus(...values) {
    const {status} = this;
    if (!values.includes(status)) {
      throw Error(`Unexpected status: ${status}`);
    }
  }

  addListener(callback) {
    callback = debounce(callback, nativeDebounce);
    let lastStatus;

    return NativeEvents.addListener('updated', payload => {
      if (activeItem !== this) {
        return;
      }

      if (lastStatus !== payload.status) {
        callback.flush();
      }

      lastStatus = payload.status;
      callback(payload);
    });
  }

  removeListener(subscription) {
    NativeEvents.removeListener(subscription);
  }

  async prepare(options = {}) {
    this.requireStatus('INITIALIZED');
    const {key, url} = this;
    const {duration} = await NativePlayback.prepareItem(key, url, options);
    this.status = 'PREPARED';
    return {duration};
  }

  async activate(options = {}) {
    const {status, key} = this;

    if (status === 'INITIALIZED') {
      await this.prepare(options);
    }

    if (activeItem) {
      await activeItem.release();
    }

    this.requireStatus('PREPARED');
    await NativePlayback.activateItem(key, options);
    this.status = 'ACTIVATED';
    activeItem = this;
  }

  async release() {
    const {status, key} = this;

    if (status !== 'RELEASED') {
      this.status = 'RELEASED';
      await NativePlayback.releaseItem(key);

      if (activeItem === this) {
        activeItem = null;
      }
    }
  }

  async play() {
    this.requireStatus('ACTIVATED');
    await NativePlayback.play();
  }

  async pause() {
    this.requireStatus('ACTIVATED');
    await NativePlayback.pause();
  }

  async seek(position) {
    this.requireStatus('PREPARED', 'ACTIVATED');
    return await NativePlayback.seekItem(this.key, position);
  }

  async getPosition() {
    this.requireStatus('ACTIVATED');
    return await NativePlayback.getPosition();
  }

  async getDuration() {
    this.requireStatus('PREPARED', 'ACTIVATED');
    return await NativePlayback.getDurationForItem(this.key);
  }

  async getStatus() {
    this.requireStatus('ACTIVATED');
    return await NativePlayback.getStatus();
  }

  async setBuffer(amount) {
    this.requireStatus('PREPARED', 'ACTIVATED');
    await NativePlayback.setBufferForItem(this.key, amount);
  }

  async setRate(rate) {
    this.requireStatus('ACTIVATED');
    await NativePlayback.setRate(rate);
  }
}
