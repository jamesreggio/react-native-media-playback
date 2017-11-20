package com.jamesreggio.react.media;

import android.media.AudioManager;
import android.media.MediaPlayer;
import android.os.Build;

import com.facebook.infer.annotation.Assertions;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableMap;

import java.io.IOException;
import java.util.Timer;
import java.util.TimerTask;

public class MediaPlaybackItem {

  public final int DEFAULT_UPDATE_INTERVAL = 30000;
  public final int BOUNDARY_UPDATE_INTERVAL = 1000;

  private final Integer key;
  private final MediaPlaybackManager manager;

  private MediaPlayer player;
  private boolean buffering;
  private OnPreparedListener preparedListener;
  private OnSeekCompleteListener seekCompleteListener;

  private Timer intervalTimer;
  private TimerTask intervalTask;
  private Integer updateInterval;

  private Timer boundaryTimer;
  private TimerTask boundaryTask;
  private ReadableArray updateBoundaries;

  /**
   * Listener interfaces
   */

  public interface OnPreparedListener {
    void onPrepared(Throwable error);
  }

  public interface OnSeekCompleteListener {
    void onSeekComplete(boolean finished);
  }

  /**
   * Constructors
   */

  public MediaPlaybackItem(
    final Integer key,
    final MediaPlaybackManager manager
  ) {
    this.key = key;
    this.manager = manager;
  }

  public void destroy() {
    if (this.intervalTimer != null) {
      this.intervalTimer.cancel();
      this.intervalTimer = null;
    }

    if (this.boundaryTimer != null) {
      this.boundaryTimer.cancel();
      this.boundaryTimer = null;
    }

    if (this.player != null) {
      this.player.release();
      this.player = null;
    }
  }

  /**
   * Events and timers
   */

  private void sendUpdate() {
    this.sendUpdate(this.getStatus());
  }

  private void sendUpdate(String status) {
    final WritableMap body = Arguments.createMap();
    body.putInt("key", this.key);
    body.putInt("position", this.getPosition());
    body.putString("status", status);
    this.manager.emit("updated", body);
  }

  private TimerTask getIntervalTask() {
    final MediaPlaybackItem item = this;

    return new TimerTask() {
      @Override
      public void run() {
        item.sendUpdate();
      }
    };
  }

  private TimerTask getBoundaryTask() {
    final MediaPlaybackItem item = this;

    return new TimerTask() {
      private Integer lastPosition;

      @Override
      public void run() {
        final Integer position = item.getPosition();

        if (lastPosition == null) {
          lastPosition = position;
          return;
        }

        int size = item.updateBoundaries.size();
        for (int i = 0; i < size; i++) {
          final Integer boundary = updateBoundaries.getInt(i);
          if (
            (boundary > lastPosition && boundary < position) ||
            (boundary > position && boundary < lastPosition)
          ) {
            item.sendUpdate();
            return;
          }
        }
      }
    };
  }

  //XXX adjust intervals for rate?
  private void startTimers() {
    if (this.intervalTask == null && this.intervalTimer != null) {
      this.intervalTask = this.getIntervalTask();
      this.intervalTimer.scheduleAtFixedRate(
        this.intervalTask, 0, this.updateInterval
      );
    }

    if (this.boundaryTask == null && this.boundaryTimer != null) {
      this.boundaryTask = this.getBoundaryTask();
      this.boundaryTimer.scheduleAtFixedRate(
        this.boundaryTask, 0, BOUNDARY_UPDATE_INTERVAL
      );
    }
  }

  private void stopTimers() {
    if (this.intervalTask != null) {
      this.intervalTask.cancel();
      this.intervalTask = null;
    }

    if (this.boundaryTask != null) {
      this.boundaryTask.cancel();
      this.boundaryTask = null;
    }
  }

  /**
   * Lifecycle
   */

  public void prepare(
    final ReadableMap options,
    final OnPreparedListener listener
  ) {
    Assertions.assertCondition(this.player == null, "Item already prepared");

    try {
      this.player = new MediaPlayer();
      this.player.setAudioStreamType(AudioManager.STREAM_MUSIC); //XXX?
      this.player.setDataSource(options.getString("url"));
    } catch (IOException error) {
      if (listener != null) {
        listener.onPrepared(error);
      }

      this.player = null;
      return;
    }

    final MediaPlaybackItem item = this;
    this.preparedListener = listener;

    this.player.setOnPreparedListener(new MediaPlayer.OnPreparedListener() {
      @Override
      public void onPrepared(final MediaPlayer player) {
        if (item.preparedListener != null) {
          item.preparedListener.onPrepared(null);
          item.preparedListener = null;
        }
      }
    });

    this.player.setOnCompletionListener(new MediaPlayer.OnCompletionListener() {
      @Override
      public void onCompletion(final MediaPlayer player) {
        item.sendUpdate("FINISHED");
      }
    });

    this.player.setOnErrorListener(new MediaPlayer.OnErrorListener() {
      @Override
      public boolean onError(
        final MediaPlayer player,
        final int what,
        final int extra
      ) {
        //XXX pass what, extra

        if (item.preparedListener != null) {
          item.preparedListener.onPrepared(null);
          item.preparedListener = null;
        } else {
          item.sendUpdate("FINISHED");
        }

        return true;
      }
    });

    this.player.setOnInfoListener(new MediaPlayer.OnInfoListener() {
      @Override
      public boolean onInfo(
        final MediaPlayer player,
        final int what,
        final int extra
      ) {
        if (what == MediaPlayer.MEDIA_INFO_BUFFERING_START) {
          item.buffering = true;
          item.sendUpdate();
          return true;
        }

        if (what == MediaPlayer.MEDIA_INFO_BUFFERING_END) {
          item.buffering = false;
          item.sendUpdate();
          return true;
        }

        return false;
      }
    });

    this.player.setOnSeekCompleteListener(new MediaPlayer.OnSeekCompleteListener() {
      @Override
      public void onSeekComplete(final MediaPlayer player) {
        if (item.seekCompleteListener == null) {
          return;
        }

        item.seekCompleteListener.onSeekComplete(true);
        item.seekCompleteListener = null;
        item.sendUpdate();
      }
    });

    this.player.prepareAsync();
  }

  public void activate(final ReadableMap options) {
    Assertions.assertCondition(this.player != null, "Item not prepared");
    Assertions.assertCondition(this.intervalTimer == null, "Item already activated");

    if (options.hasKey("position") && !options.isNull("position")) {
      this.seekTo(options.getInt("position"), null);
    }

    if (options.hasKey("rate") && !options.isNull("rate")) {
      this.setRate(options.getDouble("rate"));
    }

    this.intervalTimer = new Timer();

    this.updateInterval = (
      !options.hasKey("updateInterval") || options.isNull("updateInterval")
        ? DEFAULT_UPDATE_INTERVAL
        : options.getInt("updateInterval")
    );

    if (options.hasKey("updateBoundaries") && !options.isNull("updateBoundaries")) {
      this.updateBoundaries = options.getArray("updateBoundaries");
      this.boundaryTimer = new Timer();
    }
  }

  public void deactivate(final ReadableMap options) {
    Assertions.assertCondition(this.player != null, "Item not prepared");
    Assertions.assertCondition(this.intervalTimer != null, "Item not activated");
    this.pause();

    if (this.intervalTimer != null) {
      this.intervalTimer.cancel();
      this.intervalTimer = null;
    }

    if (this.boundaryTimer != null) {
      this.boundaryTimer.cancel();
      this.boundaryTimer = null;
    }
  }

  public void release(final ReadableMap options) {
    Assertions.assertCondition(this.player != null, "Item not prepared");

    this.player.release();
    this.player = null;
  }

  /**
   * Playback controls
   */

  public void play() {
    Assertions.assertNotNull(this.player).start();
    this.startTimers();
  }

  public void pause() {
    Assertions.assertNotNull(this.player).pause();
    this.stopTimers();
    this.sendUpdate();
  }

  public void seekTo(
    final Integer position,
    final OnSeekCompleteListener listener
  ) {
    if (this.seekCompleteListener != null) {
      this.seekCompleteListener.onSeekComplete(false);
    }

    this.seekCompleteListener = listener;
    Assertions.assertNotNull(this.player).seekTo(position * 1000);
  }

  public void skipBy(
    final Integer interval,
    final OnSeekCompleteListener listener
  ) {
    int position = this.getPosition() + interval;
    position = Math.max(0, position);
    position = Math.min(position, this.getDuration());
    this.seekTo(position, listener);
  }

  public void setRate(final Double rate) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      final MediaPlayer player = Assertions.assertNotNull(this.player);

      player.setPlaybackParams(
        player.getPlaybackParams().setSpeed(rate.floatValue())
      );
    }
  }

  public void setBuffer(final Integer duration) {
    // Not possible on Android.
  }

  /**
   * Playback properties
   */

  public String getStatus() {
    if (this.player == null) {
      return "IDLE";
    }

    if (this.buffering) {
      return "STALLED";
    }

    return this.player.isPlaying() ? "PLAYING" : "PAUSED";
  }

  public Integer getPosition() {
    return Assertions.assertNotNull(this.player).getCurrentPosition() / 1000;
  }

  public Integer getDuration() {
    return Assertions.assertNotNull(this.player).getDuration() / 1000;
  }

}
