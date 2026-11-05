param(
  [int]$ParentPid = 0,
  [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
try { [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:webViewDir = Join-Path $PSScriptRoot 'webview2'
if (-not (Test-Path -LiteralPath (Join-Path $script:webViewDir 'Microsoft.Web.WebView2.WinForms.dll'))) {
  throw "找不到 WebView2 SDK：$script:webViewDir"
}
[Environment]::CurrentDirectory = $script:webViewDir
$env:PATH = ($script:webViewDir + ';' + $env:PATH)
Add-Type -Path (Join-Path $script:webViewDir 'Microsoft.Web.WebView2.Core.dll')
Add-Type -Path (Join-Path $script:webViewDir 'Microsoft.Web.WebView2.WinForms.dll')

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ScreenSnapDpi {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern uint GetDpiForSystem();
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
}
"@

try {
  [ScreenSnapDpi]::SetProcessDpiAwarenessContext([IntPtr]::new(-4)) | Out-Null
} catch {
  try { [ScreenSnapDpi]::SetProcessDPIAware() | Out-Null } catch { }
}

Add-Type -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing' -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class ScreenSnapNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct SIZE { public int cx; public int cy; }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct BLENDFUNCTION {
        public byte BlendOp;
        public byte BlendFlags;
        public byte SourceConstantAlpha;
        public byte AlphaFormat;
    }

    const int ULW_ALPHA = 2;
    const byte AC_SRC_OVER = 0;
    const byte AC_SRC_ALPHA = 1;

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc, ref POINT pptSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);

    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr hDC);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr hdc, IntPtr h);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr hObject);

    public static bool Apply(IntPtr hwnd, Bitmap bitmap, int x, int y) {
        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memDc = CreateCompatibleDC(screenDc);
        IntPtr hBitmap = bitmap.GetHbitmap(Color.FromArgb(0));
        IntPtr oldBitmap = SelectObject(memDc, hBitmap);
        try {
            SIZE size = new SIZE();
            size.cx = bitmap.Width;
            size.cy = bitmap.Height;
            POINT src = new POINT();
            src.X = 0;
            src.Y = 0;
            POINT dst = new POINT();
            dst.X = x;
            dst.Y = y;
            BLENDFUNCTION blend = new BLENDFUNCTION();
            blend.BlendOp = AC_SRC_OVER;
            blend.BlendFlags = 0;
            blend.SourceConstantAlpha = 255;
            blend.AlphaFormat = AC_SRC_ALPHA;
            return UpdateLayeredWindow(hwnd, screenDc, ref dst, ref size, memDc, ref src, 0, ref blend, ULW_ALPHA);
        } finally {
            SelectObject(memDc, oldBitmap);
            DeleteObject(hBitmap);
            DeleteDC(memDc);
            ReleaseDC(IntPtr.Zero, screenDc);
        }
    }
}

public class ScreenSnapMainForm : Form {
    public ScreenSnapMainForm() {
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
        UpdateStyles();
        AutoScaleMode = AutoScaleMode.None;
    }
}

public class ScreenSnapFrozenForm : Form {
    public ScreenSnapFrozenForm() {
        SetStyle(ControlStyles.Opaque | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
        UpdateStyles();
        AutoScaleMode = AutoScaleMode.None;
    }
}

public class ScreenSnapHudForm : Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x00000020;
            cp.ExStyle |= 0x00080000;
            cp.ExStyle |= 0x08000000;
            cp.ExStyle |= 0x00000080;
            return cp;
        }
    }
}

public class ScreenSnapBallForm : Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x00080000;
            cp.ExStyle |= 0x08000000;
            cp.ExStyle |= 0x00000080;
            return cp;
        }
    }
}

public class ScreenSnapShadowForm : Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x00000020;
            cp.ExStyle |= 0x00080000;
            cp.ExStyle |= 0x08000000;
            cp.ExStyle |= 0x00000080;
            return cp;
        }
    }
}

public class ScreenSnapMenuColors : ProfessionalColorTable {
    static readonly Color Background = Color.FromArgb(27, 33, 48);
    static readonly Color Line = Color.FromArgb(46, 55, 74);
    static readonly Color Hover = Color.FromArgb(52, 76, 141, 255);
    public override Color ToolStripDropDownBackground { get { return Background; } }
    public override Color ImageMarginGradientBegin { get { return Background; } }
    public override Color ImageMarginGradientMiddle { get { return Background; } }
    public override Color ImageMarginGradientEnd { get { return Background; } }
    public override Color MenuBorder { get { return Line; } }
    public override Color MenuItemBorder { get { return Hover; } }
    public override Color MenuItemSelected { get { return Hover; } }
    public override Color MenuItemSelectedGradientBegin { get { return Hover; } }
    public override Color MenuItemSelectedGradientEnd { get { return Hover; } }
    public override Color SeparatorDark { get { return Color.FromArgb(62, 74, 98); } }
    public override Color SeparatorLight { get { return Background; } }
}

public class ScreenSnapMenuRenderer : ToolStripProfessionalRenderer {
    readonly float scale;
    public ScreenSnapMenuRenderer(ProfessionalColorTable table, float scale) : base(table) {
        this.scale = scale <= 0f ? 1f : scale;
        RoundedEdges = false;
    }
    public static GraphicsPath RoundedRect(RectangleF rect, float radius) {
        GraphicsPath path = new GraphicsPath();
        float d = radius * 2f;
        path.AddArc(rect.X, rect.Y, d, d, 180f, 90f);
        path.AddArc(rect.Right - d, rect.Y, d, d, 270f, 90f);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0f, 90f);
        path.AddArc(rect.X, rect.Bottom - d, d, d, 90f, 90f);
        path.CloseFigure();
        return path;
    }
    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
        if (!e.Item.Selected || !e.Item.Enabled) return;
        Graphics g = e.Graphics;
        SmoothingMode previous = g.SmoothingMode;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        RectangleF rect = new RectangleF(3f * scale, 3f * scale, e.Item.Width - 6f * scale, e.Item.Height - 6f * scale);
        using (GraphicsPath path = RoundedRect(rect, 7f * scale))
        using (SolidBrush brush = new SolidBrush(Color.FromArgb(58, 76, 141, 255))) {
            g.FillPath(brush, path);
        }
        g.SmoothingMode = previous;
    }
    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) {
        Color color = !e.Item.Enabled
            ? Color.FromArgb(118, 128, 148)
            : (e.Item.Selected ? Color.FromArgb(255, 255, 255) : e.Item.ForeColor);
        int left = Math.Max(e.TextRectangle.X, (int)(20f * scale));
        int right = (int)(16f * scale);
        int width = Math.Max(e.Item.Width - left - right, 30);
        Rectangle box = new Rectangle(left, 0, width, e.Item.Height);
        TextFormatFlags flags = TextFormatFlags.Left | TextFormatFlags.VerticalCenter |
            TextFormatFlags.SingleLine | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix;
        TextRenderer.DrawText(e.Graphics, e.Text, e.TextFont, box, color, flags);
    }
    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e) {
        Graphics g = e.Graphics;
        float y = e.Item.Height / 2f;
        using (Pen pen = new Pen(Color.FromArgb(34, 255, 255, 255), 1f)) {
            g.DrawLine(pen, 13f * scale, y, e.Item.Width - 13f * scale, y);
        }
    }
    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e) {
        Graphics g = e.Graphics;
        SmoothingMode previous = g.SmoothingMode;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        RectangleF rect = new RectangleF(0.5f, 0.5f, e.ToolStrip.Width - 1f, e.ToolStrip.Height - 1f);
        using (GraphicsPath path = RoundedRect(rect, 10f * scale))
        using (Pen pen = new Pen(Color.FromArgb(46, 56, 76), 1f)) {
            g.DrawPath(pen, path);
        }
        g.SmoothingMode = previous;
    }
}
"@

$script:ballForm = $null
$script:ballX = 0
$script:ballY = 0
$script:ballSize = 84
$script:ballMargin = 13
$script:ballWindow = 110
$script:ballWindowHeight = 110
$script:ballHover = $false
$script:ballDrag = $null
$script:menuOpen = $false
$script:ballMenu = $null
$script:pendingBallAction = $null
$script:ballActionTimer = $null
$script:ballMenuActions = $null
$script:ballMenuResetItem = $null
$script:ballMenuScale = 0.0
$script:ballImage = $null
$script:ballImageStream = $null
$script:ballImageScaled = $null
$script:ballImagePath = ''
$script:shadowForm = $null
$script:shadowMargin = 18
$script:panelForm = $null
$script:dpiScale = 1.0
$script:panelWidth = 440
$script:panelHeight = 524
$script:panelTail = 24
$script:panelVisible = $false
$script:panelAnimating = $false
$script:panelAnimTimer = $null
$script:panelAnimFrom = 24
$script:panelAnimTo = 524
$script:panelAnimStart = 0
$script:panelAnimDone = $null
$script:panelRevealTimer = $null
$script:panelX = 0
$script:panelY = 0
$script:previewImage = $null
$script:captureImageBase64 = $null
$script:web = $null
$script:webCore = $null
$script:webEnvironment = $null
$script:pageReady = $false
$script:webStarted = $false
$script:webHintShown = $false
$script:panelUri = ''
$script:panelImageWidth = 0
$script:panelImageHeight = 0
$script:pendingPanelHeight = 0
$script:capturePublished = $false
$script:hostQueue = $null
$script:hostReader = $null
$script:hostTimer = $null
$script:parentTimer = $null
$script:tooltip = $null
$script:frozen = $null
$script:hud = $null
$script:frozenImage = $null
$script:virtual = $null
$script:captureBitmap = $null
$script:selectStart = $null
$script:selecting = $false
$script:busy = $false

function New-RoundedPath([int]$x, [int]$y, [int]$width, [int]$height, [int]$radius) {
  $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
  $diameter = $radius * 2
  if ($diameter -gt $width) { $diameter = $width }
  if ($diameter -gt $height) { $diameter = $height }
  if ($diameter -lt 2) { $diameter = 2 }
  $path.AddArc($x, $y, $diameter, $diameter, 180, 90)
  $path.AddArc($x + $width - $diameter, $y, $diameter, $diameter, 270, 90)
  $path.AddArc($x + $width - $diameter, $y + $height - $diameter, $diameter, $diameter, 0, 90)
  $path.AddArc($x, $y + $height - $diameter, $diameter, $diameter, 90, 90)
  $path.CloseFigure()
  return $path
}

function Draw-WidgetIcon {
  param(
    [System.Drawing.Graphics]$graphics,
    [int]$size,
    [System.Drawing.Color]$color = [System.Drawing.Color]::FromArgb(255, 77, 163, 255),
    [double]$weight = 0.045,
    [System.Drawing.Color]$dotColor = [System.Drawing.Color]::FromArgb(255, 77, 163, 255)
  )
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $accent = $color
  $penWidth = [single]([Math]::Max(1.6, $size * $weight))
  $pen = [System.Drawing.Pen]::new($accent, $penWidth)
  $dot = [System.Drawing.SolidBrush]::new($dotColor)
  try {
    $radius = [single]($size * 0.18)
    $center = [single]($size / 2)
    $graphics.DrawEllipse($pen, ($center - $radius), ($center - $radius), ($radius * 2), ($radius * 2))
    $graphics.DrawLine(
      $pen,
      ($center + $radius * 0.5),
      ($center + $radius * 0.5),
      ($center + $radius * 1.4),
      ($center + $radius * 1.4)
    )
    $dotRadius = [single]($radius * 0.3)
    $graphics.FillEllipse($dot, ($center - $dotRadius), ($center - $dotRadius), ($dotRadius * 2), ($dotRadius * 2))
  } finally {
    $dot.Dispose()
    $pen.Dispose()
  }
}

function New-BallBitmap {
  $bitmap = [System.Drawing.Bitmap]::new(
    $script:ballWindow,
    $script:ballWindowHeight,
    [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb
  )
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    if ($null -ne $script:ballImage) {
      $custom = Get-CustomBallBitmap
      if ($null -ne $custom) { $graphics.DrawImageUnscaled($custom, 0, 0) }
    } else {
      Draw-DefaultBall $graphics
    }
  } finally {
    $graphics.Dispose()
  }
  return $bitmap
}

function Draw-DefaultBall([System.Drawing.Graphics]$graphics) {
  $size = $script:ballSize
  $margin = $script:ballMargin
  if ($size -le 0) { return }
  $radius = [single]($size / 2)
  $centerX = [single]($margin + $radius)
  $centerY = [single]($margin + $radius)

  for ($i = 18; $i -ge 1; $i--) {
    $maxR = [single](($script:ballWindow / 2) - 1)
    $inner = [single]($radius * 1.02)
    $rr = $inner + (($maxR - $inner) * ($i / 18.0))
    if ($rr -gt $maxR) { $rr = $maxR }
    $shadow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(4, 0, 0, 0))
    try {
      $graphics.FillEllipse($shadow, ($centerX - $rr), ($centerY - $rr + ($radius * 0.10)), ($rr * 2), ($rr * 2))
    } finally {
      $shadow.Dispose()
    }
  }

  $bodyRect = [System.Drawing.RectangleF]::new($margin, $margin, ($size - 1), ($size - 1))
  $top = [System.Drawing.Color]::FromArgb(255, 52, 62, 84)
  $bottom = [System.Drawing.Color]::FromArgb(255, 20, 25, 36)
  if ($script:ballHover) {
    $top = [System.Drawing.Color]::FromArgb(255, 66, 78, 104)
    $bottom = [System.Drawing.Color]::FromArgb(255, 28, 34, 48)
  }
  $gradient = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    $bodyRect,
    $top,
    $bottom,
    [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal
  )
  try {
    $graphics.FillEllipse($gradient, $bodyRect)
  } finally {
    $gradient.Dispose()
  }

  $inset = [single]($size * 0.09)
  $hiRect = [System.Drawing.RectangleF]::new(
    ($margin + $inset),
    ($margin + $inset),
    ($size - 1 - 2 * $inset),
    ($size - 1 - 2 * $inset)
  )
  $highlight = [System.Drawing.Pen]::new(
    [System.Drawing.Color]::FromArgb(48, 255, 255, 255),
    [single]([Math]::Max(1.0, $size * 0.020))
  )
  try {
    $graphics.DrawEllipse($highlight, $hiRect)
  } finally {
    $highlight.Dispose()
  }

  $border = [System.Drawing.Pen]::new(
    [System.Drawing.Color]::FromArgb(255, 74, 88, 116),
    [single]([Math]::Max(1.0, $size * 0.0175))
  )
  try {
    $graphics.DrawEllipse($border, $bodyRect)
  } finally {
    $border.Dispose()
  }

  $graphics.TranslateTransform($margin, $margin)
  try {
    Draw-WidgetIcon $graphics $size ([System.Drawing.Color]::FromArgb(255, 238, 244, 255)) 0.048 ([System.Drawing.Color]::FromArgb(255, 108, 186, 255))
  } finally {
    $graphics.ResetTransform()
  }
}

function Get-CustomBallBitmap {
  if ($null -ne $script:ballImageScaled) { return $script:ballImageScaled }
  $image = $script:ballImage
  if ($null -eq $image) { return $null }

  $size = $script:ballSize
  $margin = $script:ballMargin
  if ($size -le 0) { return $null }

  $bitmap = [System.Drawing.Bitmap]::new(
    $script:ballWindow,
    $script:ballWindowHeight,
    [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb
  )
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $radius = [single]($size / 2)
    $centerX = [single]($margin + $radius)
    $centerY = [single]($margin + $radius)
    $maxR = [single](($script:ballWindow / 2) - 1)
    for ($i = 18; $i -ge 1; $i--) {
      $inner = [single]($radius * 1.02)
      $rr = $inner + (($maxR - $inner) * ($i / 18.0))
      if ($rr -gt $maxR) { $rr = $maxR }
      $shadow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(4, 0, 0, 0))
      try {
        $graphics.FillEllipse($shadow, ($centerX - $rr), ($centerY - $rr + ($radius * 0.10)), ($rr * 2), ($rr * 2))
      } finally {
        $shadow.Dispose()
      }
    }

    $scale = [Math]::Min(($size / [double]$image.Width), ($size / [double]$image.Height))
    $width = [Math]::Max(1, [int][Math]::Round($image.Width * $scale))
    $height = [Math]::Max(1, [int][Math]::Round($image.Height * $scale))
    $x = $margin + [int][Math]::Floor(($size - $width) / 2)
    $y = $margin + [int][Math]::Floor(($size - $height) / 2)
    $graphics.DrawImage($image, [System.Drawing.Rectangle]::new($x, $y, $width, $height))
  } finally {
    $graphics.Dispose()
  }

  $script:ballImageScaled = $bitmap
  return $bitmap
}

function Get-BallImagePath {
  if (-not [string]::IsNullOrEmpty($script:ballImagePath)) { return $script:ballImagePath }
  $dir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'dsh-glance'
  try {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  } catch {
    $dir = Join-Path (Join-Path ([System.IO.Path]::GetTempPath()) 'dsh-glance')
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $script:ballImagePath = Join-Path $dir 'ball.png'
  return $script:ballImagePath
}

function Set-BallImageFree {
  if ($null -ne $script:ballImageScaled) {
    $script:ballImageScaled.Dispose()
    $script:ballImageScaled = $null
  }
  if ($null -ne $script:ballImage) {
    $script:ballImage.Dispose()
    $script:ballImage = $null
  }
  if ($null -ne $script:ballImageStream) {
    $script:ballImageStream.Dispose()
    $script:ballImageStream = $null
  }
}

function Load-BallImage {
  Set-BallImageFree
  $path = Get-BallImagePath
  if (-not (Test-Path -LiteralPath $path)) { return $false }
  try {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $stream = [System.IO.MemoryStream]::new($bytes, $false)
    $image = [System.Drawing.Image]::FromStream($stream)
    $script:ballImageStream = $stream
    $script:ballImage = $image
    return $true
  } catch {
    Set-BallImageFree
    Write-Log ('ball image load failed: ' + $_.Exception.Message)
    return $false
  }
}

function Send-PanelSkinState {
  Send-PanelMessage @{ type = 'skin-state'; custom = ($null -ne $script:ballImage) }
}

function Select-BallImage {
  $dialog = [System.Windows.Forms.OpenFileDialog]::new()
  try {
    $dialog.Title = '选择悬浮球图片（建议 PNG，带透明背景）'
    $dialog.Filter = '图片 (*.png;*.webp;*.bmp;*.jpg;*.jpeg)|*.png;*.webp;*.bmp;*.jpg;*.jpeg'
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false
    $owner = $script:panelForm
    if ($null -ne $owner -and $owner.Visible) {
      $result = $dialog.ShowDialog($owner)
    } else {
      $result = $dialog.ShowDialog()
    }
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $source = $dialog.FileName
    if ([string]::IsNullOrEmpty($source)) { return }
    $target = Get-BallImagePath
    if (-not [string]::Equals($source, $target, [System.StringComparison]::OrdinalIgnoreCase)) {
      [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($source))
    }
    if (-not (Load-BallImage)) {
      [System.Windows.Forms.MessageBox]::Show(
        '这张图片无法读取，换一张 PNG 试试。',
        '一瞥',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
      ) | Out-Null
      return
    }
    Update-Ball
    Send-PanelSkinState
    Write-Log ('ball image set from ' + $source)
  } catch {
    Write-Log ('ball image set failed: ' + $_.Exception.Message)
    [System.Windows.Forms.MessageBox]::Show(
      ('设置悬浮球外观失败：' + $_.Exception.Message),
      '一瞥',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
  } finally {
    $dialog.Dispose()
  }
}

function Reset-BallImage {
  $path = Get-BallImagePath
  try {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
  } catch {
    Write-Log ('ball image remove failed: ' + $_.Exception.Message)
  }
  Set-BallImageFree
  Update-Ball
  Send-PanelSkinState
  Write-Log 'ball image reset'
}

function New-BallMenuEntry([string]$text, [bool]$enabled, [scriptblock]$onClick) {
  $item = [System.Windows.Forms.ToolStripMenuItem]::new($text)
  $item.Enabled = $enabled
  $item.ForeColor = [System.Drawing.Color]::FromArgb(232, 238, 252)
  $item.AutoSize = $true
  $padX = [int](20 * $script:dpiScale)
  $padTop = [int](1 * $script:dpiScale)
  $padBottom = [int](1 * $script:dpiScale)
  $item.Padding = [System.Windows.Forms.Padding]::new($padX, $padTop, 0, $padBottom)
  if ($null -ne $onClick) {
    if ($null -eq $script:ballMenuActions) { $script:ballMenuActions = @{} }
    $script:ballMenuActions[$item] = $onClick
    $item.Add_Click({
      param($sender, $e)
      Invoke-BallMenuAction $script:ballMenuActions[$sender]
    })
  }
  return $item
}

function Invoke-BallMenuAction([scriptblock]$action) {
  if ($null -eq $action -or $null -eq $script:ballForm) { return }
  $script:pendingBallAction = $action
  if ($null -ne $script:ballActionTimer) { return }
  $timer = [System.Windows.Forms.Timer]::new()
  $timer.Interval = 80
  $timer.Add_Tick({
    param($sender, $e)
    $sender.Stop()
    try { $sender.Dispose() } catch { }
    $script:ballActionTimer = $null
    $menu = $script:ballMenu
    if ($null -ne $menu) {
      try { if ($menu.Visible) { $menu.Close() } } catch { }
    }
    $pending = $script:pendingBallAction
    $script:pendingBallAction = $null
    if ($null -ne $pending) {
      try { & $pending } catch { Write-Log ('menu action failed: ' + $_.Exception.Message) }
    }
  })
  $script:ballActionTimer = $timer
  $timer.Start()
}

function Get-BallMenu {
  $scale = $script:dpiScale
  if ($null -eq $scale -or $scale -le 0) { $scale = 1.0 }
  if ($null -ne $script:ballMenu) {
    if ([Math]::Abs($script:ballMenuScale - $scale) -lt 0.01) { return $script:ballMenu }
    Write-Log ('ball menu rebuild scale ' + $script:ballMenuScale + ' -> ' + $scale)
    try { $script:ballMenu.Dispose() } catch { }
    $script:ballMenu = $null
    $script:ballMenuResetItem = $null
  }
  $script:ballMenuActions = @{}

  $menu = [System.Windows.Forms.ContextMenuStrip]::new()
  $menu.ShowImageMargin = $false
  $menu.ShowCheckMargin = $false
  $menu.DropShadowEnabled = $true
  $menu.BackColor = [System.Drawing.Color]::FromArgb(27, 33, 48)
  $menu.ForeColor = [System.Drawing.Color]::FromArgb(232, 238, 252)
  $menu.Font = [System.Drawing.Font]::new('Microsoft YaHei UI', [float](8.5 * $scale))
  $menu.Renderer = [ScreenSnapMenuRenderer]::new([ScreenSnapMenuColors]::new(), [float]$scale)
  $edge = [int](4 * $scale)
  $menu.Padding = [System.Windows.Forms.Padding]::new($edge, $edge, $edge, $edge)

  $menu.Items.Add((New-BallMenuEntry '更换外观…' $true { Select-BallImage })) | Out-Null
  $script:ballMenuResetItem = New-BallMenuEntry '恢复默认外观' $false { Reset-BallImage }
  $menu.Items.Add($script:ballMenuResetItem) | Out-Null
  $menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new()) | Out-Null
  $menu.Items.Add((New-BallMenuEntry '退出' $true { Close-Widget })) | Out-Null

  $menu.Add_Closed({ OnBallMenuClosed })
  $menu.Add_Opened({
    param($sender, $e)
    try {
      if ($null -eq $sender -or $sender.Width -le 0 -or $sender.Height -le 0) { return }
      $radius = [float](10 * $script:dpiScale)
      $rect = [System.Drawing.RectangleF]::new(0, 0, [float]$sender.Width, [float]$sender.Height)
      $path = [ScreenSnapMenuRenderer]::RoundedRect($rect, $radius)
      try {
        $sender.Region = [System.Drawing.Region]::new($path)
      } finally {
        $path.Dispose()
      }
    } catch {
      Write-Log ('ball menu region failed: ' + $_.Exception.Message)
    }
  })
  $script:ballMenu = $menu
  $script:ballMenuScale = $scale
  return $menu
}

function OnBallMenuClosed {
  $script:menuOpen = $false
  try {
    if ($null -eq $script:ballForm) { return }
    $cursor = [System.Windows.Forms.Cursor]::Position
    $left = $script:ballX + $script:ballMargin
    $top = $script:ballY + $script:ballMargin
    $script:ballHover = ($cursor.X -ge $left -and $cursor.X -le ($left + $script:ballSize) -and
      $cursor.Y -ge $top -and $cursor.Y -le ($top + $script:ballSize))
    Update-Ball
  } catch {
    Write-Log ('ball menu close failed: ' + $_.Exception.Message)
  }
}

function Show-BallMenu {
  if ($null -eq $script:ballForm) { return }
  $existing = $script:ballMenu
  if ($null -ne $existing -and $existing.Visible) { return }
  $script:menuOpen = $false
  try {
    $menu = Get-BallMenu
    if ($null -ne $script:ballMenuResetItem) {
      $script:ballMenuResetItem.Enabled = ($null -ne $script:ballImage)
    }
    $size = $menu.GetPreferredSize([System.Drawing.Size]::Empty)
    $center = [System.Drawing.Point]::new(
      [int]($script:ballX + $script:ballSize / 2),
      [int]($script:ballY + $script:ballSize / 2)
    )
    $area = [System.Windows.Forms.Screen]::FromPoint($center).WorkingArea
    $gap = [int](4 * $script:dpiScale)
    $x = $script:ballX + $script:ballSize + $gap
    $y = $script:ballY
    if (($x + $size.Width) -gt ($area.Right - $gap)) { $x = $script:ballX - $size.Width - $gap }
    if ($x -lt ($area.Left + $gap)) { $x = $area.Left + $gap }
    if (($y + $size.Height) -gt ($area.Bottom - $gap)) { $y = $area.Bottom - $gap - $size.Height }
    if ($y -lt ($area.Top + $gap)) { $y = $area.Top + $gap }

    $script:menuOpen = $true
    $menu.Show([System.Drawing.Point]::new($x, $y))
    [ScreenSnapNative]::SetForegroundWindow($menu.Handle) | Out-Null
    Write-Log ('ball menu opened at ' + $x + ',' + $y)
  } catch {
    $script:menuOpen = $false
    Write-Log ('ball menu failed: ' + $_.Exception.Message)
  }
}

function Update-Ball {
  if ($null -eq $script:ballForm) { return }
  $bitmap = New-BallBitmap
  try {
    [ScreenSnapNative]::Apply(
      $script:ballForm.Handle,
      $bitmap,
      ($script:ballX - $script:ballMargin),
      ($script:ballY - $script:ballMargin)
    ) | Out-Null
  } finally {
    $bitmap.Dispose()
  }
}

function Get-PanelPlacement([System.Drawing.Rectangle]$area, [int]$width, [int]$height) {
  $gap = 12
  $pad = 8
  $left = $area.Left + $pad
  $top = $area.Top + $pad
  $right = $area.Right - $pad
  $bottom = $area.Bottom - $pad

  $ballX = $script:ballX
  $ballY = $script:ballY
  $size = $script:ballSize

  if (($ballX + $size) -gt $right) { $ballX = $right - $size }
  if ($ballX -lt $left) { $ballX = $left }
  if (($ballY + $size) -gt $bottom) { $ballY = $bottom - $size }
  if ($ballY -lt $top) { $ballY = $top }

  $candidates = @(
    @{ x = ($ballX - $gap - $width); y = $ballY },
    @{ x = ($ballX + $size - $width); y = ($ballY + $size + $gap) },
    @{ x = ($ballX + $size - $width); y = ($ballY - $gap - $height) }
  )

  $chosen = $null
  foreach ($candidate in $candidates) {
    if ($candidate.x -lt $left) { continue }
    if (($candidate.x + $width) -gt $right) { continue }
    if ($candidate.y -lt $top) { continue }
    if (($candidate.y + $height) -gt $bottom) { continue }
    $chosen = $candidate
    break
  }

  if ($null -eq $chosen) {
    $x = [Math]::Min([Math]::Max($left, ($ballX + $size - $width)), ($right - $width))
    $y = $ballY + $size + $gap
    if (($y + $height) -gt $bottom) {
      $y = $bottom - $height
      $ballY = $y - $gap - $size
      if ($ballY -lt $top) {
        $ballY = $top
        $y = $ballY + $size + $gap
      }
      if (($y + $height) -gt $bottom) { $y = $bottom - $height }
      if ($y -lt $top) { $y = $top }
    }
    $chosen = @{ x = $x; y = $y }
  }

  return @{
    x = [int]$chosen.x
    y = [int]$chosen.y
    ballX = [int]$ballX
    ballY = [int]$ballY
  }
}

function Move-PanelToBall {
  if ($null -eq $script:panelForm -or -not $script:panelForm.Visible) { return }
  $screen = [System.Windows.Forms.Screen]::FromPoint(
    [System.Drawing.Point]::new(($script:ballX + 42), ($script:ballY + 42))
  )
  $area = $screen.WorkingArea

  $placement = Get-PanelPlacement $area $script:panelWidth $script:panelForm.Height
  if ($placement.ballX -ne $script:ballX -or $placement.ballY -ne $script:ballY) {
    $script:ballX = $placement.ballX
    $script:ballY = $placement.ballY
    Update-Ball
  }

  $script:panelX = $placement.x
  $script:panelY = $placement.y
  $script:panelForm.Bounds = [System.Drawing.Rectangle]::new(
    $script:panelX,
    $script:panelY,
    $script:panelWidth,
    $script:panelForm.Height
  )
  Update-Shadow $script:panelWidth $script:panelForm.Height
}

function Set-PanelRegion {
  if ($null -eq $script:panelForm) { return }
  Set-RoundedRegion $script:panelForm 16
}

function Update-Shadow([int]$width, [int]$height) {
  if ($null -eq $script:shadowForm -or -not $script:shadowForm.Visible) { return }
  $margin = $script:shadowMargin
  $bitmap = [System.Drawing.Bitmap]::new(
    ($width + $margin * 2),
    ($height + $margin * 2),
    [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb
  )
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    for ($i = 0; $i -lt 4; $i++) {
      $alpha = 10 - ($i * 2)
      if ($alpha -lt 2) { $alpha = 2 }
      $left = $margin - $i
      $top = $margin + 4 - $i
      $shadowWidth = $width + $i * 2
      $shadowHeight = $height + $i * 2
      $path = New-RoundedPath $left $top $shadowWidth $shadowHeight (18 + $i)
      try {
        $brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($alpha, 0, 0, 0))
        try {
          $graphics.FillPath($brush, $path)
        } finally {
          $brush.Dispose()
        }
      } finally {
        $path.Dispose()
      }
    }
  } finally {
    $graphics.Dispose()
  }
  try {
    [ScreenSnapNative]::Apply(
      $script:shadowForm.Handle,
      $bitmap,
      ($script:panelX - $margin),
      ($script:panelY - $margin + 4)
    ) | Out-Null
  } finally {
    $bitmap.Dispose()
  }
}

function Show-Shadow {
  if ($null -eq $script:shadowForm) {
    $shadow = [ScreenSnapShadowForm]::new()
    $shadow.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $shadow.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $shadow.Size = [System.Drawing.Size]::new(1, 1)
    $shadow.TopMost = $true
    $shadow.ShowInTaskbar = $false
    $script:shadowForm = $shadow
    $shadow.Show()
  }
  if (-not $script:shadowForm.Visible) { $script:shadowForm.Show() }
  Update-Shadow $script:panelWidth 64
}

function Hide-Shadow {
  if ($null -ne $script:shadowForm -and $script:shadowForm.Visible) {
    $script:shadowForm.Hide()
  }
}

function Set-RoundedRegion([System.Windows.Forms.Control]$control, [int]$radius) {
  $path = New-RoundedPath 0 0 $control.Width $control.Height $radius
  try {
    $region = [System.Drawing.Region]::new($path)
    $old = $control.Region
    $control.Region = $region
    if ($null -ne $old) { $old.Dispose() }
  } finally {
    $path.Dispose()
  }
}

function Stop-PanelReveal {
  if ($null -ne $script:panelRevealTimer) {
    try {
      $script:panelRevealTimer.Stop()
      $script:panelRevealTimer.Dispose()
    } catch { }
    $script:panelRevealTimer = $null
  }
}

function Stop-PanelAnimation {
  if ($null -ne $script:panelAnimTimer) {
    try {
      $script:panelAnimTimer.Stop()
      $script:panelAnimTimer.Dispose()
    } catch { }
    $script:panelAnimTimer = $null
  }
  $script:panelAnimating = $false
  $script:panelAnimDone = $null
}

function Start-PanelAnimation([int]$fromHeight, [int]$toHeight, [scriptblock]$done) {
  Stop-PanelAnimation
  $script:panelAnimFrom = $fromHeight
  $script:panelAnimTo = $toHeight
  $script:panelAnimStart = [Environment]::TickCount
  $script:panelAnimDone = $done
  $script:panelAnimating = $true
  $timer = [System.Windows.Forms.Timer]::new()
  $timer.Interval = 15
  $script:panelAnimTimer = $timer
  $timer.Add_Tick({
    if ($null -eq $script:panelAnimTimer) { return }
    $elapsed = [Environment]::TickCount - $script:panelAnimStart
    $progress = [Math]::Min(1.0, $elapsed / 180.0)
    $eased = 1.0 - [Math]::Pow(1.0 - $progress, 3.0)
    $height = [int]($script:panelAnimFrom + ($script:panelAnimTo - $script:panelAnimFrom) * $eased)
    if ($height -lt $script:panelTail) { $height = $script:panelTail }
    $script:panelForm.Bounds = [System.Drawing.Rectangle]::new(
      $script:panelX,
      $script:panelY,
      $script:panelWidth,
      $height
    )
    Set-PanelRegion
    Update-Shadow $script:panelWidth $height
    $script:panelForm.Invalidate()

    if ($progress -ge 1.0) {
      $script:panelAnimTimer.Stop()
      $script:panelAnimTimer.Dispose()
      $script:panelAnimTimer = $null
      $script:panelAnimating = $false
      $finalHeight = [Math]::Max($script:panelTail, $script:panelAnimTo)
      $script:panelForm.Bounds = [System.Drawing.Rectangle]::new(
        $script:panelX,
        $script:panelY,
        $script:panelWidth,
        $finalHeight
      )
      Set-PanelRegion
      Update-Shadow $script:panelWidth $finalHeight
      $script:panelForm.Invalidate()
      $callback = $script:panelAnimDone
      $script:panelAnimDone = $null
      if ($null -ne $callback) { & $callback }
    }
  })
  $timer.Start()
}

function Clear-PreviewData {
  if ($null -ne $script:previewImage) {
    $script:previewImage.Dispose()
    $script:previewImage = $null
  }
  $script:captureImageBase64 = $null
  $script:panelImageWidth = 0
  $script:panelImageHeight = 0
  $script:capturePublished = $false
}

function Show-Ball {
  if ($null -eq $script:ballForm) { return }
  $null = $script:ballForm.Handle
  Update-Ball
  if (-not $script:ballForm.Visible) { $script:ballForm.Show() }
  $script:ballForm.TopMost = $true
  $script:ballForm.BringToFront()
}

function Hide-Ball {
  if ($null -ne $script:ballForm) { $script:ballForm.Hide() }
}

function Show-WebViewHint([string]$detail) {
  Write-Log ('webview unavailable: ' + $detail)
  if ($script:webHintShown) { return }
  $script:webHintShown = $true
  $nl = [Environment]::NewLine
  $text = '一瞥的悬浮面板无法启动。' + $nl + $nl +
    '最常见的原因是缺少 Microsoft Edge WebView2 运行时，' + $nl +
    '安装后重新打开开关即可：' + $nl +
    'https://developer.microsoft.com/microsoft-edge/webview2/' + $nl + $nl +
    '详细信息已写入日志：' + $nl + [string]$script:logPath
  try {
    [System.Windows.Forms.MessageBox]::Show(
      $text,
      '一瞥 / Glance',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
  } catch {
    Write-Log ('webview hint dialog failed: ' + $_.Exception.Message)
  }
  Collapse-Panel -Immediate
}

function Convert-ImageToBase64([System.Drawing.Image]$image) {
  $stream = [System.IO.MemoryStream]::new()
  try {
    $image.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    return [System.Convert]::ToBase64String($stream.ToArray())
  } finally {
    $stream.Dispose()
  }
}

function Write-Log([string]$text) {
  try {
    if ([string]::IsNullOrEmpty($script:logPath)) {
      $script:logPath = Join-Path ([System.IO.Path]::GetTempPath()) 'glance-widget.log'
      try { [System.IO.File]::WriteAllText($script:logPath, '') } catch { }
    }
    $line = ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $text) + [Environment]::NewLine
    [System.IO.File]::AppendAllText($script:logPath, $line, [System.Text.UTF8Encoding]::new($false))
  } catch { }
}

function Send-PanelMessage($message) {
  $json = $null
  try { $json = $message | ConvertTo-Json -Compress -Depth 8 } catch { return }
  if (-not $script:pageReady) {
    if ($null -eq $script:pendingPanelMessages) {
      $script:pendingPanelMessages = New-Object System.Collections.Generic.List[string]
    }
    [void]$script:pendingPanelMessages.Add($json)
    return
  }
  if ($null -eq $script:web) { return }
  $core = $script:web.CoreWebView2
  if ($null -eq $core) { return }
  try { $core.PostWebMessageAsJson($json) } catch {
    Write-Log ('panel message failed: ' + $_.Exception.Message)
  }
}

function Flush-PanelMessages {
  if (-not $script:pageReady) { return }
  if ($null -eq $script:pendingPanelMessages -or $script:pendingPanelMessages.Count -eq 0) { return }
  if ($null -eq $script:web) { return }
  $core = $script:web.CoreWebView2
  if ($null -eq $core) { return }
  foreach ($json in $script:pendingPanelMessages) {
    try { $core.PostWebMessageAsJson($json) } catch {
      Write-Log ('panel flush failed: ' + $_.Exception.Message)
    }
  }
  $script:pendingPanelMessages.Clear()
}

function Send-PanelInit {
  if (-not $script:pageReady) { return }
  $screen = [System.Windows.Forms.Screen]::FromPoint(
    [System.Drawing.Point]::new(($script:ballX + 42), ($script:ballY + 42))
  )
  $area = $screen.WorkingArea
  $scale = $script:dpiScale
  if ($null -eq $scale -or $scale -le 0) { $scale = 1.0 }
  $maxHeightDip = [Math]::Min([int]($area.Height * 0.7), [int](640 * $scale))
  $maxWidthDip = [Math]::Min([int]($area.Width * 0.8), [int](560 * $scale))
  Send-PanelMessage @{
    type = 'init'
    maxHeight = [int]($maxHeightDip / $scale)
    maxWidth = [int]($maxWidthDip / $scale)
    custom = ($null -ne $script:ballImage)
  }
}

function Send-PanelCapture {
  if (-not $script:pageReady) { return }
  if ($script:capturePublished) { return }
  if ([string]::IsNullOrEmpty($script:captureImageBase64)) { return }
  Write-Log ('capture->panel len=' + $script:captureImageBase64.Length)
  Send-PanelMessage @{
    type = 'capture'
    imageBase64 = $script:captureImageBase64
    width = $script:panelImageWidth
    height = $script:panelImageHeight
  }
  $script:capturePublished = $true
}

function Send-HostMessage([hashtable]$message) {
  $payload = $message | ConvertTo-Json -Compress
  [Console]::Out.WriteLine($payload)
  [Console]::Out.Flush()
}

function Send-Capture([string]$note) {
  if ([string]::IsNullOrEmpty($script:captureImageBase64)) {
    Send-PanelMessage @{ type = 'analysis-error'; message = '截图数据为空，请重新框选。' }
    return
  }
  Send-HostMessage @{ type = 'capture'; imageBase64 = $script:captureImageBase64; note = $note }
}

function Send-Followup([string]$text) {
  $value = ([string]$text).Trim()
  if ([string]::IsNullOrEmpty($value)) { return }
  Send-HostMessage @{ type = 'followup'; text = $value }
}

function Send-Abort {
  Send-HostMessage @{ type = 'abort' }
}

function Move-BallClearOfPanel([System.Drawing.Rectangle]$rect) {
  if ($null -eq $script:ballForm) { return }
  $size = $script:ballSize
  $ball = [System.Drawing.Rectangle]::new($script:ballX, $script:ballY, $size, $size)
  if (-not $ball.IntersectsWith($rect)) { return }
  $gap = 12
  $screen = [System.Windows.Forms.Screen]::FromPoint(
    [System.Drawing.Point]::new(($rect.Left + 10), ($rect.Top + 10))
  )
  $area = $screen.WorkingArea
  $above = $rect.Top - $gap - $size
  $below = $rect.Bottom + $gap
  if ($above -ge $area.Top + 8) {
    $script:ballY = $above
  } elseif (($below + $size) -le $area.Bottom - 8) {
    $script:ballY = $below
  } else {
    return
  }
  Update-Ball
}

function Set-PanelHeight([int]$value) {
  if ($null -eq $script:panelForm -or -not $script:panelVisible) { return }
  $screen = [System.Windows.Forms.Screen]::FromPoint(
    [System.Drawing.Point]::new(($script:ballX + 42), ($script:ballY + 42))
  )
  $area = $screen.WorkingArea
  $scale = $script:dpiScale
  if ($null -eq $scale -or $scale -le 0) { $scale = 1.0 }
  $minHeight = [int](200 * $scale)
  $max = [Math]::Min([int]($area.Height * 0.7), [int](640 * $scale))
  if ($max -lt $minHeight) { $max = $minHeight }
  $target = [Math]::Max($minHeight, [Math]::Min([int]($value * $scale), $max))
  if ($script:panelAnimating) {
    $script:pendingPanelHeight = $value
    return
  }
  if ([Math]::Abs($script:panelForm.Height - $target) -le 2) { return }
  $bottomLimit = $area.Bottom - 8
  $top = $script:panelY
  if (($top + $target) -gt $bottomLimit) { $top = $bottomLimit - $target }
  if ($top -lt $area.Top + 8) { $top = $area.Top + 8 }
  $script:panelY = $top
  $script:panelForm.Bounds = [System.Drawing.Rectangle]::new(
    $script:panelX,
    $top,
    $script:panelWidth,
    $target
  )
  Move-BallClearOfPanel ([System.Drawing.Rectangle]::new($script:panelX, $top, $script:panelWidth, $target))
  Set-PanelRegion
  Update-Shadow $script:panelWidth $target
}

function Handle-PanelMessage([string]$json) {
  $message = $null
  try { $message = $json | ConvertFrom-Json } catch { return }
  if ($null -eq $message -or $null -eq $message.type) { return }
  if ([string]$message.type -ne 'height') { Write-Log ('panel-msg ' + [string]$message.type) }
  switch ([string]$message.type) {
    'ready' {
      $script:pageReady = $true
      Send-PanelInit
      Send-PanelCapture
      Flush-PanelMessages
    }
    'height' {
      if ($null -ne $message.height) { Set-PanelHeight ([int]$message.height) }
    }
    'send' {
      Send-Capture ([string]$message.note)
    }
    'followup' {
      Send-Followup ([string]$message.text)
    }
    'stop' {
      Send-Abort
    }
    'skin' {
      if ($null -ne $script:ballImage) { Reset-BallImage } else { Select-BallImage }
    }
    'drag' {
      if ($null -ne $script:panelForm) {
        [ScreenSnapNative]::ReleaseCapture() | Out-Null
        [ScreenSnapNative]::SendMessage($script:panelForm.Handle, 0xA1, [IntPtr]::new(2), [IntPtr]::Zero) | Out-Null
      }
    }
    'minimize' { Collapse-Panel }
    'rescan' {
      Collapse-Panel -Immediate
      Start-Capture
    }
    'close' { Collapse-Panel -Immediate }
  }
}

function Handle-HostLine([string]$json) {
  $message = $null
  try { $message = $json | ConvertFrom-Json } catch { return }
  if ($null -eq $message -or $null -eq $message.type) { return }
  if ([string]$message.type -ne 'analysis-delta') { Write-Log ('host-line ' + [string]$message.type) }
  switch ([string]$message.type) {
    'analysis-delta' { Send-PanelMessage @{ type = 'analysis-delta'; text = [string]$message.text } }
    'analysis-replace' { Send-PanelMessage @{ type = 'analysis-replace'; text = [string]$message.text } }
    'analysis-done' { Send-PanelMessage @{ type = 'analysis-done' } }
    'analysis-stopped' { Send-PanelMessage @{ type = 'analysis-stopped' } }
    'analysis-error' { Send-PanelMessage @{ type = 'analysis-error'; message = [string]$message.message } }
    'thread' {
      Send-PanelMessage @{
        type = 'thread'
        sessionId = [string]$message.sessionId
        title = [string]$message.title
        turns = [int]$message.turns
        startedAt = $message.startedAt
      }
    }
  }
}

function Start-HostReader {
  if ($null -ne $script:hostReader) { return }
  $script:hostQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
  $readerScript = {
    param($queue)
    $stream = $null
    try {
      $stream = [Console]::OpenStandardInput()
      $textReader = New-Object System.IO.StreamReader($stream, (New-Object System.Text.UTF8Encoding($false)))
      while ($true) {
        $line = $null
        try { $line = $textReader.ReadLine() } catch { break }
        if ($null -eq $line) { break }
        if ($line.Trim().Length -gt 0) { [void]$queue.Enqueue($line) }
      }
    } catch { } finally {
      if ($null -ne $stream) { try { $stream.Dispose() } catch { } }
    }
  }
  $reader = [powershell]::Create()
  $null = $reader.AddScript($readerScript).AddArgument($script:hostQueue)
  $script:hostReader = $reader
  $null = $reader.BeginInvoke()
  $timer = [System.Windows.Forms.Timer]::new()
  $timer.Interval = 80
  $script:hostTimer = $timer
  $timer.Add_Tick({
    if ($null -eq $script:hostQueue) { return }
    $line = $null
    while ($script:hostQueue.TryDequeue([ref]$line)) {
      if ($null -ne $line) { Handle-HostLine $line }
    }
  })
  $timer.Start()
}

function Close-Widget {
  Write-Log 'Close-Widget'
  try { Stop-PanelReveal } catch { }
  try { Stop-PanelAnimation } catch { }
  try { if ($null -ne $script:panelForm) { $script:panelForm.Hide() } } catch { }
  try { Hide-Shadow } catch { }
  try { Hide-Ball } catch { }
  try { [System.Windows.Forms.Application]::DoEvents() } catch { }
  [System.Windows.Forms.Application]::Exit()
  [Environment]::Exit(0)
}

function Expand-Panel([System.Drawing.Image]$image, [string]$imageBase64) {
  if ($null -eq $script:panelForm) { return }
  Stop-PanelAnimation
  if ($null -ne $script:previewImage) { $script:previewImage.Dispose() }
  $script:previewImage = $image
  if ([string]::IsNullOrEmpty($imageBase64) -or $imageBase64 -eq 'selftest') {
    $imageBase64 = Convert-ImageToBase64 $image
  }
  $script:captureImageBase64 = $imageBase64
  Write-Log ('expand image=' + $image.Width + 'x' + $image.Height + ' b64=' + $script:captureImageBase64.Length)
  $script:panelImageWidth = $image.Width
  $script:panelImageHeight = $image.Height
  $script:capturePublished = $false

  $screen = [System.Windows.Forms.Screen]::FromPoint(
    [System.Drawing.Point]::new(($script:ballX + 42), ($script:ballY + 42))
  )
  $area = $screen.WorkingArea
  $dpiScale = 1.0
  try {
    $dpiGraphics = $script:panelForm.CreateGraphics()
    try { $dpiScale = $dpiGraphics.DpiX / 96.0 } finally { $dpiGraphics.Dispose() }
  } catch { }
  if ($dpiScale -lt 1.0) { $dpiScale = 1.0 }
  $script:dpiScale = $dpiScale
  $minPanelWidth = [int](440 * $dpiScale)
  $maxPanelWidth = [int](560 * $dpiScale)
  $screenCap = [int]($area.Width * 0.8)
  if ($maxPanelWidth -gt $screenCap) { $maxPanelWidth = $screenCap }
  if ($maxPanelWidth -lt $minPanelWidth) { $minPanelWidth = $maxPanelWidth }
  $panelWidth = [Math]::Min($maxPanelWidth, [Math]::Max($minPanelWidth, ($image.Width + 48)))
  $script:panelWidth = $panelWidth

  $initialHeight = [Math]::Min([int]($area.Height * 0.7), [int](640 * $dpiScale))
  $placement = Get-PanelPlacement $area $panelWidth $initialHeight
  $panelX = $placement.x
  $panelY = $placement.y
  if ($placement.ballX -ne $script:ballX -or $placement.ballY -ne $script:ballY) {
    $script:ballX = $placement.ballX
    $script:ballY = $placement.ballY
    Update-Ball
  }
  if ($panelY -lt $area.Top + 8) { $panelY = $area.Top + 8 }

  $script:panelX = $panelX
  $script:panelY = $panelY
  $script:panelHeight = $initialHeight
  $script:pendingPanelHeight = 0
  $script:panelForm.Bounds = [System.Drawing.Rectangle]::new($panelX, $panelY, $panelWidth, 64)
  Set-PanelRegion
  Show-Shadow
  if (-not $script:panelForm.Visible) { $script:panelForm.Show() }
  $script:panelForm.TopMost = $true
  $script:panelVisible = $true
  $script:ballForm.BringToFront()

  Start-PanelAnimation 64 $initialHeight {
    Set-PanelRegion
    if ($script:pendingPanelHeight -gt 0) {
      $pending = $script:pendingPanelHeight
      $script:pendingPanelHeight = 0
      Set-PanelHeight $pending
    }
    Send-PanelCapture
    $script:ballForm.BringToFront()
  }
  Send-PanelCapture

  Stop-PanelReveal
  $reveal = [System.Windows.Forms.Timer]::new()
  $reveal.Interval = 400
  $script:panelRevealTimer = $reveal
  $reveal.Add_Tick({
    Stop-PanelReveal
    if ($script:panelVisible -and $null -ne $script:panelForm) {
      Send-PanelCapture
      $script:ballForm.BringToFront()
    }
  })
  $reveal.Start()
}

function Collapse-Panel([switch]$Immediate) {
  if ($null -eq $script:panelForm) { return }
  Stop-PanelReveal
  Stop-PanelAnimation
  Clear-PreviewData
  $script:panelVisible = $false
  if ($Immediate) {
    $script:panelForm.Hide()
    Hide-Shadow
    return
  }
  $from = $script:panelForm.Height
  Start-PanelAnimation $from 64 {
    $script:panelForm.Hide()
    Hide-Shadow
  }
}

function Close-Frozen {
  if ($null -ne $script:hud) {
    try {
      $script:hud.Hide()
      $script:hud.Dispose()
    } catch { }
    $script:hud = $null
  }
  if ($null -ne $script:frozen) {
    try {
      $script:frozen.Hide()
      $script:frozen.Dispose()
    } catch { }
    $script:frozen = $null
  }
  if ($null -ne $script:frozenImage) {
    $script:frozenImage.Dispose()
    $script:frozenImage = $null
  }
}

function New-DimmedBitmap([System.Drawing.Bitmap]$source) {
  $copy = [System.Drawing.Bitmap]::new(
    $source.Width,
    $source.Height,
    [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb
  )
  $graphics = [System.Drawing.Graphics]::FromImage($copy)
  try {
    $graphics.DrawImageUnscaled($source, 0, 0)
    $shade = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(42, 0, 0, 0))
    try {
      $graphics.FillRectangle($shade, 0, 0, $copy.Width, $copy.Height)
    } finally {
      $shade.Dispose()
    }
  } finally {
    $graphics.Dispose()
  }
  return $copy
}

function Update-SelectionOverlay([System.Drawing.Rectangle]$rect) {
  if ($null -eq $script:hud -or $null -eq $script:virtual) { return }
  if ($rect.Width -lt 1 -or $rect.Height -lt 1) { return }

  $margin = 3
  $width = $rect.Width + ($margin * 2)
  $height = $rect.Height + ($margin * 2)
  $bitmap = [System.Drawing.Bitmap]::new(
    $width,
    $height,
    [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb
  )
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 0, 170, 255), 2)
    try {
      $graphics.DrawRectangle($pen, 1, 1, ($width - 3), ($height - 3))
    } finally {
      $pen.Dispose()
    }
  } finally {
    $graphics.Dispose()
  }

  $x = $script:virtual.Left + $rect.X - $margin
  $y = $script:virtual.Top + $rect.Y - $margin
  try {
    [ScreenSnapNative]::Apply($script:hud.Handle, $bitmap, $x, $y) | Out-Null
  } finally {
    $bitmap.Dispose()
  }
}

function Show-Frozen([System.Drawing.Bitmap]$bitmap) {
  $virtual = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $script:virtual = $virtual
  $script:captureBitmap = $bitmap
  $script:frozenImage = New-DimmedBitmap $bitmap
  $script:selecting = $false
  $script:selectStart = $null

  $frozen = [ScreenSnapFrozenForm]::new()
  $frozen.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
  $frozen.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
  $frozen.Location = $virtual.Location
  $frozen.Size = $bitmap.Size
  $frozen.TopMost = $true
  $frozen.ShowInTaskbar = $false
  $frozen.Cursor = [System.Windows.Forms.Cursors]::Cross
  $frozen.KeyPreview = $true
  $frozen.BackColor = [System.Drawing.Color]::Black
  $script:frozen = $frozen

  $frozen.Add_Paint({
    param($sender, $e)
    if ($null -ne $script:frozenImage) {
      $e.Graphics.DrawImageUnscaled($script:frozenImage, 0, 0)
    }
  })

  $frozen.Add_MouseDown({
    param($sender, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $script:selectStart = [System.Drawing.Point]::new($e.X, $e.Y)
    $script:selecting = $true
    if ($null -ne $script:hud) { $script:hud.Hide() }
    try { $script:frozen.Capture = $true } catch { }
  })

  $frozen.Add_MouseMove({
    param($sender, $e)
    if (-not $script:selecting -or $null -eq $script:selectStart) { return }
    $x = [Math]::Min($script:selectStart.X, $e.X)
    $y = [Math]::Min($script:selectStart.Y, $e.Y)
    $w = [Math]::Abs($e.X - $script:selectStart.X)
    $h = [Math]::Abs($e.Y - $script:selectStart.Y)
    if ($w -lt 1 -or $h -lt 1) { return }
    if ($null -ne $script:hud -and -not $script:hud.Visible) { $script:hud.Show() }
    Update-SelectionOverlay ([System.Drawing.Rectangle]::new($x, $y, $w, $h))
  })

  $frozen.Add_MouseUp({
    param($sender, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    if (-not $script:selecting) { return }
    $script:selecting = $false
    try { $script:frozen.Capture = $false } catch { }
    $rect = [System.Drawing.Rectangle]::new(
      [Math]::Min($script:selectStart.X, $e.X),
      [Math]::Min($script:selectStart.Y, $e.Y),
      [Math]::Abs($e.X - $script:selectStart.X),
      [Math]::Abs($e.Y - $script:selectStart.Y)
    )
    if ($rect.Width -ge 8 -and $rect.Height -ge 8) {
      Close-Frozen
      Complete-Capture $rect
    } else {
      Cancel-Capture
    }
  })

  $frozen.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
      Cancel-Capture
    }
  })

  $frozen.Show()
  $frozen.Activate()
  $frozen.Focus()

  $hud = [ScreenSnapHudForm]::new()
  $hud.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
  $hud.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
  $hud.Location = [System.Drawing.Point]::new(0, 0)
  $hud.Size = [System.Drawing.Size]::new(1, 1)
  $hud.TopMost = $true
  $hud.ShowInTaskbar = $false
  $script:hud = $hud
  $hud.Show()
  $frozen.Activate()
  $frozen.Focus()
}

function Complete-Capture([System.Drawing.Rectangle]$rect) {
  $script:busy = $false
  $bitmap = $script:captureBitmap
  $script:captureBitmap = $null
  if ($null -eq $bitmap) {
    Show-Ball
    return
  }

  $crop = $null
  $scaled = $null
  $previewImage = $null
  try {
    $rect = [System.Drawing.Rectangle]::Intersect($rect, [System.Drawing.Rectangle]::new(0, 0, $bitmap.Width, $bitmap.Height))
    if ($rect.Width -lt 4 -or $rect.Height -lt 4) {
      Show-Ball
      return
    }

    $crop = $bitmap.Clone($rect, $bitmap.PixelFormat)
    $bitmap.Dispose()
    $bitmap = $null

    $scale = [Math]::Min(1.0, [Math]::Min((1280.0 / $crop.Width), (960.0 / $crop.Height)))
    $target = $crop
    if ($scale -lt 1.0) {
      $targetWidth = [Math]::Max(1, [int]($crop.Width * $scale))
      $targetHeight = [Math]::Max(1, [int]($crop.Height * $scale))
      $scaled = [System.Drawing.Bitmap]::new($targetWidth, $targetHeight)
      $graphics = [System.Drawing.Graphics]::FromImage($scaled)
      try {
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($crop, 0, 0, $targetWidth, $targetHeight)
      } finally {
        $graphics.Dispose()
      }
      $target = $scaled
    }

    $stream = [System.IO.MemoryStream]::new()
    $target.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $stream.ToArray()
    $stream.Dispose()
    if ($bytes.Length -gt (6 * 1024 * 1024)) {
      throw '截图超过 6 MB，请框选更小的区域'
    }

    $imageBase64 = [System.Convert]::ToBase64String($bytes)

    $imageStream = [System.IO.MemoryStream]::new($bytes, $false)
    $tempImage = [System.Drawing.Image]::FromStream($imageStream)
    $previewImage = [System.Drawing.Bitmap]::new($tempImage)
    $tempImage.Dispose()
    $imageStream.Dispose()

    Show-Ball
    Expand-Panel $previewImage $imageBase64
    $previewImage = $null
  } catch {
    if ($null -ne $previewImage) { $previewImage.Dispose() }
    [System.Windows.Forms.MessageBox]::Show(
      ('无法准备截图：' + $_.Exception.Message),
      '一瞥',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    Show-Ball
  } finally {
    if ($null -ne $crop) { $crop.Dispose() }
    if ($null -ne $scaled) { $scaled.Dispose() }
    if ($null -ne $bitmap) { $bitmap.Dispose() }
  }
}

function Cancel-Capture {
  $script:selecting = $false
  Close-Frozen
  if ($null -ne $script:captureBitmap) {
    $script:captureBitmap.Dispose()
    $script:captureBitmap = $null
  }
  $script:busy = $false
  Show-Ball
}

function Start-Capture {
  if ($script:busy) { return }
  $script:busy = $true
  Stop-PanelReveal
  Hide-Shadow
  Hide-Ball
  if ($null -ne $script:panelForm) { $script:panelForm.Hide() }
  $script:panelVisible = $false
  Start-Sleep -Milliseconds 150

  $bitmap = $null
  try {
    $virtual = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = [System.Drawing.Bitmap]::new($virtual.Width, $virtual.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
      $graphics.CopyFromScreen($virtual.Left, $virtual.Top, 0, 0, $bitmap.Size)
    } finally {
      $graphics.Dispose()
    }
  } catch {
    if ($null -ne $bitmap) { $bitmap.Dispose() }
    $bitmap = $null
  }

  if ($null -eq $bitmap) {
    [System.Windows.Forms.MessageBox]::Show(
      '无法抓取屏幕内容。',
      '一瞥',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    $script:busy = $false
    Show-Ball
    return
  }

  Show-Frozen $bitmap
}

function Toggle-Ball {
  if ($script:panelAnimating) { return }
  if ($null -ne $script:panelForm -and $script:panelForm.Visible) {
    Collapse-Panel
  } else {
    Start-Capture
  }
}

try {
  $null = Load-BallImage
  [System.Windows.Forms.Application]::EnableVisualStyles()
  [System.Windows.Forms.Application]::SetUnhandledExceptionMode(
    [System.Windows.Forms.UnhandledExceptionMode]::CatchException
  )
  [System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $e)
    [Console]::Error.WriteLine($e.Exception.ToString())
    [System.Windows.Forms.MessageBox]::Show(
      ('一瞥出错：' + $e.Exception.Message),
      '一瞥',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
  })

  $ballDpi = 96
  try { $ballDpi = [int][ScreenSnapDpi]::GetDpiForSystem() } catch { }
  if ($ballDpi -lt 96) { $ballDpi = 96 }
  $ballScale = $ballDpi / 96.0
  $script:dpiScale = $ballScale
  $script:ballSize = [int][Math]::Round(84 * $ballScale)
  $script:ballMargin = [int][Math]::Round($script:ballSize * 0.15)
  $script:ballWindow = $script:ballSize + 2 * $script:ballMargin
  $script:ballWindowHeight = $script:ballWindow
  $script:ballImageScaled = $null
  Write-Log ('ball dpi=' + $ballDpi + ' size=' + $script:ballSize)

  $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $script:ballX = $workingArea.Right - 96 - $script:ballSize
  $script:ballY = $workingArea.Top + 88
  if ($script:ballX -lt $workingArea.Left + 8) { $script:ballX = $workingArea.Left + 8 }
  if ($script:ballY + $script:ballSize -gt $workingArea.Bottom - 8) {
    $script:ballY = $workingArea.Bottom - 8 - $script:ballSize
  }

  $ballForm = [ScreenSnapBallForm]::new()
  $ballForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
  $ballForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
  $ballForm.Size = [System.Drawing.Size]::new($script:ballWindow, $script:ballWindowHeight)
  $ballForm.TopMost = $true
  $ballForm.ShowInTaskbar = $false
  $ballForm.Cursor = [System.Windows.Forms.Cursors]::Hand
  $script:ballForm = $ballForm

  $ballForm.Add_MouseDown({
    param($sender, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    if ($e.X -lt $script:ballMargin -or $e.X -gt ($script:ballMargin + $script:ballSize) -or
        $e.Y -lt $script:ballMargin -or $e.Y -gt ($script:ballMargin + $script:ballSize)) { return }
    $script:ballDrag = @{
      start = [System.Windows.Forms.Cursor]::Position
      x = $script:ballX
      y = $script:ballY
      moved = $false
    }
    try { $script:ballForm.Capture = $true } catch { }
  })

  $ballForm.Add_MouseMove({
    param($sender, $e)
    if ($null -eq $script:ballDrag) { return }
    $position = [System.Windows.Forms.Cursor]::Position
    $dx = $position.X - $script:ballDrag.start.X
    $dy = $position.Y - $script:ballDrag.start.Y
    if (-not $script:ballDrag.moved -and ([Math]::Abs($dx) + [Math]::Abs($dy)) -lt 4) { return }
    $script:ballDrag.moved = $true
    $screen = [System.Windows.Forms.Screen]::FromPoint($position)
    $area = $screen.WorkingArea
    $newX = $script:ballDrag.x + $dx
    $newY = $script:ballDrag.y + $dy
    if ($newX -lt $area.Left + 8) { $newX = $area.Left + 8 }
    if ($newY -lt $area.Top + 8) { $newY = $area.Top + 8 }
    if ($newX + $script:ballSize -gt $area.Right - 8) { $newX = $area.Right - 8 - $script:ballSize }
    if ($newY + $script:ballSize -gt $area.Bottom - 8) { $newY = $area.Bottom - 8 - $script:ballSize }
    $script:ballX = $newX
    $script:ballY = $newY
    Update-Ball
    Move-PanelToBall
  })

  $ballForm.Add_MouseUp({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
      Show-BallMenu
      return
    }
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $drag = $script:ballDrag
    $script:ballDrag = $null
    try { $script:ballForm.Capture = $false } catch { }
    if ($null -eq $drag) { return }
    if (-not $drag.moved) {
      Toggle-Ball
    }
  })

  $ballForm.Add_MouseEnter({
    $script:ballHover = $true
    if ($null -eq $script:ballDrag -and -not $script:menuOpen) { Update-Ball }
  })
  $ballForm.Add_MouseLeave({
    $script:ballHover = $false
    if ($null -eq $script:ballDrag -and -not $script:menuOpen) { Update-Ball }
  })


  $script:tooltip = [System.Windows.Forms.ToolTip]::new()
  $script:tooltip.SetToolTip($ballForm, '左键框选屏幕区域；右键设置外观；拖动可移动位置')

  $panelForm = [ScreenSnapMainForm]::new()
  $panelForm.Text = '一瞥'
  $panelForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
  $panelForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
  $panelForm.Size = [System.Drawing.Size]::new($script:panelWidth, $script:panelHeight)
  $panelForm.TopMost = $true
  $panelForm.ShowInTaskbar = $false
  $panelForm.KeyPreview = $true
  $panelForm.BackColor = [System.Drawing.Color]::FromArgb(11, 14, 20)
  $script:panelForm = $panelForm

  $panelForm.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
      $e.SuppressKeyPress = $true
      Collapse-Panel
    }
  })

  $panelForm.Add_FormClosing({
    Stop-PanelAnimation
  })

  $panelForm.Add_LocationChanged({
    $script:panelX = $panelForm.Left
    $script:panelY = $panelForm.Top
    if ($script:panelVisible -and $null -ne $script:shadowForm -and $script:shadowForm.Visible) {
      Update-Shadow $script:panelWidth $panelForm.Height
    }
  })

  $script:panelUri = [System.Uri]::new((Join-Path $PSScriptRoot 'panel.html')).AbsoluteUri

  $web = [Microsoft.Web.WebView2.WinForms.WebView2]::new()
  $web.Dock = [System.Windows.Forms.DockStyle]::Fill
  $web.DefaultBackgroundColor = [System.Drawing.Color]::Transparent
  $panelForm.Controls.Add($web)
  $script:web = $web

  $web.Add_CoreWebView2InitializationCompleted({
    param($sender, $e)
    if (-not $e.IsSuccess) {
      Show-WebViewHint ([string]$e.InitializationException)
      return
    }
    $core = $sender.CoreWebView2
    $script:webCore = $core
    $core.Settings.AreDefaultContextMenusEnabled = $false
    $core.Settings.AreDevToolsEnabled = $false
    $core.Settings.IsStatusBarEnabled = $false
    $core.Settings.IsZoomControlEnabled = $false
    $core.Settings.IsPinchZoomEnabled = $false
    $core.Settings.AreBrowserAcceleratorKeysEnabled = $false
    $core.Add_WebMessageReceived({
      param($sender, $eventArgs)
      Handle-PanelMessage ([string]$eventArgs.WebMessageAsJson)
    })
    $core.Navigate($script:panelUri)
    Write-Log ('webview init ok, navigate ' + $script:panelUri)
  })

  $panelForm.Add_Shown({
    if ($script:webStarted) { return }
    $script:webStarted = $true
    try {
      $userDataFolder = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'dsh-glance\WebView2'
      try {
        New-Item -ItemType Directory -Force -Path $userDataFolder | Out-Null
      } catch {
        $userDataFolder = Join-Path (Join-Path ([System.IO.Path]::GetTempPath()) 'dsh-glance') 'WebView2'
        New-Item -ItemType Directory -Force -Path $userDataFolder | Out-Null
        Write-Log ('webview user data fallback: ' + $userDataFolder)
      }
      $environment = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $userDataFolder, $null).GetAwaiter().GetResult()
      $script:webEnvironment = $environment
      $null = $script:web.Handle
      $script:web.EnsureCoreWebView2Async($environment)
      Write-Log 'webview ensure called'
    } catch {
      Show-WebViewHint ($_.Exception.ToString())
    }
  })
  $panelForm.Hide()
  $null = $ballForm.Handle
  Update-Ball
  $ballForm.Show()
  $ballForm.TopMost = $true
  $ballForm.BringToFront()

  Send-HostMessage @{ type = 'ready' }
  Write-Log 'widget ready printed'

  Start-HostReader

  if ($SelfTest) {
    $testBitmap = [System.Drawing.Bitmap]::new(900, 260)
    $testGraphics = [System.Drawing.Graphics]::FromImage($testBitmap)
    try {
      $testGraphics.Clear([System.Drawing.Color]::White)
      $testFont = [System.Drawing.Font]::new('Consolas', [single]14)
      try {
        $testBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(200, 40, 40))
        try {
          $testGraphics.DrawString('TypeError: cannot read property x of undefined', $testFont, $testBrush, 16, 24)
          $testGraphics.DrawString('at main.js:42:13', $testFont, $testBrush, 16, 70)
        } finally {
          $testBrush.Dispose()
        }
      } finally {
        $testFont.Dispose()
      }
    } finally {
      $testGraphics.Dispose()
    }
    $script:selftestImage = $testBitmap
    $script:selftestTimer = [System.Windows.Forms.Timer]::new()
    $script:selftestTimer.Interval = 600
    $script:selftestTimer.Add_Tick({
      $script:selftestTimer.Stop()
      $script:selftestTimer.Dispose()
      Expand-Panel $script:selftestImage 'selftest'
    })
    $script:selftestTimer.Start()

    $script:selftestCapture = [System.Windows.Forms.Timer]::new()
    $script:selftestCapture.Interval = 2800
    $script:selftestCapture.Add_Tick({
      $script:selftestCapture.Stop()
      $script:selftestCapture.Dispose()
      $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'glance-selftest.png')
      $stream = $null
      try {
        if ($null -ne $script:web -and $null -ne $script:web.CoreWebView2) {
          $stream = [System.IO.File]::Create($path)
          $format = [Microsoft.Web.WebView2.Core.CoreWebView2CapturePreviewImageFormat]::Png
          $task = $script:web.CoreWebView2.CapturePreviewAsync($format, $stream)
          $closeTimer = [System.Windows.Forms.Timer]::new()
          $script:selftestClose = $closeTimer
          $closeTimer.Interval = 1500
          $closeTimer.Add_Tick({
            $script:selftestClose.Stop()
            $script:selftestClose.Dispose()
            try { $stream.Dispose() } catch { }
            try {
              [Console]::Out.WriteLine((@{ type = 'selftest'; path = $path } | ConvertTo-Json -Compress))
              [Console]::Out.Flush()
            } catch { }
            Close-Widget
          })
          $closeTimer.Start()
        } else {
          Close-Widget
        }
      } catch {
        if ($null -ne $stream) { try { $stream.Dispose() } catch { } }
        Close-Widget
      }
    })
    $script:selftestCapture.Start()
  }


  if ($ParentPid -gt 0) {
    $script:parentTimer = [System.Windows.Forms.Timer]::new()
    $script:parentTimer.Interval = 2000
    $script:parentTimer.Add_Tick({
      if ($null -eq (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)) {
        $script:parentTimer.Stop()
        Close-Widget
      }
    })
    $script:parentTimer.Start()
  }

  [System.Windows.Forms.Application]::Run($ballForm)
} catch {
  [Console]::Error.WriteLine($_.Exception.ToString())
  exit 1
}
