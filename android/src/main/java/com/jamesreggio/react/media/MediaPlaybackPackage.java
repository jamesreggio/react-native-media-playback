package com.jamesreggio.react.media;

import com.facebook.react.ReactPackage;
import com.facebook.react.bridge.NativeModule;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.uimanager.ViewManager;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public class MediaPlaybackPackage implements ReactPackage {

  @Override
  public List<ViewManager> createViewManagers(final ReactApplicationContext context) {
    return Collections.emptyList();
  }

  @Override
  public List<NativeModule> createNativeModules(final ReactApplicationContext context) {
    List<NativeModule> modules = new ArrayList<>();
    modules.add(new MediaPlaybackManager(context));
    return modules;
  }

}
