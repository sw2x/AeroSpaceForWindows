#requires -Version 7.0
# Regenerate the static application icon, using the same blue as workspace icons.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$images = foreach ($size in @(16, 24, 32, 48, 64, 128, 256)) {
    $bitmap = [Drawing.Bitmap]::new($size, $size)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([Drawing.Color]::FromArgb(35, 88, 174))
    $graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $font = [Drawing.Font]::new('Segoe UI', $size * 0.82, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
    $format = [Drawing.StringFormat]::new()
    $format.Alignment = [Drawing.StringAlignment]::Center
    $format.LineAlignment = [Drawing.StringAlignment]::Center
    $graphics.DrawString('A', $font, [Drawing.Brushes]::White, [Drawing.RectangleF]::new(0, 0, $size, $size), $format)
    $stream = [IO.MemoryStream]::new()
    $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
    [pscustomobject]@{ Size = $size; Data = $stream.ToArray() }
    $stream.Dispose(); $format.Dispose(); $font.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
}
$path = Join-Path (Split-Path $PSScriptRoot -Parent) 'Resources\Windows\AeroSpace.ico'
$output = [IO.File]::Create($path)
$writer = [IO.BinaryWriter]::new($output)
try {
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$images.Count)
    $offset = 6 + 16 * $images.Count
    foreach ($entry in $images) {
        $dimension = if ($entry.Size -eq 256) { 0 } else { $entry.Size }
        $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
        $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([uint16]1); $writer.Write([uint16]32)
        $writer.Write([uint32]$entry.Data.Length); $writer.Write([uint32]$offset)
        $offset += $entry.Data.Length
    }
    foreach ($entry in $images) { $writer.Write([byte[]]$entry.Data) }
} finally { $writer.Dispose(); $output.Dispose() }
