import {NativeModules} from 'react-native';
import invariant from './invariant';

const NativeModule = NativeModules.MediaPlaybackManager;

/**
 * Global state.
 */

// Native `key` for the next PlaybackSession instance.
let nextKey = 0;

/**
 * PlaybackSession encapsulates the lifecycle and metadata for a media playback
 * session, which is comprised of the playback of one or more PlaybackItems.
 */

export default class PlaybackSession {
  constructor({category, mode}) {
    this.key = nextKey++;
    this.active = false;
    this.category = category;
    this.mode = mode;
  }

  /**
   * Lifecycle.
   */

  async activate() {
    const {category, mode} = this;
    invariant(!this.active, 'PlaybackSession already active');
    await NativeModule.activateSession(this.key, {category, mode});
    this.active = true;
  }

  async deactivate() {
    invariant(this.active, 'PlaybackSession not active');
    await NativeModule.deactivateSession(this.key, {});
    this.active = false;
  }
}
