package com.xiaoyang.studyenglish;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import java.util.Calendar;
import java.util.TimeZone;

public final class DailyReminderReceiver extends BroadcastReceiver {
    private static final String CHANNEL="daily_review";
    static void schedule(Context context,int hour,int minute){
        AlarmManager alarms=(AlarmManager)context.getSystemService(Context.ALARM_SERVICE);
        if(alarms==null)return;
        Calendar next=Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"));
        next.set(Calendar.HOUR_OF_DAY,hour);next.set(Calendar.MINUTE,minute);next.set(Calendar.SECOND,0);next.set(Calendar.MILLISECOND,0);
        if(next.getTimeInMillis()<=System.currentTimeMillis())next.add(Calendar.DAY_OF_MONTH,1);
        PendingIntent pi=PendingIntent.getBroadcast(context,7391,new Intent(context,DailyReminderReceiver.class),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,next.getTimeInMillis(),pi);
    }
    static void cancel(Context context){AlarmManager alarms=(AlarmManager)context.getSystemService(Context.ALARM_SERVICE);PendingIntent pi=PendingIntent.getBroadcast(context,7391,new Intent(context,DailyReminderReceiver.class),PendingIntent.FLAG_NO_CREATE|PendingIntent.FLAG_IMMUTABLE);if(alarms!=null&&pi!=null)alarms.cancel(pi);}
    @Override public void onReceive(Context context,Intent intent){
        android.content.SharedPreferences prefs=context.getSharedPreferences("study_reminder",Context.MODE_PRIVATE);
        if(!prefs.getBoolean("enabled",false))return;
        int hour=prefs.getInt("hour",20),minute=prefs.getInt("minute",0);
        if(Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())||Intent.ACTION_TIME_CHANGED.equals(intent.getAction())||Intent.ACTION_TIMEZONE_CHANGED.equals(intent.getAction())){schedule(context,hour,minute);return;}
        if(Build.VERSION.SDK_INT>=33&&context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)!=android.content.pm.PackageManager.PERMISSION_GRANTED)return;
        NotificationManager manager=(NotificationManager)context.getSystemService(Context.NOTIFICATION_SERVICE);
        if(manager==null)return;
        if(Build.VERSION.SDK_INT>=26)manager.createNotificationChannel(new NotificationChannel(CHANNEL,"每日复习提醒",NotificationManager.IMPORTANCE_DEFAULT));
        Intent open=context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        PendingIntent tap=PendingIntent.getActivity(context,7392,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        Notification.Builder builder=Build.VERSION.SDK_INT>=26?new Notification.Builder(context,CHANNEL):new Notification.Builder(context);
        manager.notify(7391,builder.setSmallIcon(android.R.drawable.ic_popup_reminder).setContentTitle("该复习啦").setContentText("打开小洋专升本英语，完成今天的章节复习。").setContentIntent(tap).setAutoCancel(true).build());
        schedule(context,hour,minute);
    }
}
