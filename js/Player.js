import {NativeModules, NativeEventEmitter, Platform} from 'react-native';
import invariant from './invariant';

const NativeModule = NativeModules.MediaPlaybackManager;
const NativeEvents = new NativeEventEmitter(NativeModule);

/**
 * Global state.
 */

// Native `key` for the next PlaybackItem instance.
let nextKey = 0;

/**
 * Each Player manages playback for multiple tracks.
 */

export default class Player {
  static async create(options) {
    const player = new Player();
    await NativeModule.createPlayer(player.key, options);
    return player;
  }

  constructor() {
    this.key = nextKey++;
  }

  /**
   * Events.
   */

  static addListener(type, callback) {
    NativeEvents.addListener(type, callback);
  }

  static removeListener(subscription) {
    NativeEvents.removeListener(subscription);
  }

  addListener(type, callback) {
    return NativeEvents.addListener(type, ({key, ...payload}) => {
      if (key !== this.key) {
        return;
      }

      callback(payload);
    });
  }

  removeListener(subscription) {
    NativeEvents.removeListener(subscription);
  }

  /**
   * Asset management.
   */

  static setAssetWaveform(id, waveform) {
    return NativeModule.setAssetWaveform(id, waveform);
  }

  /**
   * Track management.
   */

  insertTracks(tracks, options = {}) {
    invariant(Array.isArray(tracks), 'Expected array of tracks');
    return NativeModule.insertPlayerTracks(this.key, tracks, options);
  }

  replaceTracks(tracks, options = {}) {
    invariant(Array.isArray(tracks), 'Expected array of tracks');
    return NativeModule.replacePlayerTracks(this.key, tracks, options);
  }

  nextTrack() {
    return NativeModule.nextPlayerTrack(this.key);
  }

  /**
   * Playback controls.
   */

  play(options = {}) {
    return NativeModule.playPlayer(this.key, options);
  }

  pause() {
    return NativeModule.pausePlayer(this.key);
  }

  toggle() {
    return NativeModule.togglePlayer(this.key);
  }

  stop() {
    return NativeModule.stopPlayer(this.key);
  }

  seek(position) {
    return NativeModule.seekPlayer(this.key, position);
  }

  skip(interval) {
    return NativeModule.skipPlayer(this.key, interval);
  }

  setRate(rate) {
    return NativeModule.setPlayerRate(this.key, rate);
  }

  setRange(range) {
    return NativeModule.setPlayerRange(this.key, range);
  }
}
