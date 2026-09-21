# ticai

中国体育彩票竞彩足球赛前分析 Agent Skill。它要求先核对当期官方赛程、玩法、固定奖金和单关资格，再结合赔率、阵容、伤停、天气等信息分析指定场次或当日赛程。

## 安装

复制整个 `ticai` 文件夹，保留 `SKILL.md` 和 `references/`：

- Codex：`~/.codex/skills/ticai/`（或 `~/.agents/skills/ticai/`）
- Claude Code：`~/.claude/skills/ticai/`
- Gemini CLI：`~/.gemini/skills/ticai/`（或 `~/.agents/skills/ticai/`）
- Cursor：`~/.cursor/skills/ticai/`（也支持 `~/.agents/skills/ticai/`）

`agents/openai.yaml` 是 Codex 的界面配置；其他产品可忽略。目标 Agent 需要具备联网查询能力，才能核验实时赛程、奖金与赛前信息。预测只供分析参考，不保证收益。
