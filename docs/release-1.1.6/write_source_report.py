from pathlib import Path
import collections, json
import ci

folder = ci.OUT/'source-audit'
audit = json.loads((folder/'comic-pipeline-31.json').read_text(encoding='utf8'))
assert audit['head'] == ci.ci.HEAD
raw = json.loads(Path('D:/QQ游戏/all_book_sources.json').read_text(encoding='utf-8-sig'))
types = collections.Counter(s.get('bookSourceType',0) for s in raw)
lines = [
    '# 纸间 1.1.6 漫画书源逐项检测', '',
    f"代码：`{audit['head']}`", f"输入 SHA256：`{audit['input_sha256']}`", '',
    f"输入实际为 {len(raw)} 个配置。类型分布：{dict(sorted(types.items()))}。997 个配置完成静态清点；联网链路检测覆盖全部 31 个 type=2 配置，并非 997 个源全部联网测完。", '',
    '## 检测口径', '',
    '- 使用应用正式解析引擎：搜索 → 第一条结果 → 目录 → 第一章 → 首张图片实际解码。',
    '- 优先作者 checkKeyWord，否则使用“斗罗”。第一条结果未必与关键字同名；结果不代表目标作品或全部作品可读。',
    '- 每个源单独引擎，3 路并发，搜索/目录/正文设置超时；目录和正文各取一页。不执行登录或购买。',
    '- 图片数量表示解析到的列表长度，只有首图实际请求与解码。重复配置仍逐个记录，不作为独立站点统计。',
    f"- 本轮 {audit['decoded']}/31 个配置首图成功；包括重复配置及 1 个写真图库。其余项保留失败阶段，不直接等同于源失效。", '',
    '## 已确认与仍待解决', '',
    '- 漫画搬运：CSS 节点经 JavaScript Array.from 转对象目录的桥接已修复，本轮提取 153 章，首章 5 张图，首图成功。',
    '- 爱优漫吧：数组 split 换行兼容已修复，原来逗号拼接成一个错误 URL，现在提取 10 张独立图片；两个配置首图均成功。',
    '- 直链图片章节：已添加按图片 MIME 直接保留响应 URL 的生产路径与确定性测试；名著阅读本轮正文超时，不能宣称已通过联网验证。',
    '- 漫画小屋：此前运行两个配置首图成功，本轮失败，存在时效/网络等未定位因素，不能宣称稳定修复。',
    '- 开心漫画：作者规则返回“检测到书源被恶意篡改”，本轮未通过。保留原作者配置，不盲改其校验。',
    '- 漫画台吧：目录有 33 章，但正文图片列表为空，仍未定位到可用图片。',
    '- 红牛资源：type=2 配置实际返回 m3u8 视频，不是漫画图片；没有把它虚算为漫画兼容成功。',
    '- HTTP403、搜索空结果、接口字段不匹配、图片请求/解码失败分别保留。空结果不能仅凭本次关键字判定整源失效。', '',
    '## 31 项结果', '',
    '|序号|配置|阶段|目录章数|图片列表|首图|耗时秒|结果说明|',
    '|---:|---|---|---:|---:|---|---:|---|'
]
for row in audit['rows']:
    def clean(value): return str(value).replace('|','／').replace('\n',' ')
    lines.append('|'+ '|'.join(map(clean,[row['index']+1,row['name'],row['stage'],row['chapterCount'],row['imageCount'],'成功' if row['decoded'] else '未通过',f"{row['elapsedSeconds']:.2f}",row['message']]))+'|')
lines += ['', '原始结构化结果：同目录 comic-pipeline-31.json / comic-pipeline-31.csv。',
          '全量静态清点：同目录 all-997-static-inventory.json。',
          '未完成：全站/全书/全部章节验证、手机本地网络复测、其余非漫画源逐项联网验证。', '']
(folder/'漫画书源检测报告.md').write_text('\n'.join(lines),encoding='utf8')
print(folder/'漫画书源检测报告.md')
