package com.xiaoyang.studyenglish;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.RippleDrawable;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.Uri;
import android.os.Bundle;
import android.os.Message;
import android.provider.MediaStore;
import android.speech.tts.TextToSpeech;
import android.view.Gravity;
import android.view.View;
import android.webkit.JavascriptInterface;
import android.webkit.JsResult;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.ImageView;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.FrameLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Locale;
import java.util.Map;

public final class MainActivity extends Activity {
    public static final String HOST = "appassets.androidplatform.net";
    public static final String HOME = "https://" + HOST + "/assets/index.html";
    private static final String CLOUD = "ojkychotvwrksxwgvmfk.supabase.co";
    private static final int PICK_PHOTOS = 301, SAVE_BACKUP = 302, REQUEST_NOTIFICATIONS=303;
    private WebView web;
    private PageTransition pageTransition;
    private ProgressBar progress;
    private TextView offline;
    private LinearLayout bottomBar;
    private boolean nativeSheetOpen;
    private int statusInsetPx,bottomInsetPx;
    private final ImageView[] bottomIcons=new ImageView[4];
    private final TextView[] bottomLabels=new TextView[4];
    private static final int INK = 0xFF182B43;
    private static final String[] MODULE_PATHS={"index.html","phon/index.html","phonics/index.html","root/index.html","mother/index.html","500/index.html","spell/index.html","courses/index.html","grammar/index.html","papers/index.html","essay/index.html","review/index.html","plan/index.html"};
    private static final String[] MODULE_NAMES={"今日学习","国际音标","自然拼读","32 天词根词缀","秦天 58 组母词","500 高频词汇","全能拼写","刘晓燕单词课","刘晓燕语法课","真题精做","作文模板","遗忘曲线复习","长期备考计划"};
    private ValueCallback<Uri[]> photoCallback;
    private final Uri cameraUri = Uri.parse("content://com.xiaoyang.studyenglish.photos/note-photo.jpg");
    private byte[] pendingBackup;
    private TextToSpeech speech;
    private boolean speechReady;
    private boolean reminderPermissionPending;
    private int pendingReminderHour, pendingReminderMinute;
    private ConnectivityManager connectivity;
    private ConnectivityManager.NetworkCallback networkCallback;

    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    private void syncSafeInsets(){if(web==null)return;float density=getResources().getDisplayMetrics().density;web.evaluateJavascript("document.documentElement.style.setProperty('--study-safe-top','"+(statusInsetPx/density)+"px');document.documentElement.style.setProperty('--study-safe-bottom','"+(bottomInsetPx/density)+"px');",null);}
    private void toast(String message) { Toast.makeText(this, message, Toast.LENGTH_LONG).show(); }
    private boolean local(Uri uri) { return "https".equals(uri.getScheme()) && HOST.equals(uri.getHost()) && uri.getPort() == -1 && uri.getUserInfo() == null && uri.getPath() != null && uri.getPath().startsWith("/assets/"); }

    @Override public void onCreate(Bundle savedState) {
        super.onCreate(savedState);
        getWindow().setStatusBarColor(Color.TRANSPARENT);
        if(android.os.Build.VERSION.SDK_INT>=30)getWindow().setDecorFitsSystemWindows(false);
        getWindow().setNavigationBarColor(Color.TRANSPARENT);
        if(android.os.Build.VERSION.SDK_INT>=29)getWindow().setNavigationBarContrastEnforced(false);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN|View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION|View.SYSTEM_UI_FLAG_LAYOUT_STABLE|View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        LinearLayout layout = new LinearLayout(this); layout.setOrientation(LinearLayout.VERTICAL); layout.setBackground(new android.graphics.drawable.GradientDrawable(android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM,new int[]{0xFFBDD3EE,0xFFE5F1F4}));
        FrameLayout edge=new FrameLayout(this);edge.setBackground(layout.getBackground());layout.setBackgroundColor(Color.TRANSPARENT);
        edge.setOnApplyWindowInsetsListener((v,insets)->{
            statusInsetPx=insets.getSystemWindowInsetTop();int bottom=insets.getSystemWindowInsetBottom();boolean keyboard=bottom>dp(120);bottomInsetPx=keyboard?0:bottom;
            layout.setPadding(insets.getSystemWindowInsetLeft(),0,insets.getSystemWindowInsetRight(),keyboard?bottom:0);
            if(bottomBar!=null){bottomBar.setVisibility(keyboard?View.GONE:View.VISIBLE);FrameLayout.LayoutParams bp=(FrameLayout.LayoutParams)bottomBar.getLayoutParams();bp.bottomMargin=bottomInsetPx+dp(8);bottomBar.setLayoutParams(bp);}
            syncSafeInsets();return insets.consumeSystemWindowInsets();
        });
        progress = new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal); progress.setMax(100);progress.setProgressTintList(ColorStateList.valueOf(0xFF325ED6)); progress.setVisibility(View.GONE);
        offline = new TextView(this); offline.setText("当前未联网，可查看课程；登录和云端保存需联网。"); offline.setPadding(dp(12),dp(8),dp(12),dp(8)); offline.setBackgroundColor(0xFFFFE5BA); offline.setTextColor(0xFF423527); offline.setVisibility(View.GONE); layout.addView(offline);
        FrameLayout pages=new FrameLayout(this);pages.setBackgroundColor(0xFFF5F7FB);pages.setClipChildren(true);
        web = new WebView(this);web.setVerticalScrollBarEnabled(false);web.setBackgroundColor(0xFFF5F7FB);pages.addView(web,new FrameLayout.LayoutParams(-1,-1));
        pageTransition=new PageTransition(this,pages,web);layout.addView(pages,new LinearLayout.LayoutParams(-1,0,1));
        edge.addView(layout,new FrameLayout.LayoutParams(-1,-1));edge.addView(progress,new FrameLayout.LayoutParams(-1,dp(2),Gravity.TOP));FrameLayout.LayoutParams dock=new FrameLayout.LayoutParams(-1,dp(66),Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL);dock.setMargins(dp(12),0,dp(12),dp(8));edge.addView(createBottomBar(),dock);setContentView(edge);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true); settings.setDomStorageEnabled(true); settings.setAllowFileAccess(false); settings.setAllowContentAccess(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW); settings.setMediaPlaybackRequiresUserGesture(true);
        settings.setSupportMultipleWindows(true); settings.setJavaScriptCanOpenWindowsAutomatically(false); settings.setBuiltInZoomControls(false); settings.setTextZoom(100);
        WebView.setWebContentsDebuggingEnabled(false);
        web.addJavascriptInterface(new NativeBridge(),"StudyAndroid");
        web.setWebViewClient(new LocalClient()); web.setWebChromeClient(new Chrome());
        web.setDownloadListener((url,agent,disposition,mime,len)->{ if(!url.startsWith("blob:")) openExternal(Uri.parse(url)); });
        speech = new TextToSpeech(this,status->{speechReady=status==TextToSpeech.SUCCESS&&speech!=null&&speech.isLanguageAvailable(Locale.UK)>=TextToSpeech.LANG_AVAILABLE;if(speechReady){speech.setLanguage(Locale.UK);speech.setSpeechRate(.8f);}});
        connectivity = (ConnectivityManager)getSystemService(CONNECTIVITY_SERVICE);
        networkCallback = new ConnectivityManager.NetworkCallback(){@Override public void onAvailable(Network n){networkStatus();}@Override public void onLost(Network n){networkStatus();}@Override public void onCapabilitiesChanged(Network n,NetworkCapabilities c){networkStatus();}};
        connectivity.registerDefaultNetworkCallback(networkCallback); networkStatus();
        if(savedState == null || web.restoreState(savedState) == null) web.loadUrl(HOME);
        if(getIntent().getData()!=null) receiveAuth(getIntent().getData());
        if(getIntent().getBooleanExtra("check_cloud",false))checkCloud();
    }

    private int currentModule(){String path=Uri.parse(web.getUrl()==null?HOME:web.getUrl()).getPath();for(int i=0;i<MODULE_PATHS.length;i++)if(("/assets/"+MODULE_PATHS[i]).equals(path))return i;return 0;}
    private void openModule(int which){String path="/assets/"+MODULE_PATHS[which];if(!path.equals(Uri.parse(web.getUrl()==null?HOME:web.getUrl()).getPath()))web.loadUrl("https://"+HOST+path);}
    private void navigation(){if(nativeSheetOpen)return;nativeSheetOpen=true;selectBottom(1);new NavigationSheet(this,MODULE_NAMES,currentModule(),this::openModule,()->{nativeSheetOpen=false;refreshBottom();}).show();}
    private LinearLayout createBottomBar(){
        bottomBar=new LinearLayout(this);bottomBar.setOrientation(LinearLayout.VERTICAL);bottomBar.setBackground(GlassSurface.bar(this));bottomBar.setElevation(dp(7));bottomBar.setClipToOutline(true);
        View line=new View(this);line.setBackgroundColor(0xFFE4ECF7);bottomBar.setPadding(dp(3),dp(5),dp(3),dp(5));
        LinearLayout row=new LinearLayout(this);row.setGravity(Gravity.CENTER_VERTICAL);row.setPadding(dp(8),dp(5),dp(8),dp(5));
        String[] labels={"今日","学习","复习","我的"};int[] icons={R.drawable.nav_house,R.drawable.nav_library,R.drawable.nav_calendar_check_2,R.drawable.nav_user_round};
        for(int i=0;i<4;i++){final int tab=i;LinearLayout item=new LinearLayout(this);item.setOrientation(LinearLayout.VERTICAL);item.setGravity(Gravity.CENTER);item.setContentDescription(labels[i]);item.setFocusable(true);item.setBackground(new RippleDrawable(ColorStateList.valueOf(0x14325ED6),new ColorDrawable(Color.TRANSPARENT),null));
            ImageView icon=new ImageView(this);icon.setImageResource(icons[i]);icon.setPadding(dp(11),dp(3),dp(11),dp(3));item.addView(icon,new LinearLayout.LayoutParams(dp(46),dp(28)));bottomIcons[i]=icon;
            TextView label=new TextView(this);label.setText(labels[i]);label.setTextSize(11);label.setGravity(Gravity.CENTER);label.setPadding(0,dp(3),0,0);item.addView(label);bottomLabels[i]=label;
            item.setOnClickListener(v->{switch(tab){case 0:openModule(0);break;case 1:navigation();break;case 2:openModule(11);break;case 3:myAccount();break;}});row.addView(item,new LinearLayout.LayoutParams(0,dp(56),1));
        }bottomBar.addView(row);refreshBottom();return bottomBar;
    }
    private void selectBottom(int tab){for(int i=0;i<4;i++){if(bottomIcons[i]==null)continue;boolean on=i==tab;bottomIcons[i].setImageTintList(ColorStateList.valueOf(on?0xFF325ED6:0xFF8491A5));android.graphics.drawable.GradientDrawable pill=new android.graphics.drawable.GradientDrawable();pill.setColor(on?0xE6E3EDFF:Color.TRANSPARENT);if(on)pill.setStroke(dp(1),0xFFFFFFFF);pill.setCornerRadius(dp(16));bottomIcons[i].setBackground(pill);bottomLabels[i].setTextColor(on?0xFF325ED6:0xFF8491A5);((View)bottomLabels[i].getParent()).setSelected(on);}}
    private void refreshBottom(){int module=currentModule();selectBottom(module==0?0:module==11?2:module==12?3:1);}
    private void myAccount(){
        if(nativeSheetOpen)return;nativeSheetOpen=true;
        selectBottom(3);web.evaluateJavascript("JSON.stringify({email:window.StudyAccount&&StudyAccount.session&&!StudyAccount.session.user.is_anonymous?StudyAccount.session.user.email:'',sync:(document.getElementById('syncStatus')||document.getElementById('rootStatus')||{}).textContent||'请登录后查看同步状态'})",raw->{
            if(isFinishing()){nativeSheetOpen=false;return;}String email="",sync="";try{Object decoded=new org.json.JSONTokener(raw).nextValue();org.json.JSONObject data=new org.json.JSONObject(String.valueOf(decoded));email=data.optString("email","");sync=data.optString("sync","");}catch(Exception ignored){}
            new AccountSheet(this,email,sync,this::appAction,()->{nativeSheetOpen=false;refreshBottom();}).show();
        });
    }
    private void networkStatus() {
        runOnUiThread(()->{if(isFinishing())return;NetworkCapabilities caps=connectivity.getNetworkCapabilities(connectivity.getActiveNetwork());offline.setVisibility(caps!=null&&caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)?View.GONE:View.VISIBLE);});
    }
    private void appAction(int action){
        switch(action){

            case 1:web.loadUrl(HOME);break;
            case 6:back();break;
            case 2:web.reload();break;
            case 3:pasteAuth();break;
            case 5:checkCloud();break;
            case 7:showLicenses();break;
            case 4:new AlertDialog.Builder(this).setTitle("小洋专升本英语 "+getVersionName()).setMessage("课程随 App 安装，无需开启电脑。\n\n使用原邮箱和密码登录，即可同步各模块进度、课程链接和笔记。联网后才能登录和保存到云端。\n\nB 站课程在 B 站或浏览器打开，返回 App 继续记笔记。照片由你选择后上传。\n\n邮件验证一般会自动回到 App；未跳回时，可复制邮件内的完整验证链接，通过“我的 → 邮件验证”打开。\n\n建议保持 Android System WebView 或 Chrome 为最新版本。更新时直接覆盖安装，不要卸载。\n\n系统要求：Android 8.0 及以上。个人使用版，未上架应用商店。").setPositiveButton("知道了",null).show();break;
                    case 8:web.evaluateJavascript("window.StudyAccount && StudyAccount.open()",null);break;
            case 9:openModule(12);break;
            case 10:web.evaluateJavascript("window.StudyAccount && StudyAccount.open('summary')",null);break;
        }
    }
    private String getVersionName(){try{return getPackageManager().getPackageInfo(getPackageName(),0).versionName;}catch(Exception e){return "未知版本";}}
    private void showLicenses(){
        try(java.util.Scanner scanner=new java.util.Scanner(getAssets().open("legal/LUCIDE-LICENSE.txt"),"UTF-8")){
            scanner.useDelimiter("\\A");TextView text=new TextView(this);text.setText("Lucide Icons · https://github.com/lucide-icons/lucide\n\n"+(scanner.hasNext()?scanner.next():""));text.setTextSize(12);text.setTextColor(INK);text.setPadding(dp(22),dp(12),dp(22),dp(18));android.widget.ScrollView scroll=new android.widget.ScrollView(this);scroll.addView(text);new AlertDialog.Builder(this).setTitle("开源许可").setView(scroll).setPositiveButton("关闭",null).show();
        }catch(Exception e){toast("许可文件暂时无法读取。");}
    }
    private void back() {
        // Dismiss web dialogs first; respect any in-flight save or unsaved draft.
        web.evaluateJavascript("(function(){var d=document.querySelector('dialog[open]');if(!d)return 'navigate';if(window.StudyAccount&&StudyAccount.locked)return 'busy';if(d.dispatchEvent(new Event('cancel',{cancelable:true})))d.close();return d.open?'busy':'closed'})()",result->{if("\"navigate\"".equals(result)){if(web.canGoBack())web.goBack();else new AlertDialog.Builder(this).setMessage("退出学习 App？未保存的文字请先保存。").setNegativeButton("继续学习",null).setPositiveButton("退出",(d,w)->finish()).show();}else if("\"busy\"".equals(result))toast("正在保存，请稍候。");});
    }
    @Override public void onBackPressed() { back(); }
    @Override protected void onSaveInstanceState(Bundle state) { super.onSaveInstanceState(state);web.saveState(state); }
    @Override protected void onNewIntent(Intent intent) { super.onNewIntent(intent);setIntent(intent);if(intent.getData()!=null)receiveAuth(intent.getData());if(intent.getBooleanExtra("check_cloud",false))checkCloud(); }
    @Override protected void onResume() { super.onResume();if(web!=null)web.onResume(); }
    @Override protected void onPause() { if(web!=null)web.onPause();if(speech!=null)speech.stop();super.onPause(); }
    @Override protected void onDestroy() {
        if(photoCallback!=null){photoCallback.onReceiveValue(null);photoCallback=null;}
        if(connectivity!=null&&networkCallback!=null)connectivity.unregisterNetworkCallback(networkCallback);
        if(speech!=null){speech.stop();speech.shutdown();}pageTransition.clear();web.removeJavascriptInterface("StudyAndroid");web.destroy();super.onDestroy();
    }

    private boolean route(Uri uri) {
        if(local(uri))return false;
        if("xiaoyangstudy".equals(uri.getScheme()))receiveAuth(uri);else openExternal(uri);
        return true;
    }
    private void openExternal(Uri uri) {
        String scheme=uri.getScheme();
        if(!"https".equals(scheme)&&!"http".equals(scheme)&&!"mailto".equals(scheme)){toast("此链接无法在 App 中打开。");return;}
        Intent intent=new Intent(Intent.ACTION_VIEW,uri);intent.addCategory(Intent.CATEGORY_BROWSABLE);
        String host=uri.getHost();
        if(host!=null&&(host.equals("b23.tv")||host.equals("bilibili.com")||host.endsWith(".bilibili.com"))){try{startActivity(new Intent(intent).setPackage("tv.danmaku.bili"));return;}catch(Exception ignored){}}
        try{startActivity(intent);}catch(Exception e){toast("未找到能打开此链接的应用。");}
    }

    private final class LocalClient extends WebViewClient {
        @Override public void onPageStarted(WebView view,String url,android.graphics.Bitmap icon){pageTransition.start();refreshBottom();}
        @Override public void onPageCommitVisible(WebView view,String url){pageTransition.commit();}
        @Override public void onPageFinished(WebView view,String url){syncSafeInsets();refreshBottom();}
        @Override public void doUpdateVisitedHistory(WebView view,String url,boolean reload){refreshBottom();}
        @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){return route(request.getUrl());}
        @Override public boolean shouldOverrideUrlLoading(WebView view,String url){return route(Uri.parse(url));}
        @Override public WebResourceResponse shouldInterceptRequest(WebView view,WebResourceRequest request) {
            Uri uri=request.getUrl();if(!HOST.equals(uri.getHost()))return null;
            try {
                if(!local(uri)||!"GET".equals(request.getMethod()))throw new Exception();
                String name=uri.getPath().substring("/assets/".length());
                if(name.contains("..")||name.contains("\\")||name.startsWith("/")||name.isEmpty())throw new Exception();
                String mime=name.endsWith(".html")?"text/html":name.endsWith(".js")?"application/javascript":name.endsWith(".css")?"text/css":name.endsWith(".png")?"image/png":"application/octet-stream";
                Map<String,String> headers=Collections.singletonMap("X-Content-Type-Options","nosniff");
                return new WebResourceResponse(mime,"UTF-8",200,"OK",headers,getAssets().open(name));
            }catch(Exception e){return new WebResourceResponse("text/plain","UTF-8",404,"Not Found",Collections.emptyMap(),new ByteArrayInputStream("Not found".getBytes(StandardCharsets.UTF_8)));}
        }
    }
    private final class Chrome extends WebChromeClient {
        @Override public void onProgressChanged(WebView view,int percent){progress.setProgress(percent);progress.setVisibility(percent<100?View.VISIBLE:View.GONE);}
        @Override public boolean onJsAlert(WebView view,String url,String message,JsResult result){new AlertDialog.Builder(MainActivity.this).setMessage(message).setPositiveButton("知道了",(d,w)->result.confirm()).setOnCancelListener(d->result.cancel()).show();return true;}
        @Override public boolean onJsConfirm(WebView view,String url,String message,JsResult result){confirm(message,result);return true;}
        @Override public boolean onJsBeforeUnload(WebView view,String url,String message,JsResult result){confirm("本页可能有尚未保存的文字，确定离开吗？",result);return true;}
        @Override public boolean onCreateWindow(WebView view,boolean dialog,boolean gesture,Message message){
            if(!gesture)return false;
            WebView child=new WebView(MainActivity.this);child.getSettings().setJavaScriptEnabled(false);
            child.setWebViewClient(new WebViewClient(){boolean handled;private void move(String url){if(handled||"about:blank".equals(url))return;handled=true;child.stopLoading();Uri uri=Uri.parse(url);if(local(uri))web.loadUrl(url);else route(uri);child.postDelayed(child::destroy,100);}@Override public boolean shouldOverrideUrlLoading(WebView v,String u){move(u);return true;}@Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest r){move(r.getUrl().toString());return true;}@Override public void onPageStarted(WebView v,String u,android.graphics.Bitmap b){move(u);}});
            ((WebView.WebViewTransport)message.obj).setWebView(child);message.sendToTarget();return true;
        }
        @Override public boolean onShowFileChooser(WebView view,ValueCallback<Uri[]> callback,FileChooserParams params){
            if(photoCallback!=null)photoCallback.onReceiveValue(null);photoCallback=callback;
            Intent camera=new Intent(MediaStore.ACTION_IMAGE_CAPTURE).putExtra(MediaStore.EXTRA_OUTPUT,cameraUri).addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION|Intent.FLAG_GRANT_READ_URI_PERMISSION);camera.setClipData(ClipData.newRawUri("笔记照片",cameraUri));
            boolean hasCamera=camera.resolveActivity(getPackageManager())!=null;
            try{new File(getFilesDir(),"note-photo.jpg").delete();if(params.isCaptureEnabled()&&hasCamera){startActivityForResult(camera,PICK_PHOTOS);return true;}
                Intent files=new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_ALLOW_MULTIPLE,params.getMode()==FileChooserParams.MODE_OPEN_MULTIPLE).putExtra(Intent.EXTRA_MIME_TYPES,new String[]{"image/jpeg","image/png","image/webp"});
                Intent chooser=Intent.createChooser(files,"添加笔记照片");if(hasCamera)chooser.putExtra(Intent.EXTRA_INITIAL_INTENTS,new Intent[]{camera});startActivityForResult(chooser,PICK_PHOTOS);
            }catch(Exception e){photoCallback.onReceiveValue(null);photoCallback=null;toast("无法打开照片选择器，请检查系统相册。");}return true;
        }
    }
    private void confirm(String text,JsResult result){new AlertDialog.Builder(this).setMessage(text).setNegativeButton("取消",(d,w)->result.cancel()).setPositiveButton("确定",(d,w)->result.confirm()).setOnCancelListener(d->result.cancel()).show();}

    private void checkCloud(){
        toast("正在检查网络连接…");
        new Thread(()->{
            boolean connected=false;HttpURLConnection c=null;
            try{c=(HttpURLConnection)new URL("https://"+CLOUD+"/auth/v1/health").openConnection();c.setConnectTimeout(12000);c.setReadTimeout(12000);int code=c.getResponseCode();connected=code==200||code==401;android.util.Log.i("StudyNetwork","Cloud health HTTP "+code);}
            catch(Exception e){android.util.Log.i("StudyNetwork","Cloud health "+e.getClass().getSimpleName()+": "+e.getMessage());}
            finally{if(c!=null)c.disconnect();}
            final boolean ok=connected;runOnUiThread(()->{if(isFinishing())return;new AlertDialog.Builder(this).setTitle(ok?"可以连接云端":"暂时无法连接云端").setMessage(ok?"网络检查通过。可以返回页面重新读取进度。":"课程页面可正常使用，但当前网络未能连接学习云端。请切换 Wi-Fi 或移动网络后重试；使用分应用网络设置时，需允许本 App 联网。不会清空已有学习记录。").setNegativeButton("返回",null).setPositiveButton("重新读取",(d,w)->web.reload()).show();});
        },"cloud-check").start();
    }

    private final class NativeBridge {
        @JavascriptInterface public boolean ownsPageTransitions(){return true;}
        @JavascriptInterface public float statusInset(){return statusInsetPx/getResources().getDisplayMetrics().density;}
        @JavascriptInterface public float bottomInset(){return bottomInsetPx/getResources().getDisplayMetrics().density;}
        @JavascriptInterface public boolean motionEnabled(){return AppMotion.enabled(MainActivity.this);}
        @JavascriptInterface public boolean isOnline(){if(connectivity==null)return false;Network n=connectivity.getActiveNetwork();NetworkCapabilities c=n==null?null:connectivity.getNetworkCapabilities(n);return c!=null&&c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)&&c.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED);}
        @JavascriptInterface public String setDailyReminder(boolean enabled,int hour,int minute){if(hour<0||hour>23||minute<0||minute>59)return "invalid";android.content.SharedPreferences prefs=getSharedPreferences("study_reminder",MODE_PRIVATE);prefs.edit().putInt("hour",hour).putInt("minute",minute).putBoolean("enabled",false).apply();if(!enabled){DailyReminderReceiver.cancel(MainActivity.this);prefs.edit().putBoolean("enabled",false).apply();return "disabled";}if(android.os.Build.VERSION.SDK_INT>=33&&checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)!=android.content.pm.PackageManager.PERMISSION_GRANTED){pendingReminderHour=hour;pendingReminderMinute=minute;reminderPermissionPending=true;runOnUiThread(()->requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS},REQUEST_NOTIFICATIONS));return "permission";}prefs.edit().putBoolean("enabled",true).apply();DailyReminderReceiver.schedule(MainActivity.this,hour,minute);return "enabled";}
        @JavascriptInterface public void speakText(String text){if(text==null||text.length()>500)return;runOnUiThread(()->{if(!local(Uri.parse(web.getUrl())))return;if(speechReady)speech.speak(text,TextToSpeech.QUEUE_FLUSH,null,"study-word");else toast("语音不可用，请联网播放或在系统设置中安装英语语音。");});}
        @JavascriptInterface public void saveBackup(String json,String filename){
            if(json==null||json.length()>12*1024*1024)return;
            try{new org.json.JSONObject(json);}catch(Exception e){return;}
            runOnUiThread(()->{if(!local(Uri.parse(web.getUrl())))return;if(pendingBackup!=null){toast("请先完成上一次导出。");return;}pendingBackup=json.getBytes(StandardCharsets.UTF_8);Intent save=new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("application/json").putExtra(Intent.EXTRA_TITLE,"个人学习备份.json");try{startActivityForResult(save,SAVE_BACKUP);}catch(Exception e){pendingBackup=null;toast("系统文件保存功能不可用。");}});
        }
    }
    @Override public void onRequestPermissionsResult(int requestCode,String[] permissions,int[] grantResults){super.onRequestPermissionsResult(requestCode,permissions,grantResults);if(requestCode!=REQUEST_NOTIFICATIONS||!reminderPermissionPending)return;reminderPermissionPending=false;boolean granted=grantResults.length>0&&grantResults[0]==android.content.pm.PackageManager.PERMISSION_GRANTED;android.content.SharedPreferences prefs=getSharedPreferences("study_reminder",MODE_PRIVATE);if(granted){prefs.edit().putInt("hour",pendingReminderHour).putInt("minute",pendingReminderMinute).putBoolean("enabled",true).apply();DailyReminderReceiver.schedule(this,pendingReminderHour,pendingReminderMinute);toast("每日复习提醒已开启。");}else{prefs.edit().putBoolean("enabled",false).apply();DailyReminderReceiver.cancel(this);toast("通知权限未开启；可在系统设置允许通知后重试。");if(web!=null)web.evaluateJavascript("(function(){localStorage.setItem('android_daily_review_reminder','0');var c=document.getElementById('androidReminderEnabled');if(c)c.checked=false;if(typeof notify==='function')notify('通知权限未开启，请在系统设置允许通知后重试。')})()",null);}}
    @Override protected void onActivityResult(int code,int result,Intent intent){super.onActivityResult(code,result,intent);
        if(code==PICK_PHOTOS&&photoCallback!=null){ArrayList<Uri> uris=new ArrayList<>();if(result==RESULT_OK){if(intent!=null&&intent.getClipData()!=null){ClipData clips=intent.getClipData();for(int n=0;n<clips.getItemCount();n++)uris.add(clips.getItemAt(n).getUri());}else if(intent!=null&&intent.getData()!=null)uris.add(intent.getData());else if(new File(getFilesDir(),"note-photo.jpg").length()>0)uris.add(cameraUri);}photoCallback.onReceiveValue(uris.isEmpty()?null:uris.toArray(new Uri[0]));photoCallback=null;}
        if(code==SAVE_BACKUP){byte[] bytes=pendingBackup;pendingBackup=null;if(result==RESULT_OK&&bytes!=null&&intent!=null&&intent.getData()!=null){try(OutputStream out=getContentResolver().openOutputStream(intent.getData())){if(out==null)throw new Exception();out.write(bytes);toast("学习备份已保存。");}catch(Exception e){toast("备份未保存，请重新导出。");}}}
    }

    private void receiveAuth(Uri uri){
        if(!"xiaoyangstudy".equals(uri.getScheme())||!"auth".equals(uri.getHost())||!"/callback".equals(uri.getPath())){toast("验证链接不正确。");return;}
        applyAuth(uri,"recovery".equals(uri.getQueryParameter("account"))?"recovery":"setup");
    }
    private void applyAuth(Uri result,String action){
        Uri.Builder dest=Uri.parse(HOME).buildUpon().appendQueryParameter("account",action);
        if(result.getQueryParameter("code")!=null)dest.appendQueryParameter("code",result.getQueryParameter("code"));
        if(result.getQueryParameter("error_description")!=null)dest.appendQueryParameter("error_description",result.getQueryParameter("error_description"));
        dest.encodedFragment(result.getEncodedFragment());web.loadUrl(dest.build().toString());
    }
    private void pasteAuth(){
        EditText input=new EditText(this);input.setHint("粘贴邮件里的完整验证链接");input.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_VARIATION_URI);input.setMinLines(3);input.setPadding(dp(18),dp(12),dp(18),dp(12));
        new AlertDialog.Builder(this).setTitle("打开邮件验证链接").setMessage("若邮件没有自动返回 App，长按邮件中的验证按钮复制链接，再粘贴到这里。不要把链接发给其他人。").setView(input).setNegativeButton("取消",null).setPositiveButton("打开",(d,w)->{
            String text=input.getText().toString().trim();input.setText("");Uri uri=Uri.parse(text);
            if("xiaoyangstudy".equals(uri.getScheme())){receiveAuth(uri);return;}
            if(!"https".equals(uri.getScheme())||!CLOUD.equals(uri.getHost())||uri.getPort()!=-1||uri.getUserInfo()!=null||!"/auth/v1/verify".equals(uri.getPath())){toast("请复制验证邮件中 Supabase 按钮的完整链接。");return;}
            toast("正在验证，请稍候…");
            new Thread(()->{
                HttpURLConnection connection=null;
                try{connection=(HttpURLConnection)new URL(uri.toString()).openConnection();connection.setInstanceFollowRedirects(false);connection.setConnectTimeout(15000);connection.setReadTimeout(15000);int status=connection.getResponseCode();String location=connection.getHeaderField("Location");if(status<300||status>=400||location==null)throw new Exception();Uri target=Uri.parse(location);String h=target.getHost();boolean accepted=local(target)||("xiaoyangstudy".equals(target.getScheme())&&"auth".equals(h))||"127.0.0.1".equals(h)||"localhost".equals(h);if(!accepted)throw new Exception();runOnUiThread(()->applyAuth(target,"recovery".equals(uri.getQueryParameter("type"))?"recovery":"setup"));}
                catch(Exception e){runOnUiThread(()->toast("验证未完成，链接可能已使用或过期。请重发最新邮件并重试。"));}
                finally{if(connection!=null)connection.disconnect();}
            },"email-verification").start();
        }).show();
    }
}
