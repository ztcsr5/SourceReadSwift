# Build 119 阅读核心恢复

用户明确要求接手并解决 Antigravity 最近反馈。本轮从 HEAD 5686485 开始，源文件原件已先备份到 F:/SourceReadSwift/recovery-119/BASELINE；不动书源引擎、书架、持久化格式、TTS功能和原有.bak。

阶段：
1. 已核对最新 Antigravity 到step5178：夹心已好；菜单不满意、裁字、阻尼仍在。后续分析有错：paragraphSpacing补偿与零位移springBack保护已经存在，PageCurl sync也已经animated:false。不得重复照抄。
2. 实施统一渲染测量验证、完整内容/几何缓存版本；替换水平分页交互事务，明确cover/slide差异；接回原生curl，保留已有正确同步；恢复UIButton/UIMenu且保留所有能力条件。
3. 增加原生回归测试；Windows静态验证后同commit GitHub macOS CI；不把Python模型和CI绿灯说成真机通过。
4. 打包交付与四件套（MODIFIED/DIFF/VERIFICATION/ROLLBACK），复核版本/提交/IPA hash。

本轮的稳定性声明只来自实际执行证据，不承诺100%无Bug或固定120Hz。旧聊天中的“只分析不改”不约束用户当前明确修复请求。
