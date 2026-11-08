import os

path = r"D:\Gemini反重力\SourceReadSwift2\SourceReadSwift\Core\Storage\PurifyRuleStore.swift"
with open(path, "r", encoding="utf-8") as f:
    text = f.read().replace("\r\n", "\n")

target_anchor = 'id: "control-residue"'
idx = text.find(target_anchor)
assert idx != -1, "control-residue not found"

close_preset = text.find("        )\n    ]", idx)
assert close_preset != -1, "close preset not found"

end_of_preset = close_preset + len("        )")

new_presets = """,
        PurifyRulePreset(
            id: "anti-scraping",
            title: "防盗与伪源水印",
            detail: "过滤“首发域名、笔趣阁/69书吧/飘天文学首发、最新网址”等站点防盗水印行。",
            patterns: [
                "(?im)^\\\\s*(?:请记住本书首发域名|本文由.*整理发布|笔趣阁.*首发|69书吧.*首发|飘天文学|最新网址)[^\\\\r\\\\n]*(?:\\\\r?\\\\n|$)##",
                "(?im)^\\\\s*(?:天才一秒记住|顶点小说.*提供|小说网.*更新最快|本章未完，请点击下一页)[^\\\\r\\\\n]*(?:\\\\r?\\\\n|$)##"
            ]
        ),
        PurifyRulePreset(
            id: "social-groups",
            title: "读者群与社交引流",
            detail: "清理官方QQ群、书友交流群、加群看无删减、微信公众号等引流信息。",
            patterns: [
                "(?im)^\\\\s*(?:官方QQ群|读者群|书友交流群|加群看无删减|关注微信公众号|微信公众号)[：:][^\\\\r\\\\n]*(?:\\\\r?\\\\n|$)##",
                "(?im)^\\\\s*(?:QQ群号|扣扣群|企鹅群)[：:\\\\s]*[0-9]{5,12}[^\\\\r\\\\n]*(?:\\\\r?\\\\n|$)##"
            ]
        ),
        PurifyRulePreset(
            id: "author-notes",
            title: "求票打赏与尾巴",
            detail: "清理求月票、求推荐票、求打赏、求订阅、求全订、投推荐票等尾部催票内容。",
            patterns: [
                "(?im)^\\\\s*(?:求月票|求推荐票|求打赏|求订阅|求全订|投推荐票|投月票|感谢各位书友的打赏)[^\\\\r\\\\n]*(?:\\\\r?\\\\n|$)##",
                "(?im)^\\\\s*(?:PS[:：]|作者有话说[:：]|PS：今日已更新)[^\\\\r\\\\n]*(?:\\\\r?\\\\n|$)##"
            ]
        ),
        PurifyRulePreset(
            id: "transcode-alerts",
            title: "转码与缺字提示",
            detail: "清理“本章字数过少、如遇断更请退出转码、内容手打中”等抓取残留提示。",
            patterns: [
                "(?im)^\\\\s*(?:本章内容字数过少|如遇断更|请退出转码页面|如果章节有错误|点击刷新重新加载)[^\\\\r\\\\n]*(?:\\\\r?\\\\n|$)##",
                "(?im)^\\\\s*(?:内容防盗防乱抓|内容正在手打中|章节内容更新中)[^\\\\r\\\\n]*(?:\\\\r?\\\\n|$)##"
            ]
        )"""

updated = text[:end_of_preset] + new_presets + text[end_of_preset:]
with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write(updated)
print("SUCCESS: PurifyRuleStore.swift updated!")
