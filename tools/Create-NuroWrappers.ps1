#!/usr/bin/env pwsh
<#
.SYNOPSIS
  limbo/*.ps1 を nuro 規格（NuroUsage_*/NuroCmd_*）へ自動整形して出力する。

.DESCRIPTION
  - script-level param を持つファイルは NuroCmd_* 内にロジックを直接埋め込み、元ファイルを呼び出さない。
  - ファイル内のトップレベル関数は、その本体を NuroCmd_* に移植して limbo/*.ps1 への依存を排除する。
  - 生成物は NuroUsage_* / NuroCmd_* の二関数を含む単一 ps1 として出力される。

.EXAMPLE
  .\tools\Create-NuroWrappers.ps1 -SourceDir .\limbo -OutDir .\cmds_staging

.NOTES
  - Usage テキストは AST から param 名を拾って最低限の案内文を自動生成する（必要に応じて手修正してください）。
  - コマンド名は PascalCase（英数字）化して Nuro 規格の接頭辞を付与する。
#>

[CmdletBinding()]
param(
  [Parameter()]
  [string]$SourceDir = './limbo',

  [Parameter()]
  [string]$OutDir = './cmds_staging'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName 'System.Management.Automation'

function Resolve-Pascal {
  param([string]$Name)
  $parts = ($Name -split '[^A-Za-z0-9]+') | Where-Object { $_ -ne '' }
  if (-not $parts) { return 'Cmd' }
  $joined = ($parts | ForEach-Object { $_.Substring(0,1).ToUpper() + $_.Substring(1) }) -join ''
  if ($joined -match '^[0-9]') { $joined = "Cmd$joined" }
  return $joined
}

function Get-Ast {
  param([string]$Text)
  $tokens = $null; $errors = $null
  return [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors), $errors
}

function Build-UsageText {
  param(
    [string]$DisplayName,
    [System.Collections.IEnumerable]$Params
  )
  $paramList =
    if ($Params -and $Params.Count -gt 0) {
      ($Params | ForEach-Object {
        $n = $_.Name.VariablePath.UserPath
        if ($_.Attributes | Where-Object { $_.TypeName.Name -eq 'switch' }) {
          "[-$n]"
        } else {
          "<$n>"
        }
      }) -join ' '
    } else { '' }

@"
Usage:
  $DisplayName $paramList

Notes:
  - 引数はそのまま透過されます（@args）。
"@
}

function Render-ParamBlockLines {
  param([System.Collections.IEnumerable]$Params)
  $paramArray = @($Params)
  if (-not $paramArray -or $paramArray.Count -eq 0) { return @() }

  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add('param(')

  for ($i = 0; $i -lt $paramArray.Count; $i++) {
    $param = $paramArray[$i]
    $textLines = $param.Extent.Text -split "`r?`n"
    $trimmed = @()
    foreach ($line in $textLines) {
      $trimmed += $line.TrimEnd()
    }

    $lastIdx = $trimmed.Length - 1
    while ($lastIdx -ge 0 -and [string]::IsNullOrWhiteSpace($trimmed[$lastIdx])) {
      $lastIdx--
    }

    if ($lastIdx -ge 0 -and $i -lt $paramArray.Count - 1) {
      $needsComma = -not $trimmed[$lastIdx].TrimEnd().EndsWith(',')
      if ($needsComma) {
        $trimmed[$lastIdx] = $trimmed[$lastIdx] + ','
      }
    }

    foreach ($line in $trimmed) {
      $lines.Add(('    ' + $line))
    }
  }

  $lines.Add(')')
  return $lines.ToArray()
}

function Trim-BlankLines {
  param([string[]]$Lines)
  if (-not $Lines) { return @() }

  $start = 0
  while ($start -lt $Lines.Length -and [string]::IsNullOrWhiteSpace($Lines[$start])) { $start++ }

  $end = $Lines.Length - 1
  while ($end -ge $start -and [string]::IsNullOrWhiteSpace($Lines[$end])) { $end-- }

  if ($end -lt $start) { return @() }

  return $Lines[$start..$end]
}

function Indent-Lines {
  param(
    [string[]]$Lines,
    [string]$Indent = '  '
  )

  if (-not $Lines) { return @() }

  return $Lines | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) {
      ''
    } else {
      $Indent + $_
    }
  }
}

function Get-TopLevelFunctions {
  param($Ast)
  if (-not $Ast.EndBlock) { return @() }
  return $Ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] }
}

function Write-CommandFile {
  param(
    [string]$CmdName,
    [string]$DisplayName,
    [string]$WrapperFileName,
    [string[]]$CmdBodyLines,
    [System.Collections.IEnumerable]$UsageParams,
    [string]$SourcePath
  )

  $usageFn = "NuroUsage_$CmdName"
  $cmdFn   = "NuroCmd_$CmdName"
  $usage   = Build-UsageText -DisplayName $DisplayName -Params $UsageParams

  $usageLines = [System.Collections.Generic.List[string]]::new()
  $usageLines.AddRange($usage -split "`r?`n")
  while ($usageLines.Count -gt 0 -and [string]::IsNullOrEmpty($usageLines[$usageLines.Count - 1])) {
    $usageLines.RemoveAt($usageLines.Count - 1)
  }

  $builder = [System.Text.StringBuilder]::new()
  [void]$builder.AppendLine('# Auto-generated nuro command (inline original content)')
  [void]$builder.AppendLine("# Source: $SourcePath")
  [void]$builder.AppendLine('')

  [void]$builder.AppendLine("function $usageFn {")
  [void]$builder.AppendLine('  @"')
  foreach ($line in $usageLines) {
    [void]$builder.AppendLine($line)
  }
  [void]$builder.AppendLine('  "@')
  [void]$builder.AppendLine('}')
  [void]$builder.AppendLine('')

  [void]$builder.AppendLine("function $cmdFn {")
  foreach ($line in (Indent-Lines -Lines $CmdBodyLines -Indent '  ')) {
    [void]$builder.AppendLine($line)
  }
  [void]$builder.AppendLine('}')

  $content = $builder.ToString().TrimEnd("`r", "`n") + "`r`n"
  $outPath = Join-Path $OutDir $WrapperFileName
  Set-Content -LiteralPath $outPath -Encoding UTF8 $content
  Write-Host "Generated: $outPath" -ForegroundColor Green
}

$src = Resolve-Path $SourceDir
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files = Get-ChildItem -LiteralPath $src -Filter '*.ps1' -File -Recurse
if (-not $files) {
  Write-Warning "No .ps1 under $src"
  return
}

foreach ($file in $files) {
  $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
  $parse = Get-Ast -Text $text
  $ast   = $parse[0]; $errs = $parse[1]

  if ($errs -and $errs.Count -gt 0) {
    Write-Warning "Parse warning(s) in $($file.Name): $($errs | ForEach-Object Message -join '; ')"
  }

  $rootParam = $ast.ParamBlock
  $fnAsts    = @(Get-TopLevelFunctions -Ast $ast)

  if ($rootParam -and $fnAsts.Count -eq 0) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $cmdName  = Resolve-Pascal $baseName
    $wrapper  = "$cmdName.ps1"

    $bodyStart = $rootParam.Extent.EndOffset
    $bodyText = if ($bodyStart -lt $text.Length) { $text.Substring($bodyStart) } else { '' }
    $bodyLines = Trim-BlankLines -Lines ($bodyText -split "`r?`n")

    $cmdLines = [System.Collections.Generic.List[string]]::new()
    $cmdLines.Add('[CmdletBinding()]')

    $paramLines = Render-ParamBlockLines -Params $rootParam.Parameters
    if ($paramLines.Count -gt 0) {
      foreach ($line in $paramLines) { $cmdLines.Add($line) }
    } else {
      $cmdLines.Add('param()')
    }

    if ($bodyLines.Count -gt 0) {
      $cmdLines.Add('')
      foreach ($line in $bodyLines) { $cmdLines.Add($line) }
    }

    Write-CommandFile -CmdName $cmdName -DisplayName $baseName -WrapperFileName $wrapper -CmdBodyLines $cmdLines.ToArray() -UsageParams $rootParam.Parameters -SourcePath $file.FullName
  }

  if ($fnAsts.Count -gt 0) {
    foreach ($fn in $fnAsts) {
      $origFnName = $fn.Name
      $cmdName    = Resolve-Pascal $origFnName
      $wrapper    = "$cmdName.ps1"

      $paramAsts = @()
      if ($fn.Parameters -and $fn.Parameters.Count -gt 0) {
        $paramAsts = $fn.Parameters
      } elseif ($fn.Body.ParamBlock) {
        $paramAsts = $fn.Body.ParamBlock.Parameters
      }

      $bodyStart = $fn.Body.Extent.StartOffset
      $bodyEnd   = $fn.Body.Extent.EndOffset
      $bodyText  = $text.Substring($bodyStart, $bodyEnd - $bodyStart)

      if ($bodyText.StartsWith('{')) { $bodyText = $bodyText.Substring(1) }
      if ($bodyText.EndsWith('}')) { $bodyText = $bodyText.Substring(0, $bodyText.Length - 1) }

      $bodyLines = Trim-BlankLines -Lines ($bodyText -split "`r?`n")

      $cmdLines = [System.Collections.Generic.List[string]]::new()

      if ($fn.Body.ParamBlock) {
        foreach ($line in $bodyLines) { $cmdLines.Add($line) }
      } else {
        if ($paramAsts.Count -gt 0) {
          $cmdLines.Add('[CmdletBinding()]')
          foreach ($line in (Render-ParamBlockLines -Params $paramAsts)) { $cmdLines.Add($line) }
          if ($bodyLines.Count -gt 0) { $cmdLines.Add('') }
        }
        foreach ($line in $bodyLines) { $cmdLines.Add($line) }
      }

      Write-CommandFile -CmdName $cmdName -DisplayName $origFnName -WrapperFileName $wrapper -CmdBodyLines $cmdLines.ToArray() -UsageParams $paramAsts -SourcePath $file.FullName
    }
  }

  if (-not $rootParam -and $fnAsts.Count -eq 0) {
    Write-Warning "No root param or top-level functions found in $($file.Name); skipped."
  }
}

Write-Host "Done. Generated wrappers under: $OutDir" -ForegroundColor Cyan
