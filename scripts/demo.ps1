param([string]$Output = (Join-Path $env:TEMP 'moon-photo-merge-demo'))

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $project 'examples\fixtures'
$library = Join-Path $Output 'library'
$incoming = Join-Path $Output 'incoming'
$report = Join-Path $Output 'report'
if ((Test-Path -LiteralPath $library) -or (Test-Path -LiteralPath $incoming)) {
  throw "演示目录已存在，请指定一个新的 -Output 路径：$Output"
}
New-Item -ItemType Directory -Force -Path $library,$incoming,$report | Out-Null
Get-ChildItem -LiteralPath (Join-Path $fixture 'library') -File | Copy-Item -Destination $library
Get-ChildItem -LiteralPath (Join-Path $fixture 'incoming') -File | Copy-Item -Destination $incoming
Push-Location $project
try {
  moon run cmd/main -- scan $library $incoming $report
  if ($LASTEXITCODE -ne 0) { throw '预检失败' }
  Write-Output "现有相册：$library"
  Write-Output "待导入备份：$incoming"
  Write-Output "审核报告：$(Join-Path $report 'review.html')"
} finally {
  Pop-Location
}
