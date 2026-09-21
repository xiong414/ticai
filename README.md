# ticai

中国体育彩票竞彩足球赛前分析 Agent Skill。它要求先核对当期官方赛程、玩法、固定奖金和单关资格，再结合赔率、阵容、伤停、天气等信息分析指定场次或当日赛程。

## 安装

复制整个 `ticai` 文件夹，保留 `SKILL.md` 和 `references/`：

- Codex：`~/.codex/skills/ticai/`（或 `~/.agents/skills/ticai/`）
- Claude Code：`~/.claude/skills/ticai/`
- Gemini CLI：`~/.gemini/skills/ticai/`（或 `~/.agents/skills/ticai/`）
- Cursor：`~/.cursor/skills/ticai/`（也支持 `~/.agents/skills/ticai/`）

`agents/openai.yaml` 是 Codex 的界面配置；其他产品可忽略。目标 Agent 需要具备联网查询能力，才能核验实时赛程、奖金与赛前信息。预测只供分析参考，不保证收益。

## 更新

在本地仓库执行 `git pull`，然后把 `ticai` 文件夹重新复制到上面对应的技能目录（覆盖 `SKILL.md` 和 `references/`）。

## 限制与免责

- 仅覆盖中国体育彩票竞彩足球；大乐透、排列 3、双色球等其他彩票玩法不适用。
- 只做赛前分析，不代用户下注，不承诺收益。请理性购彩、量力而行，未成年人不得购彩。
- 技能本身不含数据，必须由宿主 Agent 联网核验当期赛程、奖金与单关资格。无法核实的项目会标注“未核实”，不会用历史同编号比赛或旧奖金顶替。
- 官方页面多为 JS 渲染，抓取工具需支持渲染才能取到奖金与赛程内容。
