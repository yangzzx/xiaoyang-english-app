package com.xiaoyang.studyenglish;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.view.View;
import android.webkit.WebView;
import android.widget.FrameLayout;
import android.widget.ImageView;

/** Keep the last rendered frame only until WebView commits the next document. */
final class PageTransition {
    private final Activity activity;
    private final FrameLayout host;
    private final WebView web;
    private ImageView cover;
    private Bitmap bitmap;
    private boolean committed;
    private int generation;
    private final Runnable timeout=this::clear;
    PageTransition(Activity activity,FrameLayout host,WebView web){this.activity=activity;this.host=host;this.web=web;}
    void start(){
        generation++;host.removeCallbacks(timeout);web.animate().cancel();
        if(cover!=null){cover.animate().cancel();cover.setAlpha(1);cover.setTranslationX(0);web.setTranslationX(0);web.setAlpha(0);host.postDelayed(timeout,1800);return;} // Rapid taps retain the last stable frame.
        if(!committed||!AppMotion.enabled(activity)||web.getWidth()==0||web.getHeight()==0)return;
        try{
            float scale=Math.min(1f,(float)Math.sqrt(1000000d/(web.getWidth()*(double)web.getHeight())));
            bitmap=Bitmap.createBitmap(Math.max(1,Math.round(web.getWidth()*scale)),Math.max(1,Math.round(web.getHeight()*scale)),Bitmap.Config.ARGB_8888);
            Canvas canvas=new Canvas(bitmap);canvas.scale(scale,scale);web.draw(canvas);
            cover=new ImageView(activity);cover.setImageBitmap(bitmap);cover.setScaleType(ImageView.ScaleType.FIT_XY);
            cover.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);cover.setClickable(true);
            host.addView(cover,new FrameLayout.LayoutParams(-1,-1));host.postDelayed(timeout,1800);
        }catch(OutOfMemoryError|RuntimeException ignored){clear();}
    }
    void commit(){
        committed=true;if(!AppMotion.enabled(activity)){clear();return;}final int token=generation;
        web.postVisualStateCallback(token,new WebView.VisualStateCallback(){@Override public void onComplete(long id){
            if(token!=generation||cover==null)return;
            host.removeCallbacks(timeout);final ImageView frame=cover;
            float distance=8*activity.getResources().getDisplayMetrics().density;
            web.setAlpha(0);web.setTranslationX(distance);
            web.animate().alpha(1).translationX(0).setDuration(240).setInterpolator(AppMotion.SETTLE).start();
            frame.animate().alpha(0).setDuration(190).setInterpolator(AppMotion.EXIT).withEndAction(()->{if(token==generation)clear();}).start();
            host.postDelayed(timeout,520);
        }});
    }
    void clear(){
        host.removeCallbacks(timeout);web.animate().cancel();web.setTranslationX(0);web.setAlpha(1);
        if(cover!=null){cover.animate().cancel();cover.setImageDrawable(null);host.removeView(cover);cover=null;}
        if(bitmap!=null){bitmap.recycle();bitmap=null;}
    }
}
