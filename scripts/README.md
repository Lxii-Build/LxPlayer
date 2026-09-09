# 脚本

## inspect-screenshot.js

分析 CI 产出的界面截图，按纵向分带打印每段的内容密度与底色，
用来核对「界面结构是否符合设计」，而不是只看构建有没有过。

```bash
# 从 Actions 下载 lxplayer-screenshots 产物解压后
node scripts/inspect-screenshot.js
```

输出示例（深色首页）：

```
 408 内容 33% #############    底色 rgb(36,36,36)   ← 卡片区（#242424）
1224 内容 78% ###############  底色 rgb(27,27,27)   ← 横向封面卡带
```

**为什么需要它**：核验截图时手写过一版 PNG 解析，忘了处理逐行 filter
（PNG 每行开头有一个 filter type 字节，第 1~4 型是差分编码），
读出来的像素全是错的——alpha 恒为 0，于是误判「截图是全透明的空图」，
还据此改了两轮代码。这个脚本实现了正确的 defilter（Sub/Up/Average/Paeth），
以后核验截图直接用它，不要临时手写。
