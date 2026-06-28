# Project Code Line Counter
# Usage: .\count_lines.ps1
# powershell -ExecutionPolicy Bypass -File .\count_lines.ps1

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  PROJECT CODE LINE COUNTER" -ForegroundColor Cyan
Write-Host "  Path: $PWD" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# File type patterns -> display name
$fileTypes = @{
    "*.gd"        = "GDScript"
    "*.gdshader"  = "Shader"
    "*.tscn"      = "Scene"
    "*.godot"     = "Config"
    "*.md"        = "Markdown"
}

$results = @()

foreach ($pattern in $fileTypes.Keys) {
    $displayName = $fileTypes[$pattern]
    $files = Get-ChildItem -Path $PWD -Filter $pattern -Recurse -File -Exclude "*.gd.uid", "*.tscn.uid", "*.gdshader.uid"
    
    if ($files.Count -eq 0) {
        continue
    }

    $totalLines = 0
    $totalBlanks = 0
    $totalComments = 0
    $fileDetails = @()

    foreach ($file in $files) {
        $lines = Get-Content -Path $file.FullName
        $lineCount = $lines.Count
        $blankCount = ($lines | Where-Object { $_ -match "^\s*$" }).Count
        $commentCount = 0

        # Count comment lines (GDScript uses #)
        if ($pattern -eq "*.gd" -or $pattern -eq "*.gdshader") {
            $commentCount = ($lines | Where-Object { $_ -match "^\s*#" }).Count
        }

        $totalLines += $lineCount
        $totalBlanks += $blankCount
        $totalComments += $commentCount

        $relPath = $file.FullName.Substring((Get-Location).Path.Length + 1)
        $fileDetails += [PSCustomObject]@{
            File = $relPath
            Lines = $lineCount
        }
    }

    $codeLines = $totalLines - $totalBlanks - $totalComments

    $results += [PSCustomObject]@{
        Type = $displayName
        Files = $files.Count
        Total = $totalLines
        Blanks = $totalBlanks
        Comments = $totalComments
        Code = $codeLines
    }

    # Print file details
    Write-Host ">> $displayName ($($files.Count) files, $totalLines lines)" -ForegroundColor Yellow
    $fileDetails | Sort-Object Lines -Descending | ForEach-Object {
        $bar = "#" * [Math]::Min([Math]::Ceiling($_.Lines / 10), 50)
        Write-Host ("  {0,-55} {1,6} lines  {2}" -f $_.File, $_.Lines, $bar)
    }
    Write-Host ""
}

# Print summary table
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ("{0,-12} {1,6} {2,8} {3,8} {4,8} {5,8}" -f "Type", "Files", "Total", "Blank", "Comment", "Code")
Write-Host ("{0,-12} {1,6} {2,8} {3,8} {4,8} {5,8}" -f "----", "-----", "-----", "-----", "-------", "----")

$totalCode = 0
$totalFiles = 0
$totalTotal = 0
$totalBlanks = 0
$totalComments = 0

foreach ($r in $results) {
    Write-Host ("{0,-12} {1,6} {2,8} {3,8} {4,8} {5,8}" -f $r.Type, $r.Files, $r.Total, $r.Blanks, $r.Comments, $r.Code)
    $totalCode += $r.Code
    $totalFiles += $r.Files
    $totalTotal += $r.Total
    $totalBlanks += $r.Blanks
    $totalComments += $r.Comments
}

Write-Host ("{0,-12} {1,6} {2,8} {3,8} {4,8} {5,8}" -f "----", "-----", "-----", "-----", "-------", "----")
Write-Host ("{0,-12} {1,6} {2,8} {3,8} {4,8} {5,8}" -f "TOTAL", $totalFiles, $totalTotal, $totalBlanks, $totalComments, $totalCode) -ForegroundColor Green

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Done!" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
