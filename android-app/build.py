"""Build a signed, dependency-free native Android host for the existing study app.

Requires JDK 17+ plus Google's Android platform 35 and build-tools 34.0.0.
Paths can be overridden with STUDY_JDK, STUDY_BUILD_TOOLS and STUDY_ANDROID_JAR.
Signing material stays outside the source and deliverable archives.
"""
from pathlib import Path
import os, re, subprocess, json, secrets, zipfile, hashlib, urllib.request, shutil, xml.etree.ElementTree as ET
from PIL import Image, ImageOps

P = Path(__file__).resolve().parent
B = P.parent
W = B/'work'
version=ET.parse(P/'AndroidManifest.xml').getroot().attrib['{http://schemas.android.com/apk/res/android}versionName']
BUILD = W/'android-build'
ASSETS = BUILD/'assets'
CLASSES = BUILD/'classes'
DEX = BUILD/'dex'
GENERATED = BUILD/'generated'
for d in [BUILD,ASSETS,CLASSES,DEX,GENERATED]: d.mkdir(parents=True,exist_ok=True)
JDK = Path(os.environ.get('STUDY_JDK','D:/develop/jdk'))
TOOLS = Path(os.environ.get('STUDY_BUILD_TOOLS',str(W/'android-toolchain/build-tools_r34-windows/android-14')))
ANDROID = Path(os.environ.get('STUDY_ANDROID_JAR',str(W/'android-toolchain/platform-35_r02/android-35/android.jar')))
env = dict(os.environ, JAVA_HOME=str(JDK))
def run(args, **kw):
    result = subprocess.run([str(a) for a in args], env=env, capture_output=True, text=True,encoding='utf-8',errors='replace',**kw)
    if result.returncode: raise RuntimeError(result.stdout+'\n'+result.stderr)
    return result.stdout
def rel(path):return os.path.relpath(path,B)

# Include only the 13 live pages, not old backups, cloud setup notes, or user data.
modules=['','500','courses','essay','grammar','mother','papers','phon','phonics','plan','review','root','spell']
live=B/'手机页面'
shutil.copy2(live/'32day-data.js',ASSETS/'32day-data.js')
sdk=ASSETS/'vendor/supabase-2.108.1.js'
sdk.parent.mkdir(exist_ok=True)
if not sdk.exists():
    urllib.request.urlretrieve('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.108.1/dist/umd/supabase.js',sdk)
assert sdk.stat().st_size>10000
native=(P/'native.js').read_text(encoding='utf-8')+'\n'+(P/'native-select.js').read_text(encoding='utf-8')+'\n'+(P/'android-cloud.js').read_text(encoding='utf-8')+'\n'+(P/'glass-motion.js').read_text(encoding='utf-8')
review_runtime=(P/'review-system-v14.js').read_text(encoding='utf-8')
spell_runtime=(P/'spell-batch-v14.js').read_text(encoding='utf-8')
spell_scope_runtime=(P/'spell-scope-native.js').read_text(encoding='utf-8')
word_review_runtime=(P/'android-word-review.js').read_text(encoding='utf-8')
preserve_spell_runtime=(P/'android-preserve-spell.js').read_text(encoding='utf-8')
native_css=(P/'native.css').read_text(encoding='utf-8')+'\n'+(P/'native-theme.css').read_text(encoding='utf-8')+'\n'+(P/'review-system-v14.css').read_text(encoding='utf-8')
(ASSETS/'native.js').write_text(native,encoding='utf-8')
shutil.copytree(P/'legal',ASSETS/'legal',dirs_exist_ok=True)
shutil.copy2(P/'data/handbook-abc.json',ASSETS/'handbook-abc.json')
for module in modules:
    relative=Path(module)/'index.html'
    text=(live/relative).read_text(encoding='utf-8')
    if module=='review':text=text.replace('<body class="en-page-full">','<body class="en-page-full en-page-review">',1)
    prefix='../' if module else ''
    old='https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.108.1/dist/umd/supabase.js'
    assert text.count(old)==1, module
    text=text.replace(old,prefix+'vendor/supabase-2.108.1.js')
    text=text.replace('</head>','<style data-android-shell>'+native_css+'</style><script src="'+prefix+'native.js"></script></head>',1)
    old="function redirect(action){const u=new URL(location.href);u.search='';u.hash='';u.searchParams.set('account',action);return u.href}"
    assert text.count(old)==1, module
    text=text.replace(old,"function redirect(action){return 'xiaoyangstudy://auth/callback?account='+encodeURIComponent(action)}")
    text=text.replace('当前本机预览地址只能在这台电脑打开；手机使用还需要发布后的正式网址。','当前为安卓 App；用同一邮箱和密码登录，可读取云端学习进度。')
    text=text.replace('打开邮件中的确认链接，再回到这里检查。','打开邮件中的确认链接后返回 App；若未自动跳回，可在 App 菜单中选择“打开邮件验证链接”。')
    text=text.replace('请在你能打开本站的设备上使用邮件链接。','打开邮件链接后返回 App；未自动跳回时，可从 App 菜单打开复制的完整验证链接。')
    text=text.replace('备份已下载，不包含密码或登录凭证。','请在系统窗口选择备份保存位置，不包含密码或登录凭证。')
    text=text.replace('App 右上角菜单','App 底部“我的”').replace('App 菜单','“我的”')
    # Remove the legacy personal-vocabulary favorites feature from the 500-word module.
    text=text.replace("+(module==='core'?'<option value=\"starred\" '+(filter==='starred'?'selected':'')+'>我的生词本</option><option value=\"mistake\" '+(filter==='mistake'?'selected':'')+'>待订正自测</option>':'')", "+(module==='core'?'<option value=\"mistake\" '+(filter==='mistake'?'selected':'')+'>待订正自测</option>':'')")
    text=text.replace("+button(data('core',u.key).starred?'★ 已收藏':'☆ 放入生词本','star','data-key=\"'+esc(u.key)+'\"')", '')
    text=re.sub(r"\n if\(a==='star'\)\{[^\n]*\}", '', text)
    text=text.replace("filter==='starred'&&r.data.starred", "false")
    # Module review is consolidated in the global review navigation.
    text=text.replace(",[\'review\',\'本模块复习\']", "")
    completion_old = "function completion(u,label='确认完成，安排复习'){return '<div class=\"v4-completion\">'+button(done(module,u.key)?'✓ 已完成 · 保留原记录':label,'complete','data-key='+esc(u.key)+' '+(!ready||busy||done(module,u.key)?'disabled':''),'primary')+'<small class=\"en-muted\">首次完成后安排第 1、3、7、14 天复习；再次打开不会重复打卡。</small></div>}"
    completion_new = "function completion(u,label='确认完成，安排复习'){const isDone=done(module,u.key),wordModule=['core','mother','phon','phonics'].includes(module);return '<div class=\"v4-completion\">'+button(isDone?'取消打卡并移出复习':label,isDone?'uncomplete':'complete','data-key='+esc(u.key)+' '+(!ready||busy?'disabled':''),isDone?'':'primary')+'<small class=\"en-muted\">'+(isDone?'取消后会移出复习；再次打卡将重新安排。':wordModule?'单词卡按掌握程度安排 1、3、7、15、30、60、90 天复习。':'首次完成后安排第 1、3、7、14 天复习。')+'</small></div>'}"
    if completion_old in text:
        text=text.replace(completion_old,completion_new)
    else:
        # Minor v1.0.14 source variants use different completion wording;
        # replace the whole renderer while keeping the surrounding page intact.
        text,n=re.subn(r"function completion\(u,label='确认完成，安排复习'\)\{return [^\n]*\}",completion_new,text,count=1)
        assert n==1 or module in ('root','review','plan'), 'completion control not found in '+module
    text=text.replace("if(a==='complete'){const u=units().find(x=>x.key===k),payload={title:u?.title||k};", "if(a==='uncomplete'){if(!confirm('取消这项打卡？它会从复习队列移出，再次打卡将重新安排复习。'))return;await write(()=>rpc('study_uncomplete',{p_module:module,p_key:k}),'已取消打卡并移出复习队列。');return}\n if(a==='complete'){const u=units().find(x=>x.key===k),payload={title:u?.title||k};")
    # User-created learning materials can be archived from the Android UI.
    # Archive keeps notes and review history while removing the item from lists.
    catalog_open = "+button('打开学习 →','open','data-key=\"'+esc(u.key)+'\"')+(u.phon?"
    catalog_actions = "+button('打开学习 →','open','data-key=\"'+esc(u.key)+'\"')+(u.kind==='custom'?button('编辑','editItem','data-key=\"'+esc(u.key)+'\"')+button('移除','deleteItem','data-key=\"'+esc(u.key)+'\"'):'')+(u.phon?"
    if catalog_open in text:
        text=text.replace(catalog_open,catalog_actions)
    lesson_edit = "+button('编辑资料','editItem','data-key=\"'+esc(u.key)+'\"')+'</div>'"
    lesson_actions = "+button('编辑资料','editItem','data-key=\"'+esc(u.key)+'\"')+button('移除资料','deleteItem','data-key=\"'+esc(u.key)+'\"')+'</div>'"
    if lesson_edit in text:
        text=text.replace(lesson_edit,lesson_actions)
    course_edit = "+button('编辑链接','courseLinkEdit','data-key=\"'+esc(u.key)+'\" '+disabled)+'</div></article>'"
    course_actions = "+button('编辑链接','courseLinkEdit','data-key=\"'+esc(u.key)+'\" '+disabled)+button('移除链接','deleteItem','data-key=\"'+esc(u.key)+'\" '+disabled)+'</div></article>'"
    if course_edit in text:
        text=text.replace(course_edit,course_actions)
    delete_anchor = " if(a==='courseLinkEdit'){if(busy||StudyAccount.locked)return;"
    delete_handler = " if(a==='deleteItem'){if(busy||StudyAccount.locked)return;const item=records.find(r=>r.module===module&&r.item_key===k&&r.data.kind==='custom');if(!item){notify('这项资料已不存在，请刷新后重试。');return}if(!confirm('移除“'+(item.data.title||'这项资料')+'”？笔记和复习记录会保留。'))return;await write(()=>rpc('study_save',{p_module:module,p_key:k,p_data:{archived:true}}),'资料已从列表移除，学习记录仍保留。',()=>{selected='';view='library';const q=new URLSearchParams(location.search);q.set('view','library');q.delete('item');history.replaceState(null,'','?'+q)});return}\n" + delete_anchor
    if delete_anchor in text:
        text=text.replace(delete_anchor,delete_handler,1)
    # Keep the Android build focused on in-app learning. Browser-only legacy import
    # panels and local-preview wording are useful on the web source but misleading
    # after the pages are packaged into the app.
    text=re.sub(r'<section class="en-card"><h2 class="v4-card-title">核对本浏览器的旧进度</h2>.*?</section>', '', text, count=1, flags=re.S)
    text=text.replace('暂时不要清理浏览器数据。若邮箱已有账号，请改用登录；未验证前进度仍保留在当前访客下。','未绑定账号前请不要清理 App 数据；若邮箱已有账号，请改用登录。')
    text=text.replace('换电脑、手机或浏览器后，使用同一个邮箱和密码继续学习。','换手机或其他设备后，使用同一个邮箱和密码继续学习。')
    text=text.replace('绑定邮箱并设置密码后，可在其他设备登录同一账号继续学习。访客请保留浏览器登录数据。','绑定邮箱并设置密码后，可在其他设备登录同一账号继续学习。未绑定前请不要清理 App 数据。')
    text=re.sub(r'function notePanel\(u\)\{.*?\}', "function notePanel(u){return '<section class=\"en-card\">'+(module==='papers'?photoPanel():'')+completion(u)+spellingEntry(u)+'</section>'}", text, count=1)
    text=re.sub(r'<form id="noteForm" class="v4-form"><label>本课笔记.*?</form>', '', text, flags=re.S)
    if module=='root':
        text=text.replace('btn.textContent="第"+sday()+"天已完成 ✓";', 'btn.textContent="取消第"+sday()+"天打卡";')
        text=text.replace('btn.onclick=null;', 'btn.onclick=()=>uncheck(sday());')
        text=text.replace('rootBusy||doneSet().has(sday())', 'rootBusy')
        text=text.replace("async function check(d){\n  return rootWrite(()=>rootClient.rpc('day32_complete',{p_day:d}),r=>r.newly_completed?'第'+d+'天已保存到云端，复习卡已安排。':'本课已打卡，原完成时间和复习记录已保留。');\n}", "async function check(d){return rootWrite(()=>rootClient.rpc('day32_complete',{p_day:d}),r=>r.newly_completed?'第'+d+'天已保存到云端，复习卡已安排。':'本课已打卡。');}\nasync function uncheck(d){if(!confirm('取消第'+d+'天打卡？该课会从复习队列移出，再次打卡会重新安排复习。'))return false;return rootWrite(()=>rootClient.rpc('day32_uncomplete',{p_day:d}),'已取消打卡并移出复习队列。')}")
        text=text.replace("rootClient.from('day32_reviews').select('id,day_no,scheduled_for')", "rootClient.from('day32_reviews').select('*')")
        text=text.replace("const today=rootDateKey(),due=rootPending.filter(r=>r.scheduled_for<=today);", "const today=rootDateKey(),due=rootPending.filter(r=>r.active!==false&&!r.paused&&r.scheduled_for<=today);")
        text=text.replace("rootPending.filter(r=>r.scheduled_for>today).forEach(r=>future[r.scheduled_for]=(future[r.scheduled_for]||0)+1);", "rootPending.filter(r=>r.active!==false&&!r.paused&&r.scheduled_for>today).forEach(r=>future[r.scheduled_for]=(future[r.scheduled_for]||0)+1);")
        text=text.replace("const lessons=rootUnwrap(a)||[];const pending=rootUnwrap(b)||[];", "const lessons=rootUnwrap(a)||[];const pending=(rootUnwrap(b)||[]).filter(r=>r.active!==false&&!r.paused);")
    if module=='spell':
        anchor='StudyAccount.setBusinessBusy(()=>busy);'
        assert text.count(anchor)==1
        text=text.replace(anchor,anchor+'\n'+spell_runtime+'\n'+spell_scope_runtime+'\n'+word_review_runtime+'\n'+preserve_spell_runtime,1)
    elif module!='root':
        anchor='StudyAccount.setBusinessBusy(()=>busy);'
        assert text.count(anchor)==1, module
        text=text.replace(anchor,anchor+'\n'+review_runtime+'\n'+word_review_runtime,1)
    if module=='root':
        text=text.replace("rootClient.rpc('day32_uncomplete',{p_day:d})", "StudyCloud.cancelRoot(rootClient,rootSession.user.id,d)")
        text=text.replace("document.addEventListener('visibilitychange',()=>{if(!document.hidden&&rootReady&&!rootBusy)rootRefresh()});", "document.addEventListener('visibilitychange',()=>{if(!document.hidden&&!rootBusy)rootRefresh()});")
        text=text.replace("StudyAccount.setBusinessBusy(()=>rootBusy);", "StudyAccount.setBusinessBusy(()=>rootBusy);\nwindow.addEventListener('online',()=>{if(!rootBusy&&!document.hidden)rootRefresh()});")
    else:
        text=text.replace("rpc('study_uncomplete',{p_module:module,p_key:k})", "StudyCloud.cancelModule(client,session.user.id,module,k)")
        text=text.replace("StudyAccount.setBusinessBusy(()=>busy);", "StudyAccount.setBusinessBusy(()=>busy);\nwindow.addEventListener('online',()=>{if(!busy&&!document.hidden&&!practice)refresh()});")
        text=text.replace("let html=isLinkModule()?courseLinksView():hero();", "if(!ready){const retry=document.createElement('button');retry.type='button';retry.className='en-btn';retry.textContent=busy?'正在连接…':'重新连接';retry.disabled=busy;retry.onclick=refresh;$('globalError').append(document.createElement('br'),retry)}let html=isLinkModule()?courseLinksView():hero();")
    destination=ASSETS/relative;destination.parent.mkdir(exist_ok=True);destination.write_text(text,encoding='utf-8')

logo=Image.open(W/'brand-logo.jpg').convert('RGB')
for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    folder=P/'res'/('mipmap-'+density);folder.mkdir(exist_ok=True)
    icon=Image.new('RGB',(size,size),'#152236');inner=ImageOps.contain(logo,(round(size*.82),round(size*.82)),Image.Resampling.LANCZOS)
    icon.paste(inner,((size-inner.width)//2,(size-inner.height)//2));icon.save(folder/'ic_launcher.png')

# Compile Java and resources without Gradle or an additional application framework.
unsigned=BUILD/'unsigned.apk'
run([TOOLS/'aapt.exe','package','-f','-M',rel(P/'AndroidManifest.xml'),'-S',rel(P/'res'),'-A',rel(ASSETS),'-I',rel(ANDROID),'-F',rel(unsigned),'-J',rel(GENERATED)],cwd=B)
sources=list((P/'src').rglob('*.java'))+list(GENERATED.rglob('*.java'))
args=BUILD/'javac.args'
def quoted(path):return '"'+str(path).replace('\\','/')+'"'
args.write_text('\n'.join(['-encoding','UTF-8','-source','8','-target','8','-Xlint:-options','-bootclasspath',quoted(rel(ANDROID)+os.pathsep+rel(TOOLS/'core-lambda-stubs.jar')),'-d',quoted(rel(CLASSES))]+[quoted(rel(p)) for p in sources]),encoding='utf-8')
run([JDK/'bin/javac.exe','-J-Duser.language=en','@'+rel(args)],cwd=B)
class_files=list(CLASSES.rglob('*.class'))
d8args=BUILD/'d8.args'
d8args.write_text('\n'.join(['--release','--min-api','26','--lib',rel(ANDROID),'--output',rel(DEX)]+[rel(p) for p in class_files]),encoding='utf-8')
run([JDK/'bin/java.exe','-cp',TOOLS/'lib/d8.jar','com.android.tools.r8.D8','@'+rel(d8args)],cwd=B)
with zipfile.ZipFile(unsigned,'a',zipfile.ZIP_DEFLATED) as z:
    for p in DEX.glob('*.dex'):z.write(p,p.name)
aligned=BUILD/'aligned.apk'
run([TOOLS/'zipalign.exe','-f','-p','4',rel(unsigned),rel(aligned)],cwd=B)

private=W/'android-private';private.mkdir(exist_ok=True)
secret=private/'signing.json';keystore=private/'xiaoyang-release.p12'
if not secret.exists():secret.write_text(json.dumps({'alias':'xiaoyang-study','password':secrets.token_urlsafe(36)}),encoding='utf-8')
credentials=json.loads(secret.read_text(encoding='utf-8'))
env['STUDY_SIGNING_PASSWORD']=credentials['password']
if not keystore.exists():
    run([JDK/'bin/keytool.exe','-genkeypair','-keystore',keystore,'-storetype','PKCS12','-alias',credentials['alias'],'-keyalg','RSA','-keysize','3072','-validity','10000','-dname','CN=XiaoYang Study, OU=Personal, O=XiaoYang, C=CN','-storepass:env','STUDY_SIGNING_PASSWORD'])
out=BUILD/'signed.apk'
run([JDK/'bin/java.exe','-jar',TOOLS/'lib/apksigner.jar','sign','--ks',keystore,'--ks-key-alias',credentials['alias'],'--ks-pass','env:STUDY_SIGNING_PASSWORD','--out',out,aligned])
verification=run([JDK/'bin/java.exe','-jar',TOOLS/'lib/apksigner.jar','verify','--verbose','--print-certs',out])
assert 'Verified using v2 scheme (APK Signature Scheme v2): true' in verification
run([TOOLS/'zipalign.exe','-c','4',rel(out)],cwd=B)
badging=run([TOOLS/'aapt.exe','dump','badging',rel(out)],cwd=B)
assert "package: name='com.xiaoyang.studyenglish'" in badging
with zipfile.ZipFile(out) as z:
    assert z.testzip() is None
    assert len([n for n in z.namelist() if n.startswith('assets/') and n.endswith('index.html')])==13
    assert not any('private' in n or n.endswith('.p12') or n.endswith('.sql') for n in z.namelist())
(B/'outputs').mkdir(exist_ok=True)
release=B/('outputs/小洋专升本英语-安卓安装包-v'+version+'.apk')
shutil.copy2(out,release)
report={'apk':release.name,'bytes':out.stat().st_size,'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'sdk_js_sha256':hashlib.sha256(sdk.read_bytes()).hexdigest(),'pages':13,'minAndroid':'8.0','targetApi':35,'signatureVerification':verification,'badging':badging}
(BUILD/'apk-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k not in ['signatureVerification','badging']},ensure_ascii=False,indent=2))
