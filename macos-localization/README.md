# PoE 1 简体中文 Mac 包

这是 Apple Silicon 原生 PoB 的简体中文版本。点击窗口左下角 **English** 或 **简体中文** 切换，选择会写入设置。正式版始终沿用：

```text
~/Library/Application Support/PathOfBuildingPoE1Zh-3dbca4463/User
```

其中 `Builds` 是构筑，`Settings.xml` 是设置。目录名里的旧提交短号是固定标识，不随新版变化。原生启动器刷新的是同级的 `src` 缓存。

界面翻译和可选词库在绘制时生效，覆盖侧栏攻防数据、计算明细、配置选项、装备和技能提示。数值词缀沿用原参数和范围。构筑 XML、分享码、可编辑文本和引擎解析仍使用原文。词库之外的词条和版本更新日志可能继续显示英文。中文输入法键入受原生引擎限制。

## 查询并准备更新

本包关闭原版的应用内更新。上游清单会直接替换部分带汉化调用的 Lua 文件，不能用英文包的更新器更新本包。在这个源码仓库根目录运行：

```sh
python3 -B macos-localization/update.py --check-only
```

该命令在临时克隆中查询 PoB Community 的 `dev`，用完整提交判断是否有新版，不凭显示版本号。安装的 `3dbca4463` 与较早的稳定标签 `v2.67.2` 都可能显示 2.67.2，后者不是升级。可以用 `--ref refs/tags/vX.Y.Z` 指定未来的官方标签；工具会拒绝回退或分叉不明的源码。

准备候选包需要 Apple Silicon、Python 3、Xcode Command Line Tools、现有已签名的中文版、干净的本项目源码，以及 [PathOfBuilding-Mac mac-v0.1.4](https://github.com/stevschmid/PathOfBuilding-Mac/releases/tag/mac-v0.1.4) 源码。只需克隆一次移植源码，放在日后仍可访问的位置：

```sh
git clone --depth 1 --branch mac-v0.1.4 \
  https://github.com/stevschmid/PathOfBuilding-Mac.git "$HOME/PathOfBuilding-Mac-0.1.4"
mkdir -p "$HOME/Downloads/PoB更新候选"
python3 -B macos-localization/update.py \
  --port "$HOME/PathOfBuilding-Mac-0.1.4" \
  --output "$HOME/Downloads/PoB更新候选/Path of Building PoE1 中文 预览.app"
```

脚本在临时克隆中把上游合入中文版源码，使用完整的合并结果生成候选包，重新生成中文字形图集及本机签名。它保留真实提交、源码树和原生运行库来源，输出未使用的新路径，不覆盖现用应用。已知的上游原生运行库文件或图形接口声明变更、Git 合并冲突、缺失汉化文件、异常的用户目录逻辑都会令脚本停止。遇到冲突先在独立维护分支处理，再重跑。运行库不兼容时先升级并验证 Mac 移植，不能将 Windows DLL 复制到 Mac 包。

默认复用当前 app 中的游戏词库；用 `--terms /path/to/terms` 传入经过核验的新词库，`--no-terms` 则只保留界面汉化。词库需包含 `gems.json`、`items.json`、`passives.json`、`uniques.json`，以及 `NOTICE.md` 和标明来源提交的 `SOURCE.txt`。本机原词库来自 [PobTools-zh 固定版本](https://github.com/Hsiung-Shao/PobTools-zh/tree/3146017002865b3453a37d9e09d14053cbcf88ab/pob-zh-engine/dist/Data/poe1/zh-rCN)，[授权说明](https://github.com/Hsiung-Shao/PobTools-zh/blob/3146017002865b3453a37d9e09d14053cbcf88ab/NOTICE.md) 随包保留。可额外提供同目录的 `ui.json`、`stats.json`、`tags.json`、`monsters.json`，并附上 `LICENSE-PobTools.txt`。可再提供 `tree_names.json`、`tree_effects.json`、`gem_descriptions.json` 和 `game_stats_extra.json`。其中天赋译名按节点 ID 和英文名称匹配，天赋属性及技能说明按英文原文匹配，额外词缀按原文和安全的数值模板匹配。词库更新时请在 `SOURCE.txt` 记录游戏版本和数据来源。打包会纳入这些数据，重新生成字形。新赛季引擎与词库可以分别更新，缺失译名的内容会回退英文。

## 验收和切换正式版

1. 启动预览包。它的应用标识不同，使用 `PathOfBuildingPoE1Zh-3dbca4463-Preview/User`，不会读写正式构筑。将少量旧构筑**复制**到预览的 `Builds`。检查中文菜单和实际画面，中英文切换后重启，确认语言选择保留。分别打开毒瓶、裂风雷球和新星电球，检查天赋、技能、计算、永恒珠宝及分享码。在旧构筑副本上测试新树转换。
2. 确认候选确实包含目标赛季的数据；`2.67.2` 等应用显示版本不是游戏版本。对比中英文同一构筑的结果；跨引擎版本的数值变化另看上游改动。为自动化复核，可用仓库 Dockerfile 固定版本的 LuaJIT 和 `lua-utf8`，在候选 `Contents/Resources/src` 的临时副本运行 `smoke.lua`，可附旧 XML 副本的绝对路径。它会检查九个视图、字形、回退和两种语言的计算及导出一致性，不能替代原生 GUI 和永恒珠宝数据检查。
3. 验收后，使用**同一完整提交**重打正式候选：沿用上一步命令，加入 `--local-commit <候选显示的完整提交>`（该提交须已抓取到本地源码仓库，可先运行 `git fetch https://github.com/PathOfBuildingCommunity/PathOfBuilding.git <完整提交>`）、`--production`，并另选一个不存在的输出路径。也可指定同一个不变的正式标签并核对打印的完整提交。正式候选继续使用当前正式目录；验证阶段请勿启动它。脚本本身不会替换应用。
4. 退出正式 PoB，先备份旧 `.app` 和正式 `User`，再用 Finder 替换 `.app`。重开，确认构筑数量、语言和新天赋；不要直接覆盖旧构筑。回退时退出并换回旧 `.app`，保留 `User`。如果新包曾保存配置或将构筑转成新版，按需从备份恢复对应文件。

`package.py` 保留固定 3dbca4463 底包的本地重建入口，可加 `--preview` 验证工作区里尚未提交的汉化。日常更新走 `update.py`，它从 Git 导出源码，构建前请先保存汉化改动到本地提交。
