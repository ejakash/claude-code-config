BeforeAll {
    $script:CapturePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'capture.ps1'
    . $script:CapturePath -DotSourceOnly
}

Describe 'Write-Result' {
    Context 'pipe format' {
        It 'emits existing overview format verbatim' {
            $out = Write-Result -Kind 'overview' -Payload ([ordered]@{
                path = 'C:\x.png'; dims = '1200x675'; capture_id = '20260416_120000_000'
            }) -Format 'pipe' 6>&1
            $out | Should -Be 'overview|C:\x.png|1200x675|capture_id=20260416_120000_000'
        }
    }
    Context 'json format' {
        It 'emits one-line compact JSON with same fields' {
            $out = Write-Result -Kind 'overview' -Payload ([ordered]@{ path = 'C:\x.png' }) -Format 'json' 6>&1
            $json = $out | ConvertFrom-Json
            $json.kind | Should -Be 'overview'
            $json.path | Should -Be 'C:\x.png'
        }
    }
}

Describe 'ConvertTo-SafeTitle' {
    It 'URL-encodes pipe, newline, and percent' {
        ConvertTo-SafeTitle "foo|bar`nbaz%qux" | Should -Be 'foo%7Cbar%0Abaz%25qux'
    }
    It 'passes through plain ASCII' {
        ConvertTo-SafeTitle 'Claude Code - WezTerm' | Should -Be 'Claude Code - WezTerm'
    }
    It 'handles empty string' {
        ConvertTo-SafeTitle '' | Should -Be ''
    }
}

Describe 'Get-ProcessName' {
    It 'strips .exe and lowercases' {
        Get-ProcessName 'Chrome.exe' | Should -Be 'chrome'
    }
    It 'handles no-extension names' {
        Get-ProcessName 'WezTerm' | Should -Be 'wezterm'
    }
    It 'is case-insensitive' {
        Get-ProcessName 'CHROME.EXE' | Should -Be 'chrome'
    }
}

Describe 'Apply-Region' {
    BeforeAll {
        $script:testBounds = @{
            ExtendedFrame = @{ Left=100; Top=50; Right=900; Bottom=650 }  # 800x600
            ClientRect    = @{ Left=108; Top=80; Right=892; Bottom=642 }  # client, title bar ~30px high
        }
    }

    It 'returns extended frame for full' {
        $r = Apply-Region -Bounds $script:testBounds -Region 'full'
        $r.Left | Should -Be 100
        $r.Top | Should -Be 50
        $r.Right | Should -Be 900
        $r.Bottom | Should -Be 650
    }
    It 'returns client rect for content' {
        $r = Apply-Region -Bounds $script:testBounds -Region 'content'
        $r.Left | Should -Be 108
        $r.Top | Should -Be 80
        $r.Right | Should -Be 892
        $r.Bottom | Should -Be 642
    }
    It 'returns title bar strip for titlebar' {
        $r = Apply-Region -Bounds $script:testBounds -Region 'titlebar'
        $r.Left | Should -Be 100
        $r.Top | Should -Be 50
        $r.Right | Should -Be 900
        $r.Bottom | Should -Be 80   # ClientRect.Top
    }
    It 'splits left-half correctly' {
        $r = Apply-Region -Bounds $script:testBounds -Region 'left-half'
        $r.Left | Should -Be 100
        $r.Right | Should -Be 500   # midpoint of 100..900
    }
    It 'splits right-half correctly' {
        $r = Apply-Region -Bounds $script:testBounds -Region 'right-half'
        $r.Left | Should -Be 500
        $r.Right | Should -Be 900
    }
    It 'splits top-half correctly' {
        $r = Apply-Region -Bounds $script:testBounds -Region 'top-half'
        $r.Top | Should -Be 50
        $r.Bottom | Should -Be 350  # midpoint of 50..650
    }
    It 'splits bottom-half correctly' {
        $r = Apply-Region -Bounds $script:testBounds -Region 'bottom-half'
        $r.Top | Should -Be 350
        $r.Bottom | Should -Be 650
    }
    It 'returns center as middle 50%' {
        $r = Apply-Region -Bounds $script:testBounds -Region 'center'
        # 25% from left: 100 + 200 = 300; 75%: 100 + 600 = 700
        $r.Left | Should -Be 300
        $r.Right | Should -Be 700
        # 25% from top: 50 + 150 = 200; 75%: 50 + 450 = 500
        $r.Top | Should -Be 200
        $r.Bottom | Should -Be 500
    }
    It 'returns top 5% strip for top-strip' {
        $r = Apply-Region -Bounds $script:testBounds -Region 'top-strip'
        $r.Left | Should -Be 100
        $r.Right | Should -Be 900
        $r.Top | Should -Be 50
        # Height 600, 5% = 30
        $r.Bottom | Should -Be 80
    }
    It 'throws on unknown region' {
        { Apply-Region -Bounds $script:testBounds -Region 'bogus' } | Should -Throw
    }
}

Describe 'Test-CaptureBlank' {
    BeforeAll {
        function New-SolidBitmap {
            param([int]$W, [int]$H, [System.Drawing.Color]$Color)
            $bmp = New-Object System.Drawing.Bitmap($W, $H)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.Clear($Color)
            $g.Dispose()
            $bmp
        }
    }

    It 'flags all-black 800x600 bitmap as blank' {
        $bmp = New-SolidBitmap 800 600 ([System.Drawing.Color]::Black)
        (Test-CaptureBlank -Bitmap $bmp).IsBlank | Should -BeTrue
        $bmp.Dispose()
    }
    It 'flags all-white 800x600 as blank (uniform color)' {
        $bmp = New-SolidBitmap 800 600 ([System.Drawing.Color]::White)
        (Test-CaptureBlank -Bitmap $bmp).IsBlank | Should -BeTrue
        $bmp.Dispose()
    }
    It 'does NOT flag small 150x150 uniform bitmap (under min size)' {
        $bmp = New-SolidBitmap 150 150 ([System.Drawing.Color]::Gray)
        (Test-CaptureBlank -Bitmap $bmp).IsBlank | Should -BeFalse
        $bmp.Dispose()
    }
    It 'does NOT flag a bitmap with gradient content' {
        $bmp = New-Object System.Drawing.Bitmap(800, 600)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.Point(0, 0)),
            (New-Object System.Drawing.Point(800, 600)),
            [System.Drawing.Color]::Red,
            [System.Drawing.Color]::Blue)
        $g.FillRectangle($brush, 0, 0, 800, 600)
        $g.Dispose()
        (Test-CaptureBlank -Bitmap $bmp).IsBlank | Should -BeFalse
        $bmp.Dispose()
    }
    It 'reports CenterBlack count correctly for all-black bitmap' {
        $bmp = New-SolidBitmap 800 600 ([System.Drawing.Color]::Black)
        (Test-CaptureBlank -Bitmap $bmp).CenterBlack | Should -Be 9
        $bmp.Dispose()
    }
}

Describe 'Get-WindowBounds (smoke)' {
    It 'returns a plausible structure for the foreground window' {
        $hwnd = [Win32]::GetForegroundWindow()
        $b = Get-WindowBounds -Hwnd $hwnd
        $b.ExtendedFrame.Right | Should -BeGreaterThan $b.ExtendedFrame.Left
        $b.ClientRect.Right | Should -BeGreaterThan $b.ClientRect.Left
        $b.Dpi | Should -BeGreaterOrEqual 96
        $b.IsMinimized | Should -BeOfType [bool]
        $b.IsForeground | Should -BeTrue  # since we called GetForegroundWindow itself
        $b.Monitor | Should -BeGreaterOrEqual 0
        $b.ZOrder | Should -BeGreaterOrEqual 0
    }
}

Describe 'Capture-Window (smoke)' {
    It 'captures the current foreground window with auto strategy' {
        $hwnd = [Win32]::GetForegroundWindow()
        $result = Capture-Window -Hwnd $hwnd -Strategy 'auto'
        $result.Bitmap | Should -Not -BeNullOrEmpty
        $result.Bitmap.Width | Should -BeGreaterThan 0
        $result.Bitmap.Height | Should -BeGreaterThan 0
        $result.Strategy | Should -BeIn @('printwindow','restore')
        $result.Bitmap.Dispose()
    }
}

Describe 'Get-CandidateRanking' {
    It 'ranks foreground above others' {
        $cands = @(
            @{ Hwnd=1; IsForeground=$false; ZOrder=0; IsMinimized=$false; Area=1000 },
            @{ Hwnd=2; IsForeground=$true;  ZOrder=5; IsMinimized=$false; Area=500 }
        )
        (Get-CandidateRanking $cands)[0].Hwnd | Should -Be 2
    }
    It 'puts minimized last' {
        $cands = @(
            @{ Hwnd=1; IsForeground=$false; ZOrder=0; IsMinimized=$true;  Area=1000 },
            @{ Hwnd=2; IsForeground=$false; ZOrder=1; IsMinimized=$false; Area=500 }
        )
        (Get-CandidateRanking $cands)[0].Hwnd | Should -Be 2
    }
    It 'breaks ties by ZOrder (lower wins)' {
        $cands = @(
            @{ Hwnd=1; IsForeground=$false; ZOrder=5; IsMinimized=$false; Area=500 },
            @{ Hwnd=2; IsForeground=$false; ZOrder=0; IsMinimized=$false; Area=500 }
        )
        (Get-CandidateRanking $cands)[0].Hwnd | Should -Be 2
    }
    It 'breaks ties by area (larger wins)' {
        $cands = @(
            @{ Hwnd=1; IsForeground=$false; ZOrder=0; IsMinimized=$false; Area=500 },
            @{ Hwnd=2; IsForeground=$false; ZOrder=0; IsMinimized=$false; Area=1000 }
        )
        (Get-CandidateRanking $cands)[0].Hwnd | Should -Be 2
    }
}
