package com.xiaoyang.studyenglish;

import android.app.Activity;
import android.app.Dialog;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.Build;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.MotionEvent;
import android.view.Window;
import android.view.WindowManager;
import android.view.animation.DecelerateInterpolator;
import android.widget.LinearLayout;
import android.widget.ImageView;
import android.widget.ScrollView;
import android.widget.TextView;

/** Course navigation is a grouped surface, independent of the page's study state. */
final class NavigationSheet {
    private static final int INK=0xFF182B43, MUTED=0xFF718098, BLUE=0xFF325ED6;
    private final Activity activity;
    private final String[] names;
    private final int current;
    private final java.util.function.IntConsumer select;
    private final Dialog dialog;
    private LinearLayout panel;
    private LinearLayout contents, categories;
    private ScrollView scroll;
    private int category;
    private boolean closing;
    private final boolean motion;
    private static final String[] HINTS={"继续今天的学习","认识音标与基础发音","用字母组合练习读音","按计划学习词根词缀","每天学习 2 组母词","掌握考试常见词汇","按章节练习拼写","课程视频与照片笔记","系统学习语法知识","历年真题与照片笔记","背诵写作模板","查看到期复习任务","安排每日学习任务"};
    private static final int[] ICONS={R.drawable.nav_house,R.drawable.nav_audio_lines,R.drawable.nav_whole_word,R.drawable.nav_network,R.drawable.nav_library,R.drawable.nav_book_open,R.drawable.nav_spell_check,R.drawable.nav_play,R.drawable.nav_notebook_pen,R.drawable.nav_files,R.drawable.nav_pencil_line,R.drawable.nav_calendar_check_2,R.drawable.nav_calendar_days};
    private static final int[][] GROUPS={{1,2},{3,4,5,7},{8,9,10},{6,12}};
    NavigationSheet(Activity activity,String[] names,int current,java.util.function.IntConsumer select,Runnable onClose){
        this.activity=activity;this.names=names;this.current=current;this.select=select;
        category=0;for(int g=0;g<GROUPS.length;g++)for(int i:GROUPS[g])if(i==current)category=g;
        motion=AppMotion.enabled(activity);
        dialog=new Dialog(activity);dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.setOnDismissListener(d->onClose.run());
    }
    private int dp(int x){return Math.round(x*activity.getResources().getDisplayMetrics().density);}
    private GradientDrawable shape(int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;}
    private TextView text(String value,int size,int color,boolean bold){TextView t=new TextView(activity);t.setText(value);t.setTextSize(size);t.setTextColor(color);t.setFontFeatureSettings("kern");t.setIncludeFontPadding(false);if(bold)t.setTypeface(null,Typeface.BOLD);return t;}
    void show(){
        panel=new LinearLayout(activity);panel.setOrientation(LinearLayout.VERTICAL);panel.setBackground(GlassSurface.panel(activity));panel.setClipToOutline(true);
        LinearLayout grip=new LinearLayout(activity);grip.setGravity(Gravity.CENTER);grip.setContentDescription("下拉关闭导航");View handle=new View(activity);handle.setBackground(shape(0xFFDCE2ED,3));grip.addView(handle,new LinearLayout.LayoutParams(dp(32),dp(4)));panel.addView(grip,new LinearLayout.LayoutParams(-1,dp(32)));
        final float[] drag={0};grip.setOnTouchListener((v,e)->{switch(e.getActionMasked()){case MotionEvent.ACTION_DOWN:drag[0]=e.getRawY();return true;case MotionEvent.ACTION_MOVE:panel.setTranslationY(Math.max(0,e.getRawY()-drag[0]));return true;case MotionEvent.ACTION_UP:if(e.getRawY()-drag[0]>dp(65))dismiss(null);else{v.performClick();panel.animate().translationY(0).setDuration(motion?320:0).setInterpolator(AppMotion.SHEET).start();}return true;case MotionEvent.ACTION_CANCEL:panel.animate().translationY(0).setDuration(motion?320:0).setInterpolator(AppMotion.SHEET).start();return true;}return false;});
        LinearLayout head=new LinearLayout(activity);head.setGravity(Gravity.CENTER_VERTICAL);head.setPadding(dp(22),0,dp(14),0);
        TextView title=text("学习导航",22,INK,true);head.addView(title,new LinearLayout.LayoutParams(0,dp(44),1));title.setGravity(Gravity.CENTER_VERTICAL);
        TextView close=text("×",25,MUTED,false);close.setGravity(Gravity.CENTER);close.setContentDescription("关闭学习导航");close.setBackground(new RippleDrawable(ColorStateList.valueOf(0x18325ED6),shape(0xFFF3F5F9,22),null));close.setOnClickListener(v->dismiss(null));head.addView(close,new LinearLayout.LayoutParams(dp(44),dp(44)));panel.addView(head);
        categories=new LinearLayout(activity);categories.setPadding(dp(18),0,dp(18),0);String[] tabs={"发音","词汇","应试","工具"};
        for(int i=0;i<tabs.length;i++){final int g=i;TextView tab=text(tabs[i],13,MUTED,true);tab.setGravity(Gravity.CENTER);tab.setOnClickListener(v->{if(category==g)return;category=g;renderCategory(true);});categories.addView(tab,new LinearLayout.LayoutParams(0,dp(44),1));}panel.addView(categories);
        scroll=new ScrollView(activity);scroll.setFillViewport(false);scroll.setVerticalScrollBarEnabled(false);scroll.setOverScrollMode(View.OVER_SCROLL_NEVER);
        contents=new LinearLayout(activity);contents.setOrientation(LinearLayout.VERTICAL);contents.setPadding(dp(18),dp(16),dp(18),dp(22));scroll.addView(contents);panel.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));renderCategory(false);
        dialog.setContentView(panel);Window window=dialog.getWindow();window.setBackgroundDrawableResource(android.R.color.transparent);window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);window.setDimAmount(.28f);window.setGravity(Gravity.BOTTOM);window.setWindowAnimations(0);
        dialog.setOnKeyListener((d,key,event)->{if(key==android.view.KeyEvent.KEYCODE_BACK){if(event.getAction()==android.view.KeyEvent.ACTION_UP)dismiss(null);return true;}return false;});
        dialog.show();GlassSurface.apply(activity,dialog.getWindow(),panel);
        android.util.DisplayMetrics dm=activity.getResources().getDisplayMetrics();window.setLayout(-1,Math.round(dm.heightPixels*.82f));
        if(Build.VERSION.SDK_INT>=23)window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION|View.SYSTEM_UI_FLAG_LAYOUT_STABLE|View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        window.setNavigationBarColor(Color.TRANSPARENT);if(android.os.Build.VERSION.SDK_INT>=29)window.setNavigationBarContrastEnforced(false);
        SheetMotion.open(activity,dialog);
    }
    private void renderCategory(boolean animate){
        for(int i=0;i<categories.getChildCount();i++){TextView t=(TextView)categories.getChildAt(i);boolean on=i==category;t.setTextColor(on?BLUE:MUTED);t.setBackground(shape(on?0xFFEDF2FF:Color.WHITE,12));t.setSelected(on);t.setContentDescription(t.getText()+ (on?"，已选中":"分类"));}
        contents.removeAllViews();group(contents,GROUPS[category]);scroll.scrollTo(0,0);
        if(animate&&motion){contents.animate().cancel();contents.setAlpha(.7f);contents.setTranslationX(dp(12));contents.animate().alpha(1f).translationX(0).setDuration(300).setInterpolator(AppMotion.SETTLE).start();}
    }
    private void group(LinearLayout parent,int[] indexes){
        for(int index:indexes){
            LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.bottomMargin=dp(8);parent.addView(tile(index),lp);
        }
    }
    private View tile(int index){
        boolean selected=index==current;
        LinearLayout card=new LinearLayout(activity);card.setOrientation(LinearLayout.HORIZONTAL);card.setGravity(Gravity.CENTER_VERTICAL);card.setPadding(dp(12),dp(10),dp(14),dp(10));card.setMinimumHeight(dp(72));
        GradientDrawable background=shape(selected?0xB3E6EEFF:0x78FFFFFF,13);background.setStroke(dp(1),selected?0xFFBFCFFF:0xFFE8EDF4);
        card.setBackground(new RippleDrawable(ColorStateList.valueOf(0x1F325ED6),background,null));card.setFocusable(true);card.setContentDescription(names[index]+(selected?"，当前模块":""));
        ImageView icon=new ImageView(activity);icon.setImageResource(ICONS[index]);icon.setImageTintList(ColorStateList.valueOf(selected?BLUE:0xFF54729C));icon.setBackground(shape(selected?0xFFDDE7FF:0xFFF0F4FA,12));icon.setPadding(dp(9),dp(9),dp(9),dp(9));icon.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);LinearLayout.LayoutParams iconLp=new LinearLayout.LayoutParams(dp(40),dp(40));iconLp.rightMargin=dp(12);card.addView(icon,iconLp);
        LinearLayout labels=new LinearLayout(activity);labels.setOrientation(LinearLayout.VERTICAL);labels.setGravity(Gravity.CENTER_VERTICAL);
        TextView title=text(names[index],14,selected?BLUE:INK,true);title.setMaxLines(1);labels.addView(title);
        TextView hint=text(HINTS[index],11,MUTED,false);hint.setMaxLines(1);hint.setEllipsize(android.text.TextUtils.TruncateAt.END);LinearLayout.LayoutParams hintLp=new LinearLayout.LayoutParams(-1,-2);hintLp.topMargin=dp(4);labels.addView(hint,hintLp);
        card.addView(labels,new LinearLayout.LayoutParams(0,-2,1));
        TextView state=text(selected?"当前":"›",selected?10:22,selected?BLUE:0xFF99A8BD,false);state.setGravity(Gravity.CENTER);state.setContentDescription(selected?"当前模块":"打开模块");card.addView(state,new LinearLayout.LayoutParams(dp(36),dp(40)));
        card.setOnClickListener(v->{if(closing)return;if(motion){card.animate().scaleX(.97f).scaleY(.97f).setDuration(70).withEndAction(()->dismiss(()->select.accept(index))).start();}else dismiss(()->select.accept(index));});return card;
    }
    private void dismiss(Runnable after){if(closing)return;closing=true;Runnable end=()->{dialog.dismiss();if(after!=null)after.run();};if(motion){panel.animate().cancel();SheetMotion.close(activity,dialog,end);}else end.run();}
}
