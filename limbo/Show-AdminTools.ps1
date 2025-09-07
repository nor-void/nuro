param(
    [switch]$ListOnly
)

# 文字化け対策: 出力を UTF-8 に設定（失敗しても無視）
try {
    if ($IsWindows) { chcp 65001 | Out-Null }
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($true)
    $OutputEncoding = [Console]::OutputEncoding
} catch {}

function Show-AdminTools {
    [CmdletBinding()]
    param(
        [switch]$ListOnly  # 一覧のみ（非インタラクティブ）
    )

    # 1) 管理ツール一覧
    $items = @(
        # === .msc ===
        @{ Name = "certmgr.msc   – 現在のユーザー証明書の管理 (CurrentUser)"; Cmd = "certmgr.msc" }
        @{ Name = "certlm.msc    – ローカル コンピューター証明書の管理 (LocalMachine)"; Cmd = "certlm.msc" }
        @{ Name = "secpol.msc    – ローカル セキュリティ ポリシー";           Cmd = "secpol.msc" }
        @{ Name = "gpedit.msc    – ローカル グループ ポリシー エディター";   Cmd = "gpedit.msc" }
        @{ Name = "compmgmt.msc  – コンピューターの管理";                    Cmd = "compmgmt.msc" }
        @{ Name = "devmgmt.msc   – デバイス マネージャー";                  Cmd = "devmgmt.msc" }
        @{ Name = "diskmgmt.msc  – ディスクの管理";                        Cmd = "diskmgmt.msc" }
        @{ Name = "eventvwr.msc  – イベント ビューアー";                    Cmd = "eventvwr.msc" }
        @{ Name = "perfmon.msc   – パフォーマンス モニター";                Cmd = "perfmon.msc" }
        @{ Name = "wf.msc        – Windows Defender ファイアウォール (詳細設定)"; Cmd = "wf.msc" }
        @{ Name = "services.msc  – サービス";                              Cmd = "services.msc" }
        @{ Name = "lusrmgr.msc   – ローカル ユーザーとグループ";            Cmd = "lusrmgr.msc" }
        @{ Name = "taskschd.msc  – タスク スケジューラ";                    Cmd = "taskschd.msc" }
        @{ Name = "printmanagement.msc – プリント管理";                     Cmd = "printmanagement.msc" }
        @{ Name = "fsmgmt.msc    – 共有フォルダー";                        Cmd = "fsmgmt.msc" }
        @{ Name = "rsop.msc      – 適用されたポリシーの結果セット (RSoP)";   Cmd = "rsop.msc" }

        # === .cpl / その他 ===
        @{ Name = "appwiz.cpl        – プログラムと機能";                   Cmd = "appwiz.cpl" }
        @{ Name = "appwiz.cpl ,2     – インストールされた更新プログラム";   Cmd = "appwiz.cpl ,2" }
        @{ Name = "ncpa.cpl          – ネットワーク接続";                   Cmd = "ncpa.cpl" }
        @{ Name = "firewall.cpl      – Windows ファイアウォールの設定";     Cmd = "firewall.cpl" }
        @{ Name = "inetcpl.cpl       – インターネット オプション";          Cmd = "inetcpl.cpl" }
        @{ Name = "main.cpl          – マウスのプロパティ";                 Cmd = "main.cpl" }
        @{ Name = "desk.cpl          – ディスプレイ設定";                   Cmd = "desk.cpl" }
        @{ Name = "timedate.cpl      – 日付と時刻";                         Cmd = "timedate.cpl" }
        @{ Name = "mmsys.cpl         – サウンド";                           Cmd = "mmsys.cpl" }
        @{ Name = "powercfg.cpl      – 電源オプション";                     Cmd = "powercfg.cpl" }
        @{ Name = "intl.cpl          – 日付、時刻、地域";                   Cmd = "intl.cpl" }
        @{ Name = "sysdm.cpl         – システムのプロパティ";               Cmd = "sysdm.cpl" }
        @{ Name = "nusrmgr.cpl       – ユーザー アカウント (レガシ UI)";     Cmd = "nusrmgr.cpl" }
    )

    if ($ListOnly) {
        Write-Host "=== 管理ツール一覧 (.msc / .cpl) ===" -ForegroundColor Cyan
        $items.Name | ForEach-Object { $_ }
        return
    }

    # 2) シンプルなインタラクティブ UI
    $idx = 0
    $topMsg = "↑/↓で選択、Enterで起動、Escで終了"
    $esc = [char]27

    # Check ANSI support (fallback to colors if not supported)
    $supportsAnsi = $Host.UI.RawUI -and ($Host.UI.SupportsVirtualTerminal -or $env:WT_SESSION -or $env:ConEmuANSI -or $Host.Name -match "VSCode")

    function Draw {
        Clear-Host
        Write-Host "=== Admin Tools (.msc / .cpl) ===" -ForegroundColor Cyan
        Write-Host $topMsg -ForegroundColor DarkGray
        for ($i=0; $i -lt $items.Count; $i++) {
            $line = $items[$i].Name
            if ($i -eq $idx) {
                if ($supportsAnsi) {
                    Write-Host "$esc[7m> $line$esc[0m"
                } else {
                    Write-Host ("> " + $line) -ForegroundColor Black -BackgroundColor White
                }
            } else {
                Write-Host "  $line"
            }
        }
    }

    Draw

    while ($true) {
        $key = [System.Console]::ReadKey($true)

        switch ($key.Key) {
            'UpArrow'   { if ($idx -gt 0) { $idx-- }; Draw }
            'DownArrow' { if ($idx -lt $items.Count-1) { $idx++ }; Draw }
            'Home'      { $idx = 0; Draw }
            'End'       { $idx = $items.Count-1; Draw }
            'Enter' {
                $cmd = $items[$idx].Cmd
                Write-Host ""
                Write-Host "起動: $cmd" -ForegroundColor Green
                Start-Process $cmd
                return
            }
            'Escape' {
                Write-Host ""
                Write-Host "キャンセルしました。" -ForegroundColor Yellow
                return
            }
            default { }
        }
    }
}

# Auto-run when executed directly (skip when dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    Show-AdminTools -ListOnly:$ListOnly
}
