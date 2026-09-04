extends Node
## SaveManager：最小可解析占位（WP-02）。
## WP-06 才实现 Manifest/原子保存/备份；本轮不读写任何存档文件。

var saves_enabled := false
