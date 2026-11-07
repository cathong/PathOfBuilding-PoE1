# PoE 1 简体中文 Mac 包

这份本地改动针对 Path of Building 2.67.2 Dev、PoE 1 3.29 和 Apple Silicon。点击窗口左下角的 **English** 或 **简体中文** 即可切换，选择会写入本包的设置。构筑和设置位于 `~/Library/Application Support/PathOfBuildingPoE1Zh-3dbca4463/User`。

本包翻译主导航和常用操作。可选的游戏词库用于显示技能、天赋和装备名称，词库未收录的名称、部分词缀和计算明细继续显示英文。构筑 XML、分享码、技能与装备解析沿用 PoB 的英文数据。中文输入法键入仍受上游引擎限制。

重新打包需要 Apple Silicon、Xcode Command Line Tools、Python 3、已验证的英文原生 `.app`（其 Info.plist 中的 `PoBSourceCommit` 为 `3dbca4463c0a59079d9f7f032d8240cf868e09da`）以及对应的 [PathOfBuilding-Mac](https://github.com/stevschmid/PathOfBuilding-Mac) `mac-v0.1.4` 源码。打包脚本用本机 CoreText 字体生成字形图集，并对输出包进行本机临时签名。

```sh
python3 macos-localization/package.py \
  --base-app '/path/to/Path of Building PoE1 Dev.app' \
  --port '/path/to/PathOfBuilding-Mac' \
  --terms '/path/to/local-poe1-zh-cn-terms' \
  --output '/path/to/Path of Building PoE1 中文.app'
```

`--terms` 可省略。当前本机包使用 PobTools-zh 固定提交 `3146017002865b3453a37d9e09d14053cbcf88ab` 的 `Data/poe1/zh-rCN`，包含 `gems.json`、`items.json`、`passives.json` 和 `uniques.json`。若自行准备该目录，同时保留上游 `NOTICE.md` 和记录来源的 `SOURCE.txt`。翻译数据取材于 GGG 客户端，授权说明随本地包附上。 [词库固定版本](https://github.com/Hsiung-Shao/PobTools-zh/tree/3146017002865b3453a37d9e09d14053cbcf88ab/pob-zh-engine/dist/Data/poe1/zh-rCN) · [上游版权说明](https://github.com/Hsiung-Shao/PobTools-zh/blob/3146017002865b3453a37d9e09d14053cbcf88ab/NOTICE.md)
