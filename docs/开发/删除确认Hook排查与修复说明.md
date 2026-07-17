# 删除确认 Hook 排查与修复说明

## 背景

`delete-confirmation-hook@personal` 的目标是在执行真实删除命令前要求用户确认，避免 Agent 误删文件、目录或 Git 未追踪内容。

本次在修改登录测试时，普通的文本替换与 `apply_patch` 被 `PreToolUse` 拒绝，提示“无法验证命令是否包含删除操作，请先征得用户明确同意”。这些操作没有执行 `rm`、`Remove-Item`、`del`、`rmdir` 或 `git clean`。

## 已确认的配置

用户级 `~/.codex/config.toml` 启用了：

```toml
[plugins."delete-confirmation-hook@personal"]
enabled = true
```

插件的 `hooks/hooks.json` 对所有 `PreToolUse` 事件执行以下脚本：

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": ".*",
      "hooks": [{
        "type": "command",
        "command": "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"~/.codex/hooks/confirm-delete.ps1\""
      }]
    }]
  }
}
```

`confirm-delete.ps1` 会从 `tool_input` 中读取 `command`、`cmd` 或 `script` 字段，再识别以下删除行为：

- `rm`、`Remove-Item`、`ri`、`del`、`erase`、`rmdir`、`rd`
- `find ... -delete`
- 通过 `xargs` 或 `find -exec` 调用删除命令
- `git clean`
- 包装在 `cmd /c`、`powershell -Command`、`pwsh -Command` 中的上述命令

这部分规则符合“只拦截危险删除命令”的目标，不应因为普通文本编辑而放宽。

## 问题分析

Hook 以如下方式读取输入：

```powershell
$rawInput = [Console]::In.ReadToEnd()
$hookInput = $rawInput | ConvertFrom-Json
```

随后在任意异常时默认返回 `block`：

```powershell
catch {
    $output = [ordered]@{
        decision = 'block'
        reason = '无法验证命令是否包含删除操作，请先征得用户明确同意。'
    }
}
```

因此，除了真实删除命令，任何无法被 `ConvertFrom-Json` 解析的工具输入都会被拒绝。`apply_patch` 使用自由格式补丁内容，或命令文本在封装过程中包含未正确转义的反斜杠时，都可能进入该异常分支。

本次现象的证据是：包含 `\d` 的补丁或命令文本被拒绝，而不含该类反斜杠的简单文本替换可以执行。需要在目标 Codex 版本中保留 Hook 的原始输入，确认具体是哪一种输入格式导致 JSON 解析失败。

## 修复原则

1. JSON 解析失败不等于删除操作。
2. 只要能提取到命令文本，就继续沿用现有删除命令匹配规则。
3. 无法提取命令文本的非命令型工具输入应允许通过，避免阻断 `apply_patch`、结构化编辑和其他安全操作。
4. 对真正的 shell 命令，解析失败仍应保守处理或记录审计日志，不能无条件放行。

## 推荐实现

将输入解析改为“尽力解析”，并把命令提取与删除检测解耦：

```powershell
$rawInput = [Console]::In.ReadToEnd()
$hookInput = $null

try {
    $hookInput = $rawInput | ConvertFrom-Json -ErrorAction Stop
} catch {
    # 非 JSON 输入通常来自补丁等非命令型工具。
}

$command = Get-CommandText -ToolInput $hookInput

if ($null -eq $command) {
    # 没有 shell 命令可执行，不应视为删除操作。
    @{ decision = $null; reason = $null } | ConvertTo-Json -Compress
    exit 0
}

$isDelete = Test-DeleteCommand -Command $command
if ($isDelete) {
    $confirmation = Get-DeleteConfirmationResponse
    if ($confirmation -ne 'Yes') {
        @{ decision = 'block'; reason = '用户拒绝删除操作。' } | ConvertTo-Json -Compress
        exit 0
    }
}

@{ decision = $null; reason = $null } | ConvertTo-Json -Compress
```

若目标环境会把 shell 命令以自由文本传入，建议额外加入严格的命令起始判断：只有文本以 `rm`、`Remove-Item`、`del`、`rmdir`、`git clean` 或支持的 shell 包装器开头时，才将其视为待检测命令。不要在自由文本中做宽泛子串匹配。

## 验证用例

修改后至少执行以下用例：

| 输入类型 | 示例 | 预期 |
| --- | --- | --- |
| 补丁文本 | 含 `\d` 的 TypeScript 正则替换 | 允许 |
| 普通命令 | `npm run compile` | 允许 |
| 直接删除 | `rm file.txt` | 弹出确认；拒绝时阻断 |
| PowerShell 删除 | `Remove-Item file.txt` | 弹出确认；拒绝时阻断 |
| 包装删除 | `cmd /c del file.txt` | 弹出确认；拒绝时阻断 |
| Git 清理 | `git clean -fd` | 弹出确认；拒绝时阻断 |
| 含删除字样的普通文本 | 文档中提及 `rm` | 允许 |

可以通过 `CODEX_DELETE_HOOK_TEST_RESPONSE=Yes` 或 `No` 模拟确认结果；测试必须使用临时目录和虚拟输入，不实际删除项目文件。

## 迁移步骤

1. 复制 `confirm-delete.ps1` 与插件的 `hooks.json` 到目标 Codex 配置目录。
2. 在目标 `config.toml` 启用插件，并确认 `PreToolUse` 的命令路径正确。
3. 先运行上述验证用例，特别检查补丁文本、含反斜杠的正则和 PowerShell 包装命令。
4. 保留审计日志，记录 `tool_name`、判定结果和时间；日志中不要记录完整命令，以免泄露参数或敏感数据。
5. 插件升级或 Codex 版本升级后重新回归，因为工具输入格式可能变化。

## 结论

应修复输入兼容性和异常处理，而不是降低删除命令的匹配强度。目标行为是：真实删除命令始终需要明确确认，普通补丁、代码编辑和包含删除关键词的文档文本不应被拦截。
