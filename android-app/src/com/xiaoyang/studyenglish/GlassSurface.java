package com.xiaoyang.studyenglish;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.view.View;
import android.view.Window;

/** Small glass surfaces; long reading lists do not use a live blur. */
final class GlassSurface {
    private static int dp(Activity a,int n){return Math.round(n*a.getResources().getDisplayMetrics().density);}
    static GradientDrawable panel(Activity a){return surface(a,new int[]{0xFAFFFFFF,0xF5EDF4FC},26);}
    static GradientDrawable bar(Activity a){return surface(a,new int[]{0xE6FFFFFF,0xD9EAF2FC},24);}
    private static GradientDrawable surface(Activity a,int[] colors,int radius){
        GradientDrawable d=new GradientDrawable(GradientDrawable.Orientation.TL_BR,colors);
        d.setCornerRadius(dp(a,radius));d.setStroke(dp(a,1),0xE6FFFFFF);return d;
    }
    static void apply(Activity a,Window w,View panel){
        if(Build.VERSION.SDK_INT>=30)w.setDecorFitsSystemWindows(false);
        panel.setOnApplyWindowInsetsListener((v,insets)->{
            v.setPadding(v.getPaddingLeft(),v.getPaddingTop(),v.getPaddingRight(),insets.getSystemWindowInsetBottom());
            return insets;
        });
        panel.requestApplyInsets();
        if(Build.VERSION.SDK_INT>=31&&a.getWindowManager().isCrossWindowBlurEnabled()){
            // OEMs may accept blur without rendering it. Keep enough tint for readable menus.
            w.setBackgroundDrawable(surface(a,new int[]{0xF2FFFFFF,0xF2E2EDF9},26));
            w.setBackgroundBlurRadius(dp(a,26));
            panel.setBackgroundColor(Color.TRANSPARENT);
        }
    }
    private GlassSurface(){}
}
