#Requires -Version 5.1
<#
.SYNOPSIS
Use this checkout as the Windows Emacs configuration, with a reversible backup.
.EXAMPLE
.\scripts\use-repository.ps1 -WhatIf
.EXAMPLE
.\scripts\use-repository.ps1
.EXAMPLE
.\scripts\use-repository.ps1 -RestoreBackup 'C:\Users\you\AppData\Roaming\.emacs.d.backup-20261031-180000-123-abcdef12'
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string] $RepoPath = (Split-Path -Parent $PSScriptRoot),
    [string] $ProfilePath = (Join-Path $env:APPDATA '.emacs.d'),
    [string] $ShortcutPath = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Emacs-31.1\Emacs.lnk'),
    [string] $RestoreBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AbsoluteLocalPath([string] $Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[a-zA-Z]:[\\/]') {
        throw "An absolute local Windows path is required: $Path"
    }
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    if ($fullPath -match '^[a-zA-Z]:$') {
        throw "A drive root cannot be used: $Path"
    }
    return $fullPath
}

function Test-SamePath([string] $Left, [string] $Right) {
    return [string]::Equals($Left, $Right, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-DirectChild([string] $Child, [string] $Parent) {
    if (-not (Test-SamePath (Split-Path -Parent $Child) $Parent)) {
        throw "Refusing an operation outside the expected parent: $Child"
    }
}

function Assert-PathAbsent([string] $Path) {
    if ($null -ne (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)) {
        throw "The path unexpectedly exists; refusing to merge, nest or overwrite it: $Path"
    }
}

function Move-DirectoryExactly([string] $Source, [string] $Destination) {
    $sourceItem = Get-Item -LiteralPath $Source -Force
    if (-not $sourceItem.PSIsContainer -or ($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "The directory to move must be a regular directory: $Source"
    }
    Assert-PathAbsent $Destination
    # Unlike Move-Item, Directory.Move cannot silently nest Source inside an
    # existing Destination. The OS also rejects a destination created after
    # the check above. All call sites validate both paths before moving.
    [IO.Directory]::Move($Source, $Destination)
}

function Get-ProfileKind {
    $item = Get-Item -LiteralPath $script:ProfilePath -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return 'Absent' }
    if (-not $item.PSIsContainer) { throw "The profile path is a file: $script:ProfilePath" }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        if ($item.LinkType -ne 'Junction' -or @($item.Target).Count -ne 1) {
            throw "The profile is an unsupported reparse point: $script:ProfilePath"
        }
        $target = Get-AbsoluteLocalPath ([string] @($item.Target)[0])
        if (-not (Test-SamePath $target $script:RepoPath)) {
            throw "The profile junction points elsewhere ($target). Nothing was changed."
        }
        return 'RepositoryJunction'
    }
    return 'Directory'
}

function Remove-RepositoryJunction {
    if ((Get-ProfileKind) -ne 'RepositoryJunction') {
        throw 'The expected repository junction is missing; refusing to remove anything.'
    }
    # DirectoryInfo.Delete removes this junction itself, never its target contents.
    [IO.Directory]::Delete($script:ProfilePath)
}

function Save-State($State, [string] $Path) {
    $State | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Path -Encoding UTF8 -Confirm:$false
}

if ($env:OS -ne 'Windows_NT') { throw 'This script is for Windows.' }
$RepoPath = Get-AbsoluteLocalPath $RepoPath
$ProfilePath = Get-AbsoluteLocalPath $ProfilePath
$ShortcutPath = Get-AbsoluteLocalPath $ShortcutPath
$profileParent = Split-Path -Parent $ProfilePath
$profileLeaf = Split-Path -Leaf $ProfilePath
if ((Test-SamePath $RepoPath $ProfilePath) -or
    $RepoPath.StartsWith($ProfilePath + '\', [StringComparison]::OrdinalIgnoreCase) -or
    $ProfilePath.StartsWith($RepoPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The repository and profile must be separate, non-nested paths.'
}
if (-not $RestoreBackup -and -not (Test-Path -LiteralPath (Join-Path $RepoPath 'init.el') -PathType Leaf)) {
    throw "The repository must contain init.el: $RepoPath"
}
if (-not (Test-Path -LiteralPath $profileParent -PathType Container)) {
    throw "The profile parent directory does not exist: $profileParent"
}
if ([IO.Path]::GetExtension($ShortcutPath) -ne '.lnk' -or
    -not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf)) {
    throw "The existing Emacs shortcut was not found: $ShortcutPath"
}
if ((Get-Item -LiteralPath $ShortcutPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'The shortcut itself must be a regular file.'
}
$running = @(Get-Process | Where-Object { $_.ProcessName -match '^(runemacs|emacs|emacsclientw?)(-.+)?$' })
if ($running.Count -gt 0) {
    throw ('Save your work and exit Emacs before switching configurations. Running process IDs: ' +
        (($running | Select-Object -ExpandProperty Id) -join ', '))
}
$profileKind = Get-ProfileKind
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$newArguments = '--init-directory "' + $RepoPath + '"'
if ([IO.Path]::GetFileName($shortcut.TargetPath) -notin @('emacs.exe', 'runemacs.exe')) {
    throw "The shortcut does not start Emacs: $($shortcut.TargetPath)"
}

if ($RestoreBackup) {
    $backupPath = Get-AbsoluteLocalPath $RestoreBackup
    Assert-DirectChild $backupPath $profileParent
    if (-not (Split-Path -Leaf $backupPath).StartsWith($profileLeaf + '.backup-', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The backup directory name does not match this profile.'
    }
    $backupItem = Get-Item -LiteralPath $backupPath -Force
    if (-not $backupItem.PSIsContainer -or ($backupItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The backup must be a regular directory.'
    }
    $statePath = Join-Path $backupPath 'restore.json'
    $savedProfile = Join-Path $backupPath 'profile'
    $savedShortcut = Join-Path $backupPath 'original-Emacs.lnk'
    $switchedShortcut = Join-Path $backupPath 'repository-Emacs.lnk'
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.Version -ne 1 -or
        -not (Test-SamePath ([string] $state.RepoPath) $RepoPath) -or
        -not (Test-SamePath ([string] $state.ProfilePath) $ProfilePath) -or
        -not (Test-SamePath ([string] $state.ShortcutPath) $ShortcutPath) -or
        $state.ProfileAction -notin @('Replaced', 'Created', 'None')) {
        throw 'The backup metadata does not match the requested repository, profile and shortcut.'
    }
    if ($state.Restored) {
        Write-Output "This backup has already been restored: $backupPath"
        return
    }
    if (-not $state.Completed) { throw 'This backup was not completed; inspect it before recovering manually.' }
    foreach ($file in @($savedShortcut, $switchedShortcut, $statePath)) {
        $fileItem = Get-Item -LiteralPath $file -Force
        if ($fileItem.PSIsContainer -or ($fileItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "The backup contains an unexpected file type: $file"
        }
    }
    if ((Get-FileHash -LiteralPath $ShortcutPath).Hash -ne $state.RepositoryShortcutHash -or
        (Get-FileHash -LiteralPath $switchedShortcut).Hash -ne $state.RepositoryShortcutHash -or
        (Get-FileHash -LiteralPath $savedShortcut).Hash -ne $state.OriginalShortcutHash) {
        throw 'A shortcut changed after switching. Refusing to overwrite it automatically.'
    }
    if ($profileKind -ne 'RepositoryJunction') {
        throw 'The current profile is no longer the expected repository junction.'
    }
    if ($state.ProfileAction -eq 'Replaced') {
        $savedItem = Get-Item -LiteralPath $savedProfile -Force
        if (-not $savedItem.PSIsContainer -or ($savedItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'The saved profile must be a regular directory.'
        }
        Assert-DirectChild $savedProfile $backupPath
    }
    if (-not $PSCmdlet.ShouldProcess($ProfilePath, "Restore the profile and shortcut from $backupPath")) { return }
    $junctionRemoved = $false
    $profileRestored = $false
    try {
        if ($state.ProfileAction -ne 'None') {
            Remove-RepositoryJunction
            $junctionRemoved = $true
        }
        if ($state.ProfileAction -eq 'Replaced') {
            Assert-DirectChild $ProfilePath $profileParent
            Move-DirectoryExactly $savedProfile $ProfilePath
            $profileRestored = $true
            Assert-PathAbsent $savedProfile
        }
        Copy-Item -LiteralPath $savedShortcut -Destination $ShortcutPath -Force -Confirm:$false
        $state.Restored = $true
        Save-State $state $statePath
    }
    catch {
        $restoreError = $_
        $rollbackErrors = [Collections.Generic.List[string]]::new()
        if ($profileRestored) {
            try {
                Assert-DirectChild $ProfilePath $profileParent
                Assert-DirectChild $savedProfile $backupPath
                Move-DirectoryExactly $ProfilePath $savedProfile
                Assert-PathAbsent $ProfilePath
            }
            catch { $rollbackErrors.Add($_.Exception.Message) }
        }
        if ($junctionRemoved -and -not (Test-Path -LiteralPath $ProfilePath)) {
            try { New-Item -ItemType Junction -Path $ProfilePath -Target $RepoPath -Confirm:$false | Out-Null }
            catch { $rollbackErrors.Add($_.Exception.Message) }
        }
        try { Copy-Item -LiteralPath $switchedShortcut -Destination $ShortcutPath -Force -Confirm:$false }
        catch { $rollbackErrors.Add($_.Exception.Message) }
        if ($rollbackErrors.Count -gt 0) {
            throw ("Restore failed: {0}. Rollback needs attention: {1}. No conflicting directory was overwritten or nested. Backup: {2}" -f
                $restoreError.Exception.Message, ($rollbackErrors -join '; '), $backupPath)
        }
        throw $restoreError
    }
    Write-Output "Restored the previous Emacs profile and shortcut. Backup records: $backupPath"
    return
}

if ($profileKind -eq 'RepositoryJunction' -and $shortcut.Arguments -eq $newArguments) {
    Write-Output "Emacs already uses this repository: $RepoPath"
    return
}
$suffix = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$backupPath = Join-Path $profileParent ($profileLeaf + '.backup-' + $suffix)
$savedProfile = Join-Path $backupPath 'profile'
$statePath = Join-Path $backupPath 'restore.json'
$savedShortcut = Join-Path $backupPath 'original-Emacs.lnk'
$switchedShortcut = Join-Path $backupPath 'repository-Emacs.lnk'
Assert-DirectChild $backupPath $profileParent
Assert-DirectChild $savedProfile $backupPath
if (Test-Path -LiteralPath $backupPath) { throw "The backup path already exists: $backupPath" }
$profileAction = switch ($profileKind) {
    'Directory' { 'Replaced' }
    'Absent' { 'Created' }
    'RepositoryJunction' { 'None' }
}
if (-not $PSCmdlet.ShouldProcess($ProfilePath, "Use $RepoPath and save a reversible backup at $backupPath")) { return }
$state = [ordered]@{
    Version = 1
    RepoPath = $RepoPath
    ProfilePath = $ProfilePath
    ShortcutPath = $ShortcutPath
    ProfileAction = $profileAction
    OriginalShortcutHash = (Get-FileHash -LiteralPath $ShortcutPath).Hash
    RepositoryShortcutHash = ''
    Completed = $false
    Restored = $false
}
$profileMoved = $false
$junctionCreated = $false
try {
    New-Item -ItemType Directory -Path $backupPath -Confirm:$false | Out-Null
    Copy-Item -LiteralPath $ShortcutPath -Destination $savedShortcut -Confirm:$false
    Save-State $state $statePath
    if ($profileAction -eq 'Replaced') {
        Assert-DirectChild $ProfilePath $profileParent
        Move-DirectoryExactly $ProfilePath $savedProfile
        $profileMoved = $true
        Assert-PathAbsent $ProfilePath
    }
    if ($profileAction -ne 'None') {
        Assert-PathAbsent $ProfilePath
        New-Item -ItemType Junction -Path $ProfilePath -Target $RepoPath -Confirm:$false | Out-Null
        $junctionCreated = $true
        if ((Get-ProfileKind) -ne 'RepositoryJunction') {
            throw 'Junction creation did not produce the expected repository junction.'
        }
    }
    $shortcut.Arguments = $newArguments
    $shortcut.Save()
    Copy-Item -LiteralPath $ShortcutPath -Destination $switchedShortcut -Confirm:$false
    $state.RepositoryShortcutHash = (Get-FileHash -LiteralPath $ShortcutPath).Hash
    $state.Completed = $true
    Save-State $state $statePath
}
catch {
    $switchError = $_
    $rollbackErrors = [Collections.Generic.List[string]]::new()
    if ($junctionCreated) {
        try { Remove-RepositoryJunction }
        catch { $rollbackErrors.Add($_.Exception.Message) }
    }
    if ($profileMoved) {
        try {
            Assert-DirectChild $ProfilePath $profileParent
            Move-DirectoryExactly $savedProfile $ProfilePath
            Assert-PathAbsent $savedProfile
        }
        catch { $rollbackErrors.Add($_.Exception.Message) }
    }
    if (Test-Path -LiteralPath $savedShortcut) {
        try { Copy-Item -LiteralPath $savedShortcut -Destination $ShortcutPath -Force -Confirm:$false }
        catch { $rollbackErrors.Add($_.Exception.Message) }
    }
    if ($rollbackErrors.Count -gt 0) {
        throw ("Switch failed: {0}. Rollback needs attention: {1}. No conflicting directory was overwritten or nested. Original profile backup: {2}; shortcut backup: {3}" -f
            $switchError.Exception.Message, ($rollbackErrors -join '; '), $savedProfile, $savedShortcut)
    }
    throw $switchError
}
Write-Output "Emacs now uses: $RepoPath"
Write-Output "Backup: $backupPath"
Write-Output ("Restore with: & '$PSCommandPath' -RestoreBackup '$backupPath'")
