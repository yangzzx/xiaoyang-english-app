package com.xiaoyang.studyenglish;

import android.app.Activity;
import android.app.Dialog;
import android.view.View;
import android.view.ViewTreeObserver;

/** Animate the entire sheet from its first measured frame, including its glass. */
final class SheetMotion {
    static void open(Activity a,Dialog dialog){
        if(!AppMotion.enabled(a))return;
        View surface=dialog.getWindow().getDecorView();
        surface.getViewTreeObserver().addOnPreDrawListener(new ViewTreeObserver.OnPreDrawListener(){
            public boolean onPreDraw(){
                surface.getViewTreeObserver().removeOnPreDrawListener(this);
                surface.setTranslationY(surface.getHeight());
                surface.animate().translationY(0).setDuration(260).setInterpolator(AppMotion.SHEET).withLayer().start();
                return true;
            }
        });
    }
    static void close(Activity a,Dialog dialog,Runnable end){
        View surface=dialog.getWindow().getDecorView();surface.animate().cancel();
        if(!AppMotion.enabled(a)){end.run();return;}
        surface.animate().translationY(surface.getHeight()).setDuration(190).setInterpolator(AppMotion.EXIT).withLayer().withEndAction(end).start();
    }
    private SheetMotion(){}
}
