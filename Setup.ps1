param(
    [ValidateSet('Install','Uninstall')][string]$Action = 'Install',
    [string]$GameDir
)

$ErrorActionPreference = 'Stop'
$packageId = 'codex.just-volleyball.zh-TW.v1'
$modName = 'jv_zh_tw'
$autoloadKey = 'JVTraditionalChinese'
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)

function Read-Config([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ Text=''; Encoding=$utf8; Prefix=[byte[]]@(); Exists=$false }
    }
    $raw = [IO.File]::ReadAllBytes($Path)
    $skip = 0
    $encoding = $utf8
    if ($raw.Length -ge 3 -and $raw[0] -eq 239 -and $raw[1] -eq 187 -and $raw[2] -eq 191) {
        $skip = 3
    } elseif ($raw.Length -ge 2 -and $raw[0] -eq 255 -and $raw[1] -eq 254) {
        $skip = 2; $encoding = New-Object System.Text.UnicodeEncoding($false, $false, $true)
    } elseif ($raw.Length -ge 2 -and $raw[0] -eq 254 -and $raw[1] -eq 255) {
        $skip = 2; $encoding = New-Object System.Text.UnicodeEncoding($true, $false, $true)
    }
    $prefix = [byte[]]@()
    if ($skip -gt 0) { $prefix = [byte[]]$raw[0..($skip-1)] }
    return @{ Text=$encoding.GetString($raw,$skip,$raw.Length-$skip); Encoding=$encoding; Prefix=$prefix; Exists=$true }
}

function Write-Config([string]$Path, $Config, [string]$Value) {
    [byte[]]$body = $Config.Encoding.GetBytes($Value)
    [byte[]]$bytes = @($Config.Prefix) + @($body)
    $temp = $Path + '.jv-zhTW-' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllBytes($temp, $bytes)
        Move-Item -LiteralPath $temp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
}

function Autoload-Body([string]$Text) {
    $section = [regex]::Match($Text, '(?m)^[ \t]*\[autoload\][ \t]*(?:[;#][^\r\n]*)?(?:\r?\n|$)')
    if (-not $section.Success) { return @{ Start=0; Length=0; Text='' } }
    $start = $section.Index+$section.Length
    $rest = $Text.Substring($start)
    $next = [regex]::Match($rest, '(?m)^[ \t]*\[[^\]\r\n]+\]')
    $length = $rest.Length
    if ($next.Success) { $length=$next.Index }
    return @{ Start=$start; Length=$length; Text=$rest.Substring(0,$length) }
}

function Remove-AutoloadEntry([string]$Text) {
    $body = Autoload-Body $Text
    $newBody = [regex]::Replace($body.Text, $keyPattern, '')
    return $Text.Substring(0,$body.Start)+$newBody+$Text.Substring($body.Start+$body.Length)
}

function Assert-ChildPath([string]$Path, [string]$Parent) {
    $full = [IO.Path]::GetFullPath($Path)
    $base = [IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to change a directory outside the game folder: $full"
    }
    return $full
}

function Remove-TaskDirectory([string]$Path, [string]$Parent) {
    $verified = Assert-ChildPath $Path $Parent
    if (Test-Path -LiteralPath $verified) {
        $item = Get-Item -LiteralPath $verified -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing to remove a linked directory: $verified"
        }
        Remove-Item -LiteralPath $verified -Recurse -Force
    }
}

function Find-Game {
    $steamRoots = New-Object 'System.Collections.Generic.List[string]'
    foreach ($root in @("${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam", 'D:\SteamLibrary', 'E:\SteamLibrary')) {
        if ($root -and (Test-Path -LiteralPath $root)) { $steamRoots.Add($root) }
    }
    foreach ($reg in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $props = Get-ItemProperty -LiteralPath $reg -ErrorAction SilentlyContinue
        foreach ($propertyName in @('SteamPath','InstallPath')) {
            if ($props -and $props.PSObject.Properties[$propertyName]) {
                $value = $props.$propertyName
                if ($value -and (Test-Path -LiteralPath $value)) { $steamRoots.Add($value) }
            }
        }
    }
    $libraries = New-Object 'System.Collections.Generic.List[string]'
    foreach ($root in @($steamRoots | Select-Object -Unique)) {
        $libraries.Add($root)
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            $vdfText = [IO.File]::ReadAllText($vdf)
            foreach ($match in [regex]::Matches($vdfText, '"path"\s+"([^"\r\n]+)"')) {
                $libraries.Add($match.Groups[1].Value.Replace('\\','\'))
            }
        }
    }
    foreach ($root in @($libraries | Select-Object -Unique)) {
        $manifest = Join-Path $root 'steamapps\appmanifest_5037200.acf'
        if (Test-Path -LiteralPath $manifest) {
            $text = [IO.File]::ReadAllText($manifest)
            $match = [regex]::Match($text, '"installdir"\s+"([^"\r\n]+)"')
            if ($match.Success) {
                $candidate = Join-Path (Join-Path $root 'steamapps\common') $match.Groups[1].Value
                if (Test-Path -LiteralPath (Join-Path $candidate 'volleyball.exe')) { return $candidate }
            }
        }
    }
    throw '找不到遊戲。請使用：powershell -ExecutionPolicy Bypass -File .\Setup.ps1 -GameDir "你的遊戲目錄"'
}

try {
    if (-not $GameDir) { $GameDir = Find-Game }
    $GameDir = [IO.Path]::GetFullPath($GameDir).TrimEnd('\')
    if (-not (Test-Path -LiteralPath (Join-Path $GameDir 'volleyball.exe')) -or
        -not (Test-Path -LiteralPath (Join-Path $GameDir 'volleyball.pck'))) {
        throw '選定目錄必須同時包含 volleyball.exe 與 volleyball.pck。'
    }
    if (Get-Process -Name volleyball -ErrorAction SilentlyContinue) {
        throw '請先完全關閉 just volleyball，再執行安裝或移除。'
    }
    $target = Assert-ChildPath (Join-Path $GameDir $modName) $GameDir
    if ((Test-Path -LiteralPath $target) -and ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'jv_zh_tw 是連結目錄，已停止以避免修改其他位置。'
    }
    $cfgPath = Join-Path $GameDir 'override.cfg'
    $cfg = Read-Config $cfgPath
    $oldRaw = $null
    if ($cfg.Exists) { $oldRaw = [IO.File]::ReadAllBytes($cfgPath) }
    $marker = Join-Path $target 'package-id.txt'
    $owned = (Test-Path -LiteralPath $marker) -and ([IO.File]::ReadAllText($marker).Trim() -eq $packageId)
    $keyPattern = '(?m)^[ \t]*JVTraditionalChinese[ \t]*=[^\r\n]*(?:\r?\n|$)'
    $autoloadBody = Autoload-Body $cfg.Text
    $keyMatches = [regex]::Matches($autoloadBody.Text, $keyPattern)
    $infoPath = Join-Path $target 'install-info.json'

    if ($Action -eq 'Uninstall') {
        if (-not $owned -and $keyMatches.Count -gt 0) {
            throw '找到同名載入設定，但無法確認是本模組；已停止，避免改到其他模組。'
        }
        if (-not $owned) { Write-Host '本模組尚未安裝。'; exit 0 }
        $info = $null
        if (Test-Path -LiteralPath $infoPath) { $info = [IO.File]::ReadAllText($infoPath) | ConvertFrom-Json }
        $newText = Remove-AutoloadEntry $cfg.Text
        if ($info -and $info.AddedSectionBlock -and $cfg.Text.Contains([string]$info.AddedSectionBlock)) {
            # Remove the whole section only when our exact, otherwise empty insertion still exists.
            $newText = $cfg.Text.Replace([string]$info.AddedSectionBlock, '')
        }
        if ($info -and $info.HeaderWithoutNewline) {
            foreach ($ending in @("`r`n", "`n")) {
                if ($newText.EndsWith(([string]$info.HeaderWithoutNewline)+$ending)) {
                    $newText = $newText.Substring(0,$newText.Length-$ending.Length)
                    break
                }
            }
        }
        if ($cfg.Exists) {
            if ($info -and -not $info.HadConfig -and $newText.Length -eq 0) {
                Remove-Item -LiteralPath $cfgPath -Force
            } else { Write-Config $cfgPath $cfg $newText }
        }
        # Keep assets/backups. With no autoload entry these cannot run and make reinstall possible.
        Write-Host '已停用繁體中文模組；可以從 Steam 啟動原版。'
        Write-Host '翻譯檔與備份保留在 jv_zh_tw；不會修改存檔。'
        exit 0
    }

    $manifestPath = Join-Path (Split-Path (Split-Path $GameDir -Parent) -Parent) 'appmanifest_5037200.acf'
    if (Test-Path -LiteralPath $manifestPath) {
        $build = [regex]::Match([IO.File]::ReadAllText($manifestPath),'"buildid"\s+"([0-9]+)"')
        if ($build.Success -and $build.Groups[1].Value -ne '26937150') {
            Write-Host ('提醒：目前 Build '+$build.Groups[1].Value+'，與此版驗證的 26937150 不同；可能需要相容性檢查。')
        }
    }

    $source = Join-Path $PSScriptRoot $modName
    if (-not (Test-Path -LiteralPath (Join-Path $source 'localize.gd')) -or
        -not (Test-Path -LiteralPath (Join-Path $source 'translations.json')) -or
        -not (Test-Path -LiteralPath (Join-Path $source 'settings_panel.gd')) -or
        -not (Test-Path -LiteralPath (Join-Path $source 'match_extras.gd')) -or
        -not (Test-Path -LiteralPath (Join-Path $source 'impact_glyph.gd')) -or
        -not (Test-Path -LiteralPath (Join-Path $source 'effect_preview.gd')) -or
        -not (Test-Path -LiteralPath (Join-Path $source 'topple_stats.gd')) -or
        -not (Test-Path -LiteralPath (Join-Path $source 'ball_trails.gd')) -or
        -not (Test-Path -LiteralPath (Join-Path $source 'score_showcase.gd'))) {
        throw '安裝包不完整，請先完整解壓縮所有檔案。'
    }
    if ((Test-Path -LiteralPath $target) -and -not $owned) {
        throw '遊戲內已有不屬於本安裝包的 jv_zh_tw 目錄；已停止，避免覆蓋。'
    }
    if ($keyMatches.Count -gt 0 -and -not $owned) {
        throw 'override.cfg 已有同名載入項目；已停止，避免覆蓋。'
    }
    $sections = [regex]::Matches($cfg.Text, '(?m)^[ \t]*\[autoload\][ \t]*(?:[;#][^\r\n]*)?(?:\r?\n|$)')
    if ($sections.Count -gt 1) { throw 'override.cfg 包含重複的 [autoload] 區段，請先檢查此檔案。' }
    $newline = "`n"
    if ($cfg.Text.Contains("`r`n")) { $newline = "`r`n" }
    $value = '*' + $target.Replace('\','/') + '/localize.gd'
    if ($value.Contains('"')) { throw '遊戲目錄不能包含雙引號。' }
    $line = $autoloadKey + '="' + $value + '"' + $newline
    $baseText = Remove-AutoloadEntry $cfg.Text
    $sections = [regex]::Matches($baseText, '(?m)^[ \t]*\[autoload\][ \t]*(?:[;#][^\r\n]*)?(?:\r?\n|$)')
    $addedBlock = ''
    $headerWithoutNewline = ''
    if ($sections.Count -eq 1) {
        $s = $sections[0]
        $prefix = ''
        if (-not $s.Value.EndsWith("`n")) { $prefix = $newline; $headerWithoutNewline=$s.Value }
        $newText = $baseText.Insert($s.Index+$s.Length, $prefix+$line)
    } else {
        $prefix = ''
        if ($baseText.Length -gt 0 -and -not $baseText.EndsWith("`n")) { $prefix = $newline }
        $addedBlock = $prefix+'[autoload]'+$newline+$line
        $newText = $baseText+$addedBlock
    }

    $staging = Assert-ChildPath (Join-Path $GameDir ('jv_zh_tw.staging.'+[guid]::NewGuid().ToString('N'))) $GameDir
    $rollback = Assert-ChildPath (Join-Path $GameDir ('jv_zh_tw.rollback.'+[guid]::NewGuid().ToString('N'))) $GameDir
    $hadTarget = Test-Path -LiteralPath $target
    $movedOld = $false
    $newTargetPlaced = $false
    $committed = $false
    try {
        New-Item -ItemType Directory -Path $staging | Out-Null
        foreach ($item in Get-ChildItem -LiteralPath $source -Force) {
            if ($item.Name -notin @('backup','install-info.json')) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '安裝包不可包含連結檔案。' }
                Copy-Item -LiteralPath $item.FullName -Destination $staging -Recurse -Force
            }
        }
        $backupDir = Join-Path $staging 'backup'
        New-Item -ItemType Directory -Path $backupDir | Out-Null
        $existingBackup = Join-Path $target 'backup'
        if ($owned -and (Test-Path -LiteralPath $existingBackup)) {
            foreach ($item in Get-ChildItem -LiteralPath $existingBackup -Force) {
                Copy-Item -LiteralPath $item.FullName -Destination $backupDir -Recurse -Force
            }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $backupDir 'original-state.json'))) {
            @{ HadConfig=$cfg.Exists; CreatedUtc=[DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backupDir 'original-state.json') -Encoding UTF8
            if ($cfg.Exists) { [IO.File]::WriteAllBytes((Join-Path $backupDir 'override.original.cfg'),$oldRaw) }
        }
        $originalInfo = $null
        if ($owned -and (Test-Path -LiteralPath $infoPath)) { $originalInfo = [IO.File]::ReadAllText($infoPath) | ConvertFrom-Json }
        if ($originalInfo -and $keyMatches.Count -gt 0) {
            $hadCfgBefore = $originalInfo.HadConfig
            $headerWithoutNewline = [string]$originalInfo.HeaderWithoutNewline
            if ($originalInfo.AddedSectionBlock) {
                $oldLine = [regex]::Match([string]$originalInfo.AddedSectionBlock,$keyPattern).Value
                $addedBlock = ([string]$originalInfo.AddedSectionBlock).Replace($oldLine,$line)
            }
        } else { $hadCfgBefore = $cfg.Exists }
        @{ PackageId=$packageId; HadConfig=$hadCfgBefore; AddedSectionBlock=$addedBlock; HeaderWithoutNewline=$headerWithoutNewline; InstalledUtc=[DateTime]::UtcNow.ToString('o'); TestedBuild='26937150'; ModVersion='1.3.0' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $staging 'install-info.json') -Encoding UTF8
        if ($hadTarget) { Move-Item -LiteralPath $target -Destination $rollback; $movedOld=$true }
        Move-Item -LiteralPath $staging -Destination $target
        $newTargetPlaced=$true
        Write-Config $cfgPath $cfg $newText
        $committed=$true
    } catch {
        if ($newTargetPlaced -and (Test-Path -LiteralPath $target)) { Remove-TaskDirectory $target $GameDir }
        if ($movedOld -and (Test-Path -LiteralPath $rollback)) { Move-Item -LiteralPath $rollback -Destination $target }
        if ($cfg.Exists) { [IO.File]::WriteAllBytes($cfgPath,$oldRaw) }
        elseif (Test-Path -LiteralPath $cfgPath) { Remove-Item -LiteralPath $cfgPath -Force }
        throw
    } finally {
        Remove-TaskDirectory $staging $GameDir
        if ($committed) { Remove-TaskDirectory $rollback $GameDir }
    }
    Write-Host '繁體中文模組已安裝。請照常從 Steam 啟動遊戲。'
    Write-Host '需要恢復原文時，請關閉遊戲並執行 Uninstall.cmd。'
    Write-Host ('遊戲目錄：'+$GameDir)
} catch {
    Write-Host ('未完成：'+$_.Exception.Message) -ForegroundColor Red
    Write-Host '如果是權限不足，請將安裝包放在可寫入的資料夾，並以系統管理員身分執行 Install.cmd。'
    exit 1
}
