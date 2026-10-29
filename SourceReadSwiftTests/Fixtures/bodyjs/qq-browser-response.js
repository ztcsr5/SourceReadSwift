var browser = JSON.parse(String(result));
var officialUrl = "https://newopensearch.reader.qq.com/wechat?keyword=" + encodeURIComponent(String(key)) + "&start=" + ((page - 1) * 20) + "&end=" + (page * 20 - 1);
var officialText = java.ajax(officialUrl);
var official = {};
try { official = JSON.parse(String(officialText)); } catch (e) { official = {}; }
var books = [];
var seen = {};
function addBook(item) {
  var mark = String(item.name || "").replace(/\s+/g, "").toLowerCase() + "|" + String(item.author || "").replace(/\s+/g, "").toLowerCase();
  if (!item.name || seen[mark]) return;
  seen[mark] = true;
  books.push(item);
}
function officialKind(raw) {
  var parts = String(raw || "").split(",");
  var names = [];
  var used = {};
  for (var n = 0; n < parts.length; n++) {
    var bits = parts[n].split(":");
    var label = bits.length > 1 ? bits[1] : "";
    if (label && label != "小说" && !used[label]) { used[label] = true; names.push(label); }
  }
  return names.join("·");
}
var states = page == 1 && browser && browser.data && browser.data.state ? browser.data.state : [];
for (var i = 0; i < states.length; i++) {
  var items = states[i].items || [];
  for (var j = 0; j < items.length; j++) {
    var b = items[j];
    var resourceId = String(b.docId || "").replace(/^.*_/, "");
    addBook({name:b.title, author:b.author, coverUrl:b.cover_url, intro:b.abstract, kind:String(b.tag_views || "").replace(/\s+/g, "·"), resourceId:resourceId, lastChapter:"", wordCount:"", bookUrl:"https://novel.html5.qq.com/qbread/api/novel/bookInfo?resourceId=" + resourceId, searchFrom:"QQ浏览器"});
  }
}
var list = official && official.booklist ? official.booklist : [];
for (var k = 0; k < list.length; k++) {
  var o = list[k];
  var bid = String(o.bid || "0");
  var resourceId2 = String(1100000000 + parseInt(bid, 10));
  var tail = parseInt(bid.slice(-3), 10);
  var dir = tail < 10 ? bid.slice(-1) : (tail < 100 ? bid.slice(-2) : bid.slice(-3));
  var cover = "https://wfqqreader-1252317822.image.myqcloud.com/cover/" + dir + "/" + bid + "/b_" + bid + ".jpg";
  addBook({name:o.title, author:o.author, coverUrl:cover, intro:o.intro, kind:officialKind(o.categoryInfoV4), resourceId:resourceId2, lastChapter:o.updateInfo, wordCount:o.totalWords, bookUrl:"https://bookshelf.html5.qq.com/qbread/api/novel/intro-info?bookid=" + resourceId2, searchFrom:"QQ阅读"});
}
JSON.stringify({books:books})
