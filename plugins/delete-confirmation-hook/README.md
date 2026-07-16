# Delete Confirmation Hook

A Windows-focused Codex plugin that recognizes common delete commands and asks for confirmation with a Yes/No dialog.

## Included commands

- `rm`, `Remove-Item`, `del`, `erase`, `rmdir`, and `rd`
- `git clean`
- `find -delete`, `find -exec rm`, and `xargs rm`

## Install from a cloned repository

```powershell
codex plugin marketplace add <repository-root>
codex plugin add delete-confirmation-hook@delete-confirmation-hook
```

Restart Codex after installation before starting a new task.

## Requirements

- Windows
- PowerShell with `System.Windows.Forms`
- A Codex host that runs `PreToolUse` command hooks

## Security behavior

Choosing No, closing the dialog, or failing to create a dialog returns a blocking decision.

## Development test hook response

Set `CODEX_DELETE_HOOK_TEST_RESPONSE` to `Yes` or `No` to test the hook without opening a dialog.
