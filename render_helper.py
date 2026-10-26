import subprocess
import os

def render_pptx_slides(pptx_path, out_dir, slide_nums=None):
    os.makedirs(out_dir, exist_ok=True)
    nums_str = ','.join(str(n) for n in slide_nums) if slide_nums else ''
    ps_code = f'''
$pptxPath = "{pptx_path}"
$outDir = "{out_dir}"
$nums = "{nums_str}".Split(',') | Where-Object {{ $_ -ne "" }} | ForEach-Object {{ [int]$_ }}

$ppt = New-Object -ComObject PowerPoint.Application
try {{
    $presentation = $ppt.Presentations.Open($pptxPath, [Microsoft.Office.Core.MsoTriState]::msoTrue, [Microsoft.Office.Core.MsoTriState]::msoFalse, [Microsoft.Office.Core.MsoTriState]::msoFalse)
    if ($nums.Count -eq 0) {{
        for ($i = 1; $i -le $presentation.Slides.Count; $i++) {{
            $slide = $presentation.Slides.Item($i)
            $pngPath = Join-Path $outDir ("slide_{{0:D2}}.png" -f $i)
            $slide.Export($pngPath, "PNG", 1920, 1080)
        }}
    }} else {{
        foreach ($n in $nums) {{
            $slide = $presentation.Slides.Item($n)
            $pngPath = Join-Path $outDir ("slide_{{0:D2}}.png" -f $n)
            $slide.Export($pngPath, "PNG", 1920, 1080)
        }}
    }}
    $presentation.Close()
}} finally {{
    $ppt.Quit()
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}}
'''
    with open('render_temp.ps1', 'w', encoding='utf-8') as f:
        f.write(ps_code)
    res = subprocess.run(['powershell', '-ExecutionPolicy', 'Bypass', '-File', 'render_temp.ps1'], capture_output=True, text=True)
    if os.path.exists('render_temp.ps1'):
        os.remove('render_temp.ps1')
    return res

if __name__ == '__main__':
    res = render_pptx_slides(r'd:\mkes-lovable\test_slide1.pptx', r'd:\mkes-lovable\presentation_screenshots\test_render', [1])
    print('Render result:', res.returncode, res.stdout, res.stderr)
