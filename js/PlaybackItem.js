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
 * Lifecycle states machine.
 */

const states = {
  instantiated: {
    async prepare(options = {}) {
      await this._prepare(options);
      return ['prepared', this.prepared];
    },

    async activate(options = {}) {
      await this._prepare(options);
      await this._activate(options);
      return ['activated', this.activated];
    },

    deactivate() {
      return ['instantiated'];
    },

    release() {
      return ['released'];
    },
  },

  prepared: {
    prepare() {
      return ['prepared', this.prepared];
    },

    async activate(options = {}) {
      await this._activate(options);
      return ['activated', ...this.activated];
    },

    deactivate() {
      return ['prepared'];
    },

    async release() {
      await this._release();
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

    async deactivate() {
      await this._deactivate();
      return ['prepared'];
    },

    async release() {
      await this._release();
      return ['released'];
    },
  },

  released: {
    prepare() {
      throw Error('PlaybackItem is already released');
    },

    activate() {
      throw Error('PlaybackItem is already released');
    },

    deactivate() {
      throw Error('PlaybackItem is already released');
    },

    release() {
      return ['released'];
    },
  },
};

/**
 * PlaybackItem encapsulates the lifecycle, playback controls, and events for
 * a playable media item.
 */

export default class PlaybackItem {
  constructor(url) {
    this.url = url;
    this.key = nextKey++;
    this.fsm = new FiniteStateMachine(states, 'instantiated', this);
  }

  /**
   * Events subscriptions.
   */

  addListener(callback) {
    callback = debounce(callback, nativeDebounce);

    let lastStatus;
    return NativeEvents.addListener('updated', (payload) => {
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

  /**
   * Public lifecycle transitions.
   */

  prepare(options = {}) {
    return this.fsm.next('prepare', options);
  }

  activate(options = {}) {
    return this.fsm.next('activate', options);
  }

  deactivate() {
    return this.fsm.next('deactivate');
  }

  release() {
    return this.fsm.next('release');
  }

  /**
   * Private lifecycle transitions.
   */

  _prepare(options) {
    const {key, url} = this;
    this.prepared = await NativeModule.prepareItem(key, url, options);
  }

  _activate(options) {
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

  _deactivate() {
    invariant(activeItem === this);
    await NativeModule.deactivateItem(this.key, options);
    activeItem = null;
  }

  _release() {
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
    await NativeModule.play();
  }

  async pause() {
    this.requireState('activated');
    await NativeModule.pause();
  }

  async seek(position) {
    this.requireState('prepared', 'activated');
    return await NativeModule.seekItem(this.key, position);
  }

  async getPosition() {
    this.requireState('activated');
    return await NativeModule.getPosition();
  }

  async getDuration() {
    this.requireState('prepared', 'activated');
    return await NativeModule.getDurationForItem(this.key);
  }

  async getStatus() {
    this.requireState('activated');
    return await NativeModule.getStatus();
  }

  async setBuffer(amount) {
    this.requireState('prepared', 'activated');
    await NativeModule.setBufferForItem(this.key, amount);
  }

  async setRate(rate) {
    this.requireState('activated');
    await NativeModule.setRate(rate);
  }
}
