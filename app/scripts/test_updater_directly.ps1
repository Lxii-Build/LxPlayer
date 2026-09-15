# 直接测试更新器脚本
# 用于验证更新器逻辑是否正常工作

param(
    [Parameter(Mandatory=$false)]
    [string]$TestDir = "test_updater_temp"
)

$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "更新器脚本直接测试" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# 1. 准备测试环境
Write-Host "[1/5] 准备测试环境..." -ForegroundColor Yellow

if (Test-Path $TestDir) {
    Write-Host "清理旧的测试目录..." -ForegroundColor Gray
    Remove-Item $TestDir -Recurse -Force
}

# 创建模拟的安装目录
$installDir = Join-Path $TestDir "install"
New-Item -ItemType Directory -Path $installDir -Force | Out-Null

# 创建一些模拟的旧文件
$oldExePath = Join-Path $installDir "cyrene_music.exe"
$oldDllPath = Join-Path $installDir "flutter_windows.dll"
$oldDataPath = Join-Path $installDir "data\flutter_assets\version.txt"

New-Item -ItemType Directory -Path (Split-Path $oldDataPath -Parent) -Force | Out-Null
Set-Content -Path $oldExePath -Value "OLD VERSION EXE" -Encoding ASCII
Set-Content -Path $oldDllPath -Value "OLD VERSION DLL" -Encoding ASCII
Set-Content -Path $oldDataPath -Value "1.0.5" -Encoding ASCII

Write-Host "✓ 创建了模拟的旧文件:" -ForegroundColor Green
Write-Host "  - $oldExePath" -ForegroundColor Gray
Write-Host "  - $oldDllPath" -ForegroundColor Gray
Write-Host "  - $oldDataPath" -ForegroundColor Gray
Write-Host ""

# 2. 创建模拟的更新文件
Write-Host "[2/5] 创建模拟的更新文件..." -ForegroundColor Yellow

$updateDir = Join-Path $TestDir "updates\temp_123456"
New-Item -ItemType Directory -Path $updateDir -Force | Out-Null

$newExePath = Join-Path $updateDir "cyrene_music.exe"
$newDllPath = Join-Path $updateDir "flutter_windows.dll"
$newDataPath = Join-Path $updateDir "data\flutter_assets\version.txt"

New-Item -ItemType Directory -Path (Split-Path $newDataPath -Parent) -Force | Out-Null
Set-Content -Path $newExePath -Value "NEW VERSION 1.0.6 EXE" -Encoding ASCII
Set-Content -Path $newDllPath -Value "NEW VERSION 1.0.6 DLL" -Encoding ASCII
Set-Content -Path $newDataPath -Value "1.0.6" -Encoding ASCII

Write-Host "✓ 创建了模拟的新文件:" -ForegroundColor Green
Write-Host "  - $newExePath" -ForegroundColor Gray
Write-Host "  - $newDllPath" -ForegroundColor Gray
Write-Host "  - $newDataPath" -ForegroundColor Gray
Write-Host ""

# 3. 准备更新器脚本
Write-Host "[3/5] 准备更新器脚本..." -ForegroundColor Yellow

$updaterScript = "windows\runner\updater.ps1"
if (-not (Test-Path $updaterScript)) {
    Write-Host "错误: 找不到更新器脚本: $updaterScript" -ForegroundColor Red
    exit 1
}

Write-Host "✓ 找到更新器脚本: $updaterScript" -ForegroundColor Green
Write-Host ""

# 4. 显示测试参数
Write-Host "[4/5] 测试参数:" -ForegroundColor Yellow
Write-Host "  InstallDir: $installDir" -ForegroundColor Cyan
Write-Host "  UpdateDir: $updateDir" -ForegroundColor Cyan
Write-Host "  ExePath: $oldExePath" -ForegroundColor Cyan
Write-Host ""

# 5. 执行更新器
Write-Host "[5/5] 执行更新器脚本..." -ForegroundColor Yellow
Write-Host "按任意键开始测试..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Host ""

try {
    & $updaterScript `
        -InstallDir $installDir `
        -UpdateDir $updateDir `
        -ExePath $oldExePath `
        -WaitSeconds 1
    
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "更新器执行完成" -ForegroundColor Green
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # 验证结果
    Write-Host "验证更新结果:" -ForegroundColor Yellow
    Write-Host ""
    
    # 检查文件是否被更新
    $exeContent = Get-Content $oldExePath -Raw
    $dllContent = Get-Content $oldDllPath -Raw
    $versionContent = Get-Content (Join-Path $installDir "data\flutter_assets\version.txt") -Raw
    
    Write-Host "EXE 文件内容: $($exeContent.Trim())" -ForegroundColor $(if ($exeContent.Contains("NEW VERSION")) { "Green" } else { "Red" })
    Write-Host "DLL 文件内容: $($dllContent.Trim())" -ForegroundColor $(if ($dllContent.Contains("NEW VERSION")) { "Green" } else { "Red" })
    Write-Host "版本文件内容: $($versionContent.Trim())" -ForegroundColor $(if ($versionContent.Contains("1.0.6")) { "Green" } else { "Red" })
    Write-Host ""
    
    # 检查更新日志
    $logPath = Join-Path $installDir "updater.log"
    if (Test-Path $logPath) {
        Write-Host "更新日志 (最后 20 行):" -ForegroundColor Yellow
        Get-Content $logPath -Tail 20 | ForEach-Object {
            Write-Host "  $_" -ForegroundColor Gray
        }
    } else {
        Write-Host "警告: 未找到更新日志文件: $logPath" -ForegroundColor Red
    }
    Write-Host ""
    
    # 检查临时目录是否被删除
    if (Test-Path $updateDir) {
        Write-Host "警告: 临时更新目录未被删除: $updateDir" -ForegroundColor Yellow
    } else {
        Write-Host "✓ 临时更新目录已清理" -ForegroundColor Green
    }
    Write-Host ""
    
    # 总结
    $success = $exeContent.Contains("NEW VERSION") -and 
               $dllContent.Contains("NEW VERSION") -and 
               $versionContent.Contains("1.0.6")
    
    if ($success) {
        Write-Host "✓✓✓ 测试成功！所有文件均已正确更新 ✓✓✓" -ForegroundColor Green
    } else {
        Write-Host "✗✗✗ 测试失败！某些文件未能更新 ✗✗✗" -ForegroundColor Red
    }
    
} catch {
    Write-Host ""
    Write-Host "错误: 更新器执行失败" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "测试完成" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "测试文件位置: $TestDir" -ForegroundColor Gray
Write-Host "更新日志: $(Join-Path $installDir 'updater.log')" -ForegroundColor Gray
Write-Host ""

