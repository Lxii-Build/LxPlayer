# Windows 自动更新测试脚本
# 用于快速测试新的独立更新器机制

param(
    [Parameter(Mandatory=$false)]
    [string]$OldVersion = "1.0.5",
    
    [Parameter(Mandatory=$false)]
    [string]$NewVersion = "1.0.6"
)

$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Windows 自动更新测试脚本" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# 1. 检查环境
Write-Host "[1/6] 检查环境..." -ForegroundColor Yellow

if (-not (Test-Path "pubspec.yaml")) {
    Write-Host "错误: 请在项目根目录运行此脚本" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "错误: 找不到 Flutter 命令" -ForegroundColor Red
    exit 1
}

Write-Host "✓ 环境检查通过" -ForegroundColor Green
Write-Host ""

# 2. 读取当前版本
Write-Host "[2/6] 读取当前版本..." -ForegroundColor Yellow

$pubspecContent = Get-Content "pubspec.yaml" -Raw
if ($pubspecContent -match 'version:\s*([\d.+]+)') {
    $currentVersion = $matches[1]
    Write-Host "当前版本: $currentVersion" -ForegroundColor Cyan
} else {
    Write-Host "错误: 无法读取版本号" -ForegroundColor Red
    exit 1
}

Write-Host ""

# 3. 构建旧版本（如果需要）
Write-Host "[3/6] 准备旧版本构建..." -ForegroundColor Yellow

$oldBuildPath = "build/windows/x64/runner/Release_$OldVersion"
if (Test-Path $oldBuildPath) {
    Write-Host "✓ 旧版本构建已存在: $oldBuildPath" -ForegroundColor Green
} else {
    Write-Host "正在构建旧版本 $OldVersion ..." -ForegroundColor Cyan
    
    # 暂存当前 pubspec.yaml
    Copy-Item "pubspec.yaml" "pubspec.yaml.bak"
    
    # 修改版本号
    $pubspecContent -replace 'version:\s*[\d.+]+', "version: $OldVersion+${OldVersion.Replace('.', '')}" | Set-Content "pubspec.yaml"
    
    # 构建
    flutter build windows --release
    
    # 复制构建结果
    if (Test-Path "build/windows/x64/runner/Release") {
        Copy-Item -Path "build/windows/x64/runner/Release" -Destination $oldBuildPath -Recurse -Force
        Write-Host "✓ 旧版本构建完成" -ForegroundColor Green
    } else {
        Write-Host "错误: 构建失败" -ForegroundColor Red
        Move-Item "pubspec.yaml.bak" "pubspec.yaml" -Force
        exit 1
    }
    
    # 恢复 pubspec.yaml
    Move-Item "pubspec.yaml.bak" "pubspec.yaml" -Force
}

Write-Host ""

# 4. 构建新版本
Write-Host "[4/6] 构建新版本 $NewVersion ..." -ForegroundColor Yellow

# 暂存当前 pubspec.yaml
Copy-Item "pubspec.yaml" "pubspec.yaml.bak"

# 修改版本号
$pubspecContent -replace 'version:\s*[\d.+]+', "version: $NewVersion+${NewVersion.Replace('.', '')}" | Set-Content "pubspec.yaml"

# 构建
flutter build windows --release

# 恢复 pubspec.yaml
Move-Item "pubspec.yaml.bak" "pubspec.yaml" -Force

if (-not (Test-Path "build/windows/x64/runner/Release")) {
    Write-Host "错误: 新版本构建失败" -ForegroundColor Red
    exit 1
}

Write-Host "✓ 新版本构建完成" -ForegroundColor Green
Write-Host ""

# 5. 打包新版本为 ZIP
Write-Host "[5/6] 打包更新包..." -ForegroundColor Yellow

$updateDir = "backend/update/$NewVersion"
$zipPath = "$updateDir/windows-$NewVersion.zip"

if (-not (Test-Path $updateDir)) {
    New-Item -ItemType Directory -Path $updateDir -Force | Out-Null
}

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

Compress-Archive -Path "build/windows/x64/runner/Release/*" -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host "✓ 更新包已创建: $zipPath" -ForegroundColor Green
Write-Host "  大小: $([math]::Round((Get-Item $zipPath).Length / 1MB, 2)) MB" -ForegroundColor Cyan
Write-Host ""

# 6. 准备测试环境
Write-Host "[6/6] 准备测试..." -ForegroundColor Yellow

$testDir = "test_update_temp"
if (Test-Path $testDir) {
    Write-Host "清理旧的测试目录..." -ForegroundColor Cyan
    Remove-Item $testDir -Recurse -Force
}

New-Item -ItemType Directory -Path $testDir -Force | Out-Null
Copy-Item -Path "$oldBuildPath/*" -Destination $testDir -Recurse -Force

Write-Host "✓ 测试环境准备完成" -ForegroundColor Green
Write-Host ""

# 测试说明
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "测试准备完成！" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "接下来的步骤：" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. 启动后端服务器 (如果还未启动):" -ForegroundColor White
Write-Host "   cd backend" -ForegroundColor Gray
Write-Host "   bun run src/index.ts" -ForegroundColor Gray
Write-Host ""
Write-Host "2. 确保后端版本接口返回新版本信息:" -ForegroundColor White
Write-Host "   GET http://localhost:4055/version/check/windows/current" -ForegroundColor Gray
Write-Host "   应该返回: {version: '$NewVersion', downloadUrl: '/update/$NewVersion/windows-$NewVersion.zip', ...}" -ForegroundColor Gray
Write-Host ""
Write-Host "3. 运行旧版本应用:" -ForegroundColor White
Write-Host "   cd $testDir" -ForegroundColor Gray
Write-Host "   .\cyrene_music.exe" -ForegroundColor Gray
Write-Host ""
Write-Host "4. 在应用中:" -ForegroundColor White
Write-Host "   - 进入【设置】->【关于】" -ForegroundColor Gray
Write-Host "   - 开启【自动更新】" -ForegroundColor Gray
Write-Host "   - 点击【检查更新】" -ForegroundColor Gray
Write-Host "   - 应用会自动下载、更新并重启" -ForegroundColor Gray
Write-Host ""
Write-Host "5. 验证更新:" -ForegroundColor White
Write-Host "   - 应用重启后，版本号应该变为 $NewVersion" -ForegroundColor Gray
Write-Host "   - 查看更新日志: $testDir\updater.log" -ForegroundColor Gray
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "提示：如果更新失败，请查看以下日志：" -ForegroundColor Yellow
Write-Host "  - 应用日志: 应用内的开发者页面" -ForegroundColor Gray
Write-Host "  - 更新器日志: $testDir\updater.log" -ForegroundColor Gray
Write-Host ""

