# 测试批处理文件编码
# 用于验证生成的批处理文件是否能正确运行

Write-Host "测试批处理文件生成..." -ForegroundColor Cyan
Write-Host ""

# 创建一个测试批处理文件（使用 ASCII/Latin1 编码）
$testBatchFile = "test_batch_temp.bat"
$content = @"
@echo off
echo ========================================
echo Cyrene Music Updater
echo ========================================
echo.
echo This is a test batch file
echo No Chinese characters should cause problems
echo.
echo Current directory: %CD%
echo.
pause
"@

# 使用 ASCII 编码写入
[System.IO.File]::WriteAllText($testBatchFile, $content, [System.Text.Encoding]::ASCII)

Write-Host "批处理文件已创建: $testBatchFile" -ForegroundColor Green
Write-Host ""
Write-Host "文件内容预览:" -ForegroundColor Yellow
Get-Content $testBatchFile | ForEach-Object {
    Write-Host "  $_" -ForegroundColor Gray
}
Write-Host ""
Write-Host "按任意键运行批处理文件..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# 运行批处理文件
& ".\$testBatchFile"

Write-Host ""
Write-Host "清理测试文件..." -ForegroundColor Yellow
Remove-Item $testBatchFile -Force

Write-Host "测试完成！" -ForegroundColor Green

