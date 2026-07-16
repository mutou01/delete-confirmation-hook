$ErrorActionPreference = 'Stop'

function ConvertFrom-Base64Utf8 {
    param([Parameter(Mandatory)][string]$Value)

    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

function Get-CommandText {
    param($ToolInput)

    if ($null -eq $ToolInput) {
        return $null
    }

    foreach ($name in @('command', 'cmd', 'script')) {
        $property = $ToolInput.PSObject.Properties[$name]
        if ($null -ne $property -and $property.Value -is [string]) {
            return $property.Value
        }
    }

    return $null
}

function Test-DeleteCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [int]$Depth = 0
    )

    if ($Depth -gt 2) {
        return $false
    }

    $directDelete = '(?i)(?:^|(?:&&|\|\||[;|&])\s*)(?:(?:sudo|doas|command)\s+)*(?:rm|remove-item|ri|del|erase|rmdir|rd)\b'
    if ($Command -match $directDelete) {
        return $true
    }

    if ($Command -match '(?i)\b(?:find\s+.+?\s-delete\b|(?:xargs|find\s+.+?-exec)\s+(?:rm|remove-item|del|rmdir)\b|git\s+clean\b)') {
        return $true
    }

    $shellPayload = [regex]::Match($Command, '(?is)^\s*(?:cmd(?:\.exe)?\s+/c|powershell(?:\.exe)?\s+(?:-command|-c)|pwsh(?:\.exe)?\s+(?:-command|-c))\s+(.+?)\s*$')
    if ($shellPayload.Success) {
        $payload = $shellPayload.Groups[1].Value.Trim()
        if ($payload.Length -ge 2 -and (($payload[0] -eq '"' -and $payload[$payload.Length - 1] -eq '"') -or ($payload[0] -eq "'" -and $payload[$payload.Length - 1] -eq "'"))) {
            $payload = $payload.Substring(1, $payload.Length - 2)
        }

        return Test-DeleteCommand -Command $payload -Depth ($Depth + 1)
    }

    return $false
}

function Get-DeleteConfirmationResponse {
    $testResponse = $env:CODEX_DELETE_HOOK_TEST_RESPONSE
    if ($testResponse -in @('Yes', 'No')) {
        return $testResponse
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms
        $message = ConvertFrom-Base64Utf8 '5qOA5rWL5Yiw5Yig6Zmk5ZG95Luk44CC5piv5ZCm5YWB6K645omn6KGM77yf'
        $caption = ConvertFrom-Base64Utf8 'Q29kZXgg5Yig6Zmk56Gu6K6k'
        $result = [System.Windows.Forms.MessageBox]::Show(
            $message,
            $caption,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2,
            [System.Windows.Forms.MessageBoxOptions]::DefaultDesktopOnly
        )

        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            return 'Yes'
        }
    } catch {
        # A missing desktop session must fail closed.
    }

    return 'No'
}

try {
    $hookInput = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $command = Get-CommandText -ToolInput $hookInput.tool_input
    $isDelete = $command -is [string] -and (Test-DeleteCommand -Command $command)
    $confirmation = if ($isDelete) { Get-DeleteConfirmationResponse } else { $null }
    $isApproved = -not $isDelete -or $confirmation -eq 'Yes'
    $permissionDecision = if ($isApproved) { 'allow' } else { 'deny' }
    $topLevelDecision = if ($isApproved) { $null } else { 'block' }
    $reason = if ($isApproved) { $null } else { ConvertFrom-Base64Utf8 '55So5oi35ouS57ud5Yig6Zmk5pON5L2c44CC' }

    [ordered]@{
        decision = $topLevelDecision
        reason = $reason
        hookSpecificOutput = [ordered]@{
            hookEventName = 'PreToolUse'
            permissionDecision = $permissionDecision
            permissionDecisionReason = $reason
        }
    } | ConvertTo-Json -Compress
} catch {
    [ordered]@{
        decision = 'block'
        reason = ConvertFrom-Base64Utf8 '5peg5rOV6aqM6K+B5ZG95Luk5piv5ZCm5YyF5ZCr5Yig6Zmk5pON5L2c77yM6K+35YWI5b6B5b6X55So5oi35piO56Gu5ZCM5oSP44CC'
        hookSpecificOutput = [ordered]@{
            hookEventName = 'PreToolUse'
            permissionDecision = 'deny'
        }
    } | ConvertTo-Json -Compress
}
