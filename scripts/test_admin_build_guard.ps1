$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $PSScriptRoot 'build_admin_windows.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Admin build script contains syntax errors.' }
$guard = $ast.Find({ param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-AdminFlutter'
}, $true)
if ($null -eq $guard) { throw 'Admin Flutter exit guard is absent.' }
. ([scriptblock]::Create($guard.Extent.Text))
# Only the extracted wrapper runs; no build, provider call, or file packaging.
function flutter { $global:LASTEXITCODE = 7 }
$rejected = $false
try { Invoke-AdminFlutter -FlutterArguments @('build', 'windows') }
catch {
  if ($_.Exception.Message -notlike 'Flutter build failed*Packaging stopped*') { throw }
  $rejected = $true
}
if (-not $rejected) { throw 'A failed Flutter command did not stop packaging.' }
function flutter { $global:LASTEXITCODE = 0 }
Invoke-AdminFlutter -FlutterArguments @('test')
Write-Output 'Admin build guard: nonzero Flutter exits stop packaging; successful commands continue.'
