package com.xiaoyang.studyenglish;

import android.app.Activity;
import android.app.Dialog;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.view.animation.DecelerateInterpolator;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/** Account and application actions live under the bottom 'My' tab. */
final class AccountSheet {
    private final Activity activity;private final String email,sync;private final java.util.function.IntConsumer action;private final Runnable onClose;
    private Dialog dialog;private LinearLayout panel;private boolean closing;private final boolean motion;
    AccountSheet(Activity activity,String email,String sync,java.util.function.IntConsumer action,Runnable onClose){this.activity=activity;this.email=email;this.sync=sync;this.action=action;this.onClose=onClose;motion=AppMotion.enabled(activity);}
    private int dp(int n){return Math.round(n*activity.getResources().getDisplayMetrics().density);}
    private GradientDrawable shape(int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;}
    private TextView text(String value,int size,int color,boolean bold){TextView t=new TextView(activity);t.setText(value);t.setTextSize(size);t.setTextColor(color);t.setIncludeFontPadding(false);if(bold)t.setTypeface(null,Typeface.BOLD);return t;}
    void show(){
        dialog=new Dialog(activity);dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);dialog.setOnDismissListener(d->onClose.run());panel=new LinearLayout(activity);panel.setOrientation(LinearLayout.VERTICAL);panel.setBackground(GlassSurface.panel(activity));panel.setClipToOutline(true);
        LinearLayout header=new LinearLayout(activity);header.setGravity(Gravity.CENTER_VERTICAL);header.setPadding(dp(22),dp(18),dp(14),dp(10));TextView title=text("我的",23,0xFF182B43,true);header.addView(title,new LinearLayout.LayoutParams(0,dp(44),1));title.setGravity(Gravity.CENTER_VERTICAL);TextView close=text("×",25,0xFF718098,false);close.setGravity(Gravity.CENTER);close.setContentDescription("关闭我的面板");close.setBackground(shape(0x80FFFFFF,22));close.setOnClickListener(v->dismiss(0));header.addView(close,new LinearLayout.LayoutParams(dp(44),dp(44)));panel.addView(header);
        ScrollView scroll=new ScrollView(activity);scroll.setVerticalScrollBarEnabled(false);LinearLayout body=new LinearLayout(activity);body.setOrientation(LinearLayout.VERTICAL);body.setPadding(dp(20),dp(8),dp(20),dp(24));scroll.addView(body);panel.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout account=new LinearLayout(activity);account.setOrientation(LinearLayout.VERTICAL);account.setPadding(dp(18),dp(18),dp(18),dp(18));account.setBackground(new RippleDrawable(ColorStateList.valueOf(0x18325ED6),shape(0xFFEDF2FF,18),null));account.setOnClickListener(v->dismiss(8));account.setFocusable(true);account.addView(text(email.isEmpty()?"登录 / 管理账号":"学习账号",16,0xFF182B43,true));TextView identity=text(email.isEmpty()?"登录原账号，跨设备继续学习":email,12,0xFF627692,false);identity.setPadding(0,dp(9),0,dp(10));identity.setMaxLines(2);account.addView(identity);account.addView(text("管理账号  →",12,0xFF325ED6,true));body.addView(account);
        section(body,"学习与同步");TextView status=text(sync.isEmpty()?"进入课程后查看同步状态":sync,12,0xFF718098,false);status.setPadding(dp(4),0,dp(4),dp(10));status.setMaxLines(3);body.addView(status);
        row(body,"学习计划","调整当前阶段与目标日期",9);row(body,"刷新当前页面","重新读取当前模块进度",2);row(body,"检查云端连接","查看当前网络是否可用",5);row(body,"学习数据备份","导出自己的学习记录",10);
        appendices(body);
        section(body,"更多");row(body,"邮件验证链接","验证邮件没有自动返回时使用",3);row(body,"使用说明","版本与使用帮助",4);row(body,"开源许可","Lucide 图标与许可证",7);
        dialog.setContentView(panel);Window w=dialog.getWindow();w.setBackgroundDrawableResource(android.R.color.transparent);w.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);w.setDimAmount(.28f);w.setGravity(Gravity.BOTTOM);w.setWindowAnimations(0);dialog.setOnKeyListener((d,key,event)->{if(key==android.view.KeyEvent.KEYCODE_BACK){if(event.getAction()==android.view.KeyEvent.ACTION_UP)dismiss(0);return true;}return false;});dialog.show();GlassSurface.apply(activity,dialog.getWindow(),panel);w.setLayout(-1,Math.round(activity.getResources().getDisplayMetrics().heightPixels*.86f));w.setNavigationBarColor(Color.TRANSPARENT);if(android.os.Build.VERSION.SDK_INT>=29)w.setNavigationBarContrastEnforced(false);w.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION|View.SYSTEM_UI_FLAG_LAYOUT_STABLE|View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        SheetMotion.open(activity,dialog);
    }
    private void appendices(LinearLayout body){
        section(body,"手册速查");
        try(java.io.InputStream input=activity.getAssets().open("handbook-abc.json")){
            java.io.ByteArrayOutputStream bytes=new java.io.ByteArrayOutputStream();byte[] buffer=new byte[4096];int n;
            while((n=input.read(buffer))!=-1)bytes.write(buffer,0,n);
            org.json.JSONArray books=new org.json.JSONArray(new String(bytes.toByteArray(),java.nio.charset.StandardCharsets.UTF_8));
            for(int i=0;i<books.length();i++){
                org.json.JSONObject book=books.getJSONObject(i);org.json.JSONArray rows=book.getJSONArray("rows");
                LinearLayout group=new LinearLayout(activity);group.setOrientation(LinearLayout.VERTICAL);group.setBackground(shape(0x80FFFFFF,14));
                TextView heading=text(book.getString("title")+"  ▾",14,0xFF182B43,true);heading.setPadding(dp(14),dp(17),dp(14),dp(17));heading.setMinimumHeight(dp(52));heading.setFocusable(true);group.addView(heading);
                LinearLayout content=new LinearLayout(activity);content.setOrientation(LinearLayout.VERTICAL);content.setPadding(dp(14),0,dp(14),dp(12));content.setVisibility(View.GONE);group.addView(content);
                heading.setOnClickListener(v->{boolean open=content.getVisibility()!=View.VISIBLE;content.setVisibility(open?View.VISIBLE:View.GONE);heading.setText(book.optString("title")+(open?"  ▴":"  ▾"));heading.setContentDescription(book.optString("title")+(open?"，已展开":"，已收起"));
                    if(open&&content.getChildCount()==0)for(int j=0;j<rows.length();j++){
                        org.json.JSONArray row=rows.optJSONArray(j);if(row==null)continue;
                        TextView word=text(row.optString(0)+" · "+row.optString(1),14,0xFF325ED6,true);word.setPadding(0,dp(12),0,dp(5));content.addView(word);
                        TextView example=text(row.optString(2),12,0xFF52637B,false);example.setTextIsSelectable(true);example.setLineSpacing(dp(3),1f);example.setPadding(0,0,0,dp(12));content.addView(example);
                        View line=new View(activity);line.setBackgroundColor(0xFFE5EAF2);content.addView(line,new LinearLayout.LayoutParams(-1,dp(1)));
                    }
                    if(open&&motion){content.setAlpha(.5f);content.setTranslationY(dp(6));content.animate().alpha(1f).translationY(0).setDuration(180).setInterpolator(AppMotion.SETTLE).start();}
                });
                LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.bottomMargin=dp(8);body.addView(group,lp);
            }
        }catch(Exception e){body.addView(text("手册读取失败，请重新打开“我的”。",12,0xFF718098,false));}
    }
    private void section(LinearLayout body,String label){TextView t=text(label,12,0xFF718098,true);t.setPadding(dp(4),dp(24),0,dp(12));body.addView(t);}
    private void row(LinearLayout body,String title,String subtitle,int id){
        LinearLayout row=new LinearLayout(activity);row.setGravity(Gravity.CENTER_VERTICAL);row.setPadding(dp(14),dp(13),dp(12),dp(13));row.setMinimumHeight(dp(64));row.setFocusable(true);row.setBackground(new RippleDrawable(ColorStateList.valueOf(0x18325ED6),shape(0x80FFFFFF,14),null));
        LinearLayout labels=new LinearLayout(activity);labels.setOrientation(LinearLayout.VERTICAL);labels.addView(text(title,14,0xFF182B43,true));TextView sub=text(subtitle,11,0xFF718098,false);sub.setPadding(0,dp(5),0,0);labels.addView(sub);row.addView(labels,new LinearLayout.LayoutParams(0,-2,1));row.addView(text("›",22,0xFF99A8BD,false));row.setOnClickListener(v->dismiss(id));LinearLayout.LayoutParams rp=new LinearLayout.LayoutParams(-1,-2);rp.bottomMargin=dp(8);body.addView(row,rp);
    }
    private void dismiss(int id){if(closing)return;closing=true;Runnable end=()->{dialog.dismiss();if(id!=0)action.accept(id);};SheetMotion.close(activity,dialog,end);}
}
