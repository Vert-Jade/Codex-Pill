# Codex Pill notification-area integration. Windows PowerShell 5.1.
# Dot-source after WPF, System.Windows.Forms and System.Drawing are loaded.
# Hiding the main window is deliberately distinct from closing the app.

function Initialize-PillTrayRenderer {
    if ('CodexPill.TrayRenderer' -as [type]) { return }
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
namespace CodexPill {
    public sealed class TrayColors : ProfessionalColorTable {
        private static Color Surface { get { return Color.FromArgb(30, 31, 35); } }
        private static Color Selected { get { return Color.FromArgb(48, 50, 56); } }
        private static Color Border { get { return Color.FromArgb(57, 59, 65); } }
        public TrayColors() { UseSystemColors = false; }
        public override Color ToolStripDropDownBackground { get { return Surface; } }
        public override Color ImageMarginGradientBegin { get { return Surface; } }
        public override Color ImageMarginGradientMiddle { get { return Surface; } }
        public override Color ImageMarginGradientEnd { get { return Surface; } }
        public override Color MenuBorder { get { return Border; } }
        public override Color MenuItemBorder { get { return Selected; } }
        public override Color MenuItemSelected { get { return Selected; } }
        public override Color MenuItemSelectedGradientBegin { get { return Selected; } }
        public override Color MenuItemSelectedGradientEnd { get { return Selected; } }
        public override Color MenuItemPressedGradientBegin { get { return Selected; } }
        public override Color MenuItemPressedGradientMiddle { get { return Selected; } }
        public override Color MenuItemPressedGradientEnd { get { return Selected; } }
        public override Color SeparatorDark { get { return Border; } }
        public override Color SeparatorLight { get { return Surface; } }
        public override Color CheckBackground { get { return Surface; } }
        public override Color CheckSelectedBackground { get { return Selected; } }
        public override Color CheckPressedBackground { get { return Selected; } }
    }
    public sealed class TrayRenderer : ToolStripProfessionalRenderer {
        public TrayRenderer() : base(new TrayColors()) { RoundedEdges = true; }
        protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e) {
            e.ArrowColor = Color.FromArgb(180, 182, 189);
            base.OnRenderArrow(e);
        }
        protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e) {
            Rectangle area = e.ImageRectangle;
            float x = area.Left + area.Width / 2.0f;
            float y = area.Top + area.Height / 2.0f;
            float scale = e.Graphics.DpiX / 96.0f;
            SmoothingMode previous = e.Graphics.SmoothingMode;
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            string choice = e.Item.Tag as string;
            bool providerChoice = choice == "Provider:Codex" || choice == "Provider:Claude";
            if (providerChoice) {
                // ToolStripMenuItem has no RadioCheck property: the provider
                // entries use exclusive Checked state with a radio indicator.
                Color accent = Color.FromArgb(112, 206, 173);
                using (Pen ring = new Pen(accent, 1.2f * scale)) {
                    e.Graphics.DrawEllipse(ring, x - 4.5f * scale, y - 4.5f * scale, 9 * scale, 9 * scale);
                }
                using (Brush dot = new SolidBrush(accent)) {
                    e.Graphics.FillEllipse(dot, x - 2 * scale, y - 2 * scale, 4 * scale, 4 * scale);
                }
            } else {
                using (Pen pen = new Pen(Color.FromArgb(112, 206, 173), 1.6f * scale)) {
                    pen.StartCap = LineCap.Round;
                    pen.EndCap = LineCap.Round;
                    pen.LineJoin = LineJoin.Round;
                    e.Graphics.DrawLines(pen, new PointF[] {
                        new PointF(x - 4 * scale, y),
                        new PointF(x - 1 * scale, y + 3 * scale),
                        new PointF(x + 5 * scale, y - 3 * scale)
                    });
                }
            }
            e.Graphics.SmoothingMode = previous;
        }
    }
}
'@
}

function Invoke-PillTrayAction {
    param([scriptblock]$Action)
    if ($script:PillExiting -or $null -eq $script:PillUi) { return }
    # NotifyIcon was created on the WPF dispatcher thread. Its native window
    # receives messages through that same dispatcher; this branch also keeps
    # future callers from touching WPF objects from another thread.
    if (-not $script:PillUi.Main.Dispatcher.CheckAccess()) {
        [void]$script:PillUi.Main.Dispatcher.BeginInvoke([Action]$Action)
        return
    }
    try { & $Action }
    catch {
        Write-PillLog $_
        [void][Windows.MessageBox]::Show('Cette action ne peut pas être effectuée. Consulte le journal de Codex Pill.', 'Codex Pill')
    } finally {
        if (-not $script:PillExiting) { Update-PillTray }
    }
}

function Show-PillWidget {
    param([switch]$ResetPosition)
    if ($script:PillExiting -or $null -eq $script:PillUi) { return }
    $mainWindow = $script:PillUi.Main
    if ($mainWindow.WindowState -eq [Windows.WindowState]::Minimized) { $mainWindow.WindowState = 'Normal' }
    if (-not $mainWindow.IsVisible) { $mainWindow.Show() }
    Move-PillIntoView -Reset:$ResetPosition
    [void]$mainWindow.Activate()
    Save-PillSettings
    Update-PillTray
}

function Hide-PillWidget {
    if ($script:PillExiting -or $null -eq $script:PillUi) { return }
    if ($null -eq $script:PillTray -or -not $script:PillTray.Notify.Visible) {
        throw "L’icône de notification est indisponible ; la pastille reste visible."
    }
    Save-PillSettings
    $script:PillUi.Detail.Hide()
    $script:PillUi.Main.Hide()
    Update-PillTray
}

function Update-PillTray {
    if ($script:PillExiting -or $null -eq $script:PillTray -or $null -eq $script:PillUi) { return }
    $widgetVisible = [bool]$script:PillUi.Main.IsVisible
    $script:PillTray.Items.Show.Enabled = -not $widgetVisible
    $script:PillTray.Items.Hide.Enabled = $widgetVisible
    $script:PillTray.Items.Console.Checked = [bool]$script:PillSettings.HideConsole
    $script:PillTray.Items.Topmost.Checked = [bool]$script:PillSettings.Topmost
    $providerName = if ([string]$script:PillSettings.Provider -eq 'Claude') { 'Claude' } else { 'Codex' }
    $script:PillTray.Items.Provider.Text = 'Suivi : ' + $providerName
    $script:PillTray.Items.ProviderCodex.Checked = $providerName -eq 'Codex'
    $script:PillTray.Items.ProviderClaude.Checked = $providerName -eq 'Claude'
    $script:PillTray.Notify.Text = if ($widgetVisible) { 'Codex Pill - ' + $providerName + ' - double-clic : afficher' } else { 'Codex Pill - ' + $providerName + ' - actif en arrière-plan' }
    # Keep both menus consistent without firing their Click event again.
    if ($null -ne $script:PillUi.Controls.PillSurface.ContextMenu) {
        foreach ($entry in $script:PillUi.Controls.PillSurface.ContextMenu.Items) {
            if ($entry -is [Windows.Controls.MenuItem]) {
                if ([string]$entry.Header -eq 'Masquer la fenêtre de commande') { $entry.IsChecked = [bool]$script:PillSettings.HideConsole }
                elseif ([string]$entry.Header -eq 'Toujours au premier plan') { $entry.IsChecked = [bool]$script:PillSettings.Topmost }
            }
        }
    }
}

function Add-PillTrayMenuItem {
    param($Menu, [string]$Text, [scriptblock]$Action, [switch]$Checkable)
    $menuEntry = [Windows.Forms.ToolStripMenuItem]::new()
    $menuEntry.Text = $Text
    $menuEntry.CheckOnClick = [bool]$Checkable
    $menuEntry.Padding = [Windows.Forms.Padding]::new(7, 5, 10, 5)
    $menuEntry.ForeColor = [Drawing.Color]::FromArgb(230, 231, 233)
    $menuEntry.Add_Click($Action)
    [void]$Menu.Items.Add($menuEntry)
    return $menuEntry
}

function Get-PillTrayProviderImage {
    param([ValidateSet('Codex','Claude')][string]$Provider)
    $providerDirectory = Join-Path $script:PillDirectory 'assets\providers'
    $providerPath = Join-Path $providerDirectory ($Provider + '.png')
    if (-not [IO.File]::Exists($providerPath)) { return $null }
    $sourceImage = $null
    try {
        $sourceImage = [Drawing.Image]::FromFile($providerPath)
        # Clone before disposing the source to release the file immediately.
        return [Drawing.Image]$sourceImage.Clone()
    } catch {
        Write-PillLog $_
        return $null
    } finally {
        if ($null -ne $sourceImage) { $sourceImage.Dispose() }
    }
}

function New-PillTray {
    if ($null -ne $script:PillTray) { return }
    $script:PillTray = @{ Notify = $null; Menu = $null; Icon = $null; Font = $null; Items = @{}; ProviderImages = @{} }
    try {
        $menuObject = [Windows.Forms.ContextMenuStrip]::new()
        $script:PillTray.Menu = $menuObject
        $menuObject.BackColor = [Drawing.Color]::FromArgb(30, 31, 35)
        $menuObject.ForeColor = [Drawing.Color]::FromArgb(230, 231, 233)
        $menuObject.ShowImageMargin = $false
        $menuObject.ShowCheckMargin = $true
        $menuObject.Padding = [Windows.Forms.Padding]::new(4)
        $menuFont = [Drawing.Font]::new('Segoe UI', 9.0, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Point)
        $script:PillTray.Font = $menuFont
        $menuObject.Font = $menuFont
        try {
            Initialize-PillTrayRenderer
            $menuObject.Renderer = [CodexPill.TrayRenderer]::new()
        } catch {
            # A theme failure must never remove access to the running widget.
            Write-PillLog $_
            $menuObject.RenderMode = 'System'
        }
        $script:PillTray.Items.Show = Add-PillTrayMenuItem $menuObject 'Afficher la pastille' {
            Invoke-PillTrayAction { Show-PillWidget }
        }
        $script:PillTray.Items.Hide = Add-PillTrayMenuItem $menuObject 'Masquer la pastille' {
            Invoke-PillTrayAction { Hide-PillWidget }
        }
        $script:PillTray.Items.Details = Add-PillTrayMenuItem $menuObject 'Détails des quotas' {
            Invoke-PillTrayAction {
                Show-PillWidget
                if (-not $script:PillUi.Detail.IsVisible) { Show-PillDetails }
                else { [void]$script:PillUi.Detail.Activate() }
            }
        }
        [void]$menuObject.Items.Add([Windows.Forms.ToolStripSeparator]::new())
        $providerMenu = [Windows.Forms.ToolStripMenuItem]::new()
        $providerMenu.Text = 'Suivi : Codex'
        $providerMenu.Padding = [Windows.Forms.Padding]::new(7, 5, 10, 5)
        $providerMenu.ForeColor = $menuObject.ForeColor
        $providerDropDown = $providerMenu.DropDown
        $providerDropDown.BackColor = $menuObject.BackColor
        $providerDropDown.ForeColor = $menuObject.ForeColor
        $providerDropDown.Font = $menuFont
        $providerDropDown.Renderer = $menuObject.Renderer
        $providerDropDown.Padding = [Windows.Forms.Padding]::new(4)
        $providerDropDown.ShowImageMargin = $true
        $providerDropDown.ShowCheckMargin = $true
        $providerDropDown.ImageScalingSize = [Drawing.Size]::new(16, 16)
        $script:PillTray.Items.Provider = $providerMenu
        [void]$menuObject.Items.Add($providerMenu)
        $script:PillTray.Items.ProviderCodex = Add-PillTrayMenuItem $providerDropDown 'Codex' {
            Invoke-PillTrayAction {
                if ([string]$script:PillSettings.Provider -ne 'Codex') { Set-PillProvider -Provider 'Codex' }
                Update-PillTray
            }
        }
        $script:PillTray.Items.ProviderClaude = Add-PillTrayMenuItem $providerDropDown 'Claude' {
            Invoke-PillTrayAction {
                if ([string]$script:PillSettings.Provider -ne 'Claude') { Set-PillProvider -Provider 'Claude' }
                Update-PillTray
            }
        }
        foreach ($providerName in @('Codex','Claude')) {
            $providerItem = $script:PillTray.Items['Provider' + $providerName]
            $providerItem.Tag = 'Provider:' + $providerName
            $providerImage = Get-PillTrayProviderImage -Provider $providerName
            if ($null -ne $providerImage) {
                $script:PillTray.ProviderImages[$providerName] = $providerImage
                $providerItem.Image = $providerImage
                $providerItem.ImageScaling = [Windows.Forms.ToolStripItemImageScaling]::SizeToFit
            }
        }
        [void]$menuObject.Items.Add([Windows.Forms.ToolStripSeparator]::new())
        $script:PillTray.Items.Console = Add-PillTrayMenuItem $menuObject 'Masquer la fenêtre de commande' {
            Invoke-PillTrayAction {
                Set-PillConsoleHidden -Hidden ([bool]$script:PillTray.Items.Console.Checked)
                Save-PillSettings
            }
        } -Checkable
        $script:PillTray.Items.Topmost = Add-PillTrayMenuItem $menuObject 'Toujours au premier plan' {
            Invoke-PillTrayAction {
                $script:PillSettings.Topmost = [bool]$script:PillTray.Items.Topmost.Checked
                $script:PillUi.Main.Topmost = $script:PillSettings.Topmost
                $script:PillUi.Detail.Topmost = $script:PillSettings.Topmost
                Save-PillSettings
            }
        } -Checkable
        [void]$menuObject.Items.Add([Windows.Forms.ToolStripSeparator]::new())
        $script:PillTray.Items.Quit = Add-PillTrayMenuItem $menuObject 'Quitter Codex Pill' {
            Invoke-PillTrayAction { $script:PillUi.Main.Close() }
        }
        $menuObject.Add_Opening({ if (-not $script:PillExiting) { Update-PillTray } })
        $assetPath = Join-Path $script:PillDirectory 'assets\CodexPill.ico'
        if ([IO.File]::Exists($assetPath)) {
            $sourceIcon = [Drawing.Icon]::new($assetPath, [Drawing.Size]::new(32, 32))
            try { $script:PillTray.Icon = [Drawing.Icon]$sourceIcon.Clone() }
            finally { $sourceIcon.Dispose() }
        } else {
            $script:PillTray.Icon = [Drawing.Icon][Drawing.SystemIcons]::Application.Clone()
        }
        $notificationIcon = [Windows.Forms.NotifyIcon]::new()
        $script:PillTray.Notify = $notificationIcon
        $notificationIcon.Icon = $script:PillTray.Icon
        $notificationIcon.Text = 'Codex Pill'
        $notificationIcon.ContextMenuStrip = $menuObject
        $notificationIcon.Add_MouseDoubleClick({
            param($senderObject, $mouseEvent)
            if ($mouseEvent.Button -eq [Windows.Forms.MouseButtons]::Left) {
                Invoke-PillTrayAction { Show-PillWidget }
            }
        })
        # Windows owns overflow placement. Visible=true registers the icon;
        # it does not force it into or out of the user's hidden-icons panel.
        $notificationIcon.Visible = $true
        Update-PillTray
    } catch {
        Remove-PillTray
        throw
    }
}

function Remove-PillTray {
    if ($null -eq $script:PillTray) { return }
    $trayState = $script:PillTray
    $script:PillTray = $null
    if ($null -ne $trayState.Notify) {
        try { $trayState.Notify.Visible = $false; $trayState.Notify.ContextMenuStrip = $null }
        finally { $trayState.Notify.Dispose() }
    }
    if ($null -ne $trayState.Menu) { $trayState.Menu.Dispose() }
    if ($null -ne $trayState.Icon) { $trayState.Icon.Dispose() }
    if ($null -ne $trayState.Font) { $trayState.Font.Dispose() }
    foreach ($providerImage in $trayState.ProviderImages.Values) { $providerImage.Dispose() }
}
