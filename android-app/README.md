# 小洋专升本英语 安卓手机端源码 v1.0.39

本版更新：关于弹窗按安装包动态显示版本；首页显示连续学习、本周活跃天数、今日完成数和复习/计划/拼写入口；章节复习页说明单词卡的 1/3/7/15/30/60/90 天排期；接通 Android 每日本地提醒和通知权限；相机笔记照片保存到应用私有持久目录。没有修改云端数据库或 SQL。

此包为当前本地安卓工程的源码快照。
- android-app：安卓 Java 代码、界面样式、运行逻辑和构建脚本。
- 手机页面：App 内使用的 13 个 WebView 学习页面；它们是手机界面的必要源码。
- android-app/sql：本地保存的云端 SQL 文件，不代表云端数据库当前状态。不要未经检查重新执行旧迁移，尤其是 06。
- work/brand-logo.jpg：构建图标所需素材。

构建环境：JDK 17+、Android Platform 35、Build Tools 34.0.0、Python 和 Pillow。
配置 STUDY_JDK、STUDY_BUILD_TOOLS、STUDY_ANDROID_JAR 后，在本目录运行：
python -X utf8 android-app/build.py
构建时会获取固定版本的 Supabase JS。源码未包含 Android SDK/JDK。

签名密钥未包含。更新已有安装时，需在本机安全地恢复原 work/android-private 签名材料；没有原签名时，脚本生成的新签名不能覆盖原 App。

不包含独立电脑端应用、旧版本安装包、旧备份和网页发布说明。
本包未从云端导出数据；仅包含当前电脑保存的代码和 SQL。
