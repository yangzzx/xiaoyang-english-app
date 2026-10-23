package com.xiaoyang.studyenglish;

import android.app.Activity;
import android.provider.Settings;
import android.view.animation.Interpolator;
import android.view.animation.PathInterpolator;

/** A settled ease for surfaces without bounce or overshoot. */
final class AppMotion {
    static boolean enabled(Activity a){return Settings.Global.getFloat(a.getContentResolver(),Settings.Global.ANIMATOR_DURATION_SCALE,1f)>0;}
    static final Interpolator SETTLE=new PathInterpolator(.22f,1f,.36f,1f);
    static final Interpolator EXIT=new PathInterpolator(.4f,0f,1f,1f);
    static final Interpolator SHEET=new PathInterpolator(.22f,.75f,.36f,1f);
}
