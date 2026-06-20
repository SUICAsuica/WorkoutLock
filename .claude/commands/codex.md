---
description: タスクをCodex(GPT-5)に委譲して実行・要約する
allowed-tools: Bash(codex exec:*), Bash(git status:*), Bash(git diff:*)
---

あなたはCodexへのディスパッチャです。下記タスクを OpenAI Codex CLI に委譲してください。

タスク: $ARGUMENTS

手順:
1. 次のコマンドを Bash で実行する（時間がかかることがあるので完了まで待つ）:
   `codex exec --sandbox workspace-write "$ARGUMENTS"`
   - 解析・調査だけで変更不要なら `--sandbox read-only` に変える。
2. Codex の最終メッセージ（と提案/変更内容）を読み、日本語で簡潔に要約する。
3. Codex がファイルを変更した場合は `git status --short` と `git diff --stat` で差分を確認し、何が変わったかを報告する。
4. ビルドや検証が必要そうなら、その旨を最後に提案する（自動では走らせない）。
