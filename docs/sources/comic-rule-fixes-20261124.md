# 两条漫画书源的规则修复 · 2026-11-24

这里只保留可复用的字段改动，不提交完整书源、Cookie、诊断数据或原始响应。先导出原规则以便回退。

## WEBTOON：取阅读区的实际页图

替换 `ruleContent.content`，其余字段保持不变。优先读取阅读区的 `data-url`，保留旧格式的显式 `imageList`，不再扫描全页 `<img>`。

```javascript
@js:
(function () {
  var pages = String(java.getString('@css:#_imageList img[data-url], img._images[data-url], .viewer_img img[data-url]@data-url') || '')
    .split(/\r?\n/).map(function (url) { return url.trim(); })
    .filter(function (url) { return /^https?:\/\//i.test(url); });
  if (pages.length) return pages.join('\n');

  var body = String(result || '');
  var first = body.indexOf('var imageList');
  if (first < 0) return '';
  var urls = /url\s*:\s*["']([^"']+)["']/g;
  var section = body.substring(first);
  for (var match; (match = urls.exec(section)) !== null;) {
    if (/^https?:\/\//i.test(match[1])) pages.push(match[1]);
  }
  return pages.join('\n');
})()
```

用同一份[公开样章](https://www.webtoons.com/zh-hant/romance/operation-true-love/%E5%BA%8F%E7%AB%A0/viewer?episode_no=1&title_no=4823)的响应对照：真实页图由 0 张恢复为 43 张，首、中、末三张在匿名浏览器中解码成功。该结果不代表已在纸间或 LiveContainer 跑通。

## 如漫画：把网页目录节点转换为可合并的章节行

仅把 `ruleToc.chapterList` 中的 `list = Array.from(result)` 改成下列内容，保留后续目录合并代码及正文规则。`chapterName` 仍读 `text`，`chapterUrl` 仍读 `href`。

```javascript
list = Array.from(result, function (node) {
  return {text: String(node.text()), href: String(node.attr('href'))};
})
```

原站目录样本有 20 个带标题的网页链接；混合目录问题已用节点与 JSON 对象的夹具复现。正文图片尚未通过验收。导入同一地址的规则可能覆盖当前版本；重新导入之前保存的原规则可回退。
