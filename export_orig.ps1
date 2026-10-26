$pptxPath = "C:\Users\Tatva jain\Downloads\MKES CARE+ Front Page (1).pptx"
$outDir = "d:\mkes-lovable\presentation_screenshots\original_slides"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$ppt = New-Object -ComObject PowerPoint.Application
try {
    $presentation = $ppt.Presentations.Open($pptxPath, [Microsoft.Office.Core.MsoTriState]::msoTrue, [Microsoft.Office.Core.MsoTriState]::msoFalse, [Microsoft.Office.Core.MsoTriState]::msoFalse)
    $nums = @(1, 12, 13, 14)
    foreach ($n in $nums) {
        $slide = $presentation.Slides.Item($n)
        $pngPath = Join-Path $outDir ("slide_{0:D2}.png" -f $n)
        $slide.Export($pngPath, "PNG", 1920, 1080)
        Write-Host "Exported slide $n to $pngPath"
    }
    $presentation.Close()
} finally {
    $ppt.Quit()
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
