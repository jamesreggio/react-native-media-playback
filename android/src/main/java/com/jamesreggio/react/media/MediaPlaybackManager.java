package com.jamesreggio.react.media;

import com.facebook.infer.annotation.Assertions;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.JavaScriptModule;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableMap;

import java.util.HashMap;

import javax.annotation.Nullable;

public class MediaPlaybackManager extends ReactContextBaseJavaModule {

  private final ReactApplicationContext context;
  private final HashMap<Integer, MediaPlaybackItem> items = new HashMap<>();

  /**
   * Constructors
   */

  public MediaPlaybackManager(final ReactApplicationContext context) {
    super(context);
    this.context = context;
  }

  public void destroy() {
    for (final MediaPlaybackItem item : this.items.values()) {
      item.destroy();
    }

    this.items.clear();
  }

  @Override
  public String getName() {
    return "MediaPlaybackManager";
  }

  /**
   * Events
   */

  private interface RCTDeviceEventEmitter extends JavaScriptModule {
    void emit(String eventName, @Nullable Object data);
  }

  protected void emit(final String name) {
    this.emit(name, null);
  }

  protected void emit(final String name, final Object body) {
    this.context
      .getJSModule(MediaPlaybackManager.RCTDeviceEventEmitter.class)
      .emit(name, body);
  }

  /**
   * Session lifecycle
   */

  @ReactMethod
  public void activateSession(
    final Integer key,
    final ReadableMap options,
    final Promise promise
  ) {
    promise.resolve(null); //XXX
  }

  @ReactMethod
  public void deactivateSession(
    final Integer key,
    final ReadableMap options,
    final Promise promise
  ) {
    promise.resolve(null); //XXX
  }

  /**
   * Item lifecycle
   */

  @ReactMethod
  public void prepareItem(
    final Integer key,
    final ReadableMap options,
    final Promise promise
  ) {
    MediaPlaybackItem item = this.items.get(key);

    if (item == null) {
      item = new MediaPlaybackItem(key, this);
      this.items.put(key, item);
    }

    final MediaPlaybackItem finalItem = item;

    item.prepare(options, new MediaPlaybackItem.OnPreparedListener() {
      boolean promiseResolved = false;

      @Override
      public void onPrepared(Throwable error) {
        if (promiseResolved) {
          return;
        }

        promiseResolved = true;

        if (error != null) {
          promise.reject(
            "PLAYBACK_LOAD_FAILURE",
            "The item failed to load",
            error
          );
        } else {
          WritableMap body = Arguments.createMap();
          body.putInt("duration", finalItem.getDuration());
          promise.resolve(body);
        }
      }
    });
  }

  @ReactMethod
  public void activateItem(
    final Integer key,
    final ReadableMap options,
    final Promise promise
  ) {
    final MediaPlaybackItem item = this.items.get(key);
    Assertions.assertNotNull(item).activate(options);
    promise.resolve(null);
  }

  @ReactMethod
  public void deactivateItem(
    final Integer key,
    final ReadableMap options,
    final Promise promise
  ) {
    final MediaPlaybackItem item = this.items.get(key);
    Assertions.assertNotNull(item).deactivate(options);
    promise.resolve(null);
  }

  @ReactMethod
  public void releaseItem(
    final Integer key,
    final ReadableMap options,
    final Promise promise
  ) {
    final MediaPlaybackItem item = this.items.get(key);
    Assertions.assertNotNull(item).release(options);
    promise.resolve(null);
  }

  /**
   * Item playback controls
   */

  @ReactMethod
  public void playItem(
    final Integer key,
    final Promise promise
  ) {
    final MediaPlaybackItem item = this.items.get(key);
    Assertions.assertNotNull(item).play();
    promise.resolve(null);
  }

  @ReactMethod
  public void pauseItem(
    final Integer key,
    final Promise promise
  ) {
    final MediaPlaybackItem item = this.items.get(key);
    Assertions.assertNotNull(item).pause();
    promise.resolve(null);
  }

  @ReactMethod
  public void seekItem(
    final Integer key,
    final Integer position,
    final Promise promise
  ) {
    final MediaPlaybackItem item = this.items.get(key);

    Assertions.assertNotNull(item).seekTo(
      position,
      new MediaPlaybackItem.OnSeekCompleteListener() {
        boolean promiseResolved = false;

        @Override
        public void onSeekComplete(boolean finished) {
          if (promiseResolved) {
            return;
          }

          promiseResolved = true;
          promise.resolve(finished);
        }
      }
    );
  }

  @ReactMethod
  public void setRateForItem(
    final Integer key,
    final Double rate,
    final Promise promise
  ) {
    final MediaPlaybackItem item = this.items.get(key);
    Assertions.assertNotNull(item).setRate(rate);
    promise.resolve(null);
  }

  @ReactMethod
  public void setBufferForItem(
    final Integer key,
    final Integer duration,
    final Promise promise
  ) {
    final MediaPlaybackItem item = this.items.get(key);
    Assertions.assertNotNull(item).setBuffer(duration);
    promise.resolve(null);
  }

  /**
   * Item playback properties
   */

  @ReactMethod
  public void getStatusForItem(
    final Integer key,
    final Promise promise
  ) {
    final MediaPlaybackItem item = this.items.get(key);
    final String status = Assertions.assertNotNull(item).getStatus();
    promise.resolve(status);
  }

  @ReactMethod
  public void getPositionForItem(
    final Integer key,
    final Promise promise
  ) {
    final MediaPlaybackItem item = this.items.get(key);
    final Integer position = Assertions.assertNotNull(item).getPosition();
    promise.resolve(position);
  }

  @ReactMethod
  public void getDurationForItem(
    final Integer key,
    final Promise promise
  ) {
    final MediaPlaybackItem item = this.items.get(key);
    final Integer duration = Assertions.assertNotNull(item).getDuration();
    promise.resolve(duration);
  }

}
