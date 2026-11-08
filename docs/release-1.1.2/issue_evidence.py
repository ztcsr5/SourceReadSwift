from pathlib import Path
import hashlib, json, shutil
O=Path('F:/SourceReadSwift/release-1.1.2'); I=O/'INPUT';I.mkdir(exist_ok=True)
root=Path('C:/Users/Edc21/Documents/xwechat_files/wxid_rpsqr5rjmyc222_4e8b/temp/RWTemp/2026-11/bb3b96445913ce671dac20c8773d584e')
names=['3514dc3b341cb2f04a10ffbca0d36cd4.jpg','e35563571a244bd7fc45da9ace3f0462.jpg','e000610641129b179fbe6eccadbaf031.jpg','f4baec78b5b0e83f18c95934d2efe2dd.jpg']
evidence=[]
for name in names:
    p=root/name
    if p.exists():
        shutil.copy2(p,I/name)
        evidence.append({'file':name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(O/'input-manifest.json').write_text(json.dumps(evidence,indent=2),encoding='utf8')
(O/'CHANGES.md').write_text('''# 1.1.2 / Build123 — 底部导航热修复

用户截图确认：主页/设置出现空白玻璃附件，阅读页面仍显示主页/发现/设置。

本轮只处理导航与附件，不改动分页排版、翻页手势、目录加载或书源解析。

- 不再挂载内容为空的 tabViewBottomAccessory；无播放任务就没有附件容器。
- 迷你音频面板按需放在子页面 safeAreaInset 中，不重建整个 TabView/NavigationStack。
- 阅读器、开书网关、hideRootTabBar 修饰器直接声明隐藏原生标签栏。
- 将根标签栏的可见性偏好移到 TabView 的子页面，不依赖 TabView 外层偏好。
- 保留 iOS26 原生玻璃导航及滚动收缩；iOS16–25 继续兼容导航。
- 新增隐藏所有权、多原生标签栏容器/附件检查、导航 push/pop 检查。
- iOS26 专项 CI 明确创建 26.x runtime，不能用旧模拟器跳过专项测试冒充通过。

最终测试与包信息见同目录 VERIFICATION.txt；真机实际外观仍需安装此包验收。

依据：[Apple toolbar](https://developer.apple.com/documentation/swiftui/view/toolbar(_:for:))、
[原生附件](https://developer.apple.com/documentation/uikit/uitabbarcontroller/bottomaccessory)。
''',encoding='utf8')
print('Input screenshots preserved:',len(evidence))
