import {NativeModules, NativeEventEmitter} from 'react-native';
import debounce from 'lodash.debounce';

import FiniteStateMachine from './FiniteStateMachine';
import invariant from './invariant';

const NativeModule = NativeModules.MediaPlaybackManager;
const NativeEvents = new NativeEventEmitter(NativeModule);

/**
 * Configuration.
 */

// Debounce native events by this amount (in ms).
// Events are only debounced if they have the same `status`.
const nativeDebounce = 50;

/**
 * Global state.
 */

// Native `key` for the next PlaybackItem instance.
let nextKey = 0;

// Currently active PlaybackItem. (Only one may be active at a given time.)
let activeItem = null;

/**
 * Lifecycle state machine.
 */

const states = {
  released: {
    async prepare(options) {
      await this._prepare(options);
      return ['prepared', this.prepared];
    },

    async activate(options) {
      await this._prepare(options);
      await this._activate(options);
      return ['activated', this.activated];
    },

    deactivate() {
      return ['released'];
    },

    release() {
      return ['released'];
    },
  },

  prepared: {
    prepare() {
      return ['prepared', this.prepared];
    },

    async activate(options) {
      await this._activate(options);
      return ['activated', this.activated];
    },

    deactivate() {
      return ['prepared'];
    },

    async release(options) {
      await this._release(options);
      return ['released'];
    },
  },

  activated: {
    prepare() {
      return ['activated', this.prepared];
    },

    activate() {
      return ['activated', this.activated];
    },

    async deactivate(options) {
      await this._deactivate(options);
      return ['prepared'];
    },

    async release(options) {
      await this._deactivate(options);
      await this._release(options);
      return ['released'];
    },
  },
};

/**
 * PlaybackItem encapsulates the lifecycle, events, playback controls,
 * and properties for a playable media item.
 */

export default class PlaybackItem {
  constructor({url}) {
    invariant(url, 'PlaybackItem requires a URL');
    this.key = nextKey++;
    this.fsm = new FiniteStateMachine(states, 'released', this);
    this.url = url;
  }

  /**
   * Events.
   */

  addListener(callback) {
    callback = debounce(callback, nativeDebounce);

    let lastStatus;
    return NativeEvents.addListener('updated', ({key, ...payload}) => {
      if (this.key !== key) {
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

  /**
   * Lifecycle.
   */

  prepare(options = {}) {
    return this.fsm.next('prepare', options);
  }

  activate(options = {}) {
    return this.fsm.next('activate', options);
  }

  deactivate(options = {}) {
    return this.fsm.next('deactivate', options);
  }

  release(options = {}) {
    return this.fsm.next('release', options);
  }

  /**
   * Private lifecycle implementations.
   */

  async _prepare(options) {
    const {key, url} = this;
    this.prepared = await NativeModule.prepareItem(key, {...options, url});
  }

  async _activate(options) {
    while (activeItem) {
      await activeItem.deactivate();
    }

    activeItem = this;
    this.activated = {
      ...this.prepared,
      ...await NativeModule.activateItem(this.key, options),
    };
    invariant(activeItem === this);
  }

  async _deactivate(options) {
    invariant(activeItem === this);
    await NativeModule.deactivateItem(this.key, options);
    activeItem = null;
  }

  async _release(options) {
    await NativeModule.releaseItem(this.key, options);
  }

  /**
   * Playback controls.
   */

  requireState(...states) {
    invariant(
      states.some(state => state === this.fsm.state),
      `Invalid action for PlaybackItem state: ${this.fsm.state}`,
    );
  }

  async play() {
    this.requireState('activated');
    await NativeModule.playItem(this.key);
  }

  async pause() {
    this.requireState('activated');
    await NativeModule.pauseItem(this.key);
  }

  async seek(position) {
    this.requireState('prepared', 'activated');
    return await NativeModule.seekItem(this.key, position);
  }

  async setRate(rate) {
    this.requireState('prepared', 'activated');
    await NativeModule.setRateForItem(this.key, rate);
  }

  async setBuffer(duration) {
    this.requireState('prepared', 'activated');
    await NativeModule.setBufferForItem(this.key, duration);
  }

  /**
   * Playback properties.
   */

  async getPosition() {
    this.requireState('prepared', 'activated');
    return await NativeModule.getPositionForItem(this.key);
  }

  async getDuration() {
    this.requireState('prepared', 'activated');
    return await NativeModule.getDurationForItem(this.key);
  }

  async getStatus() {
    this.requireState('prepared', 'activated');
    return await NativeModule.getStatusForItem(this.key);
  }
}
