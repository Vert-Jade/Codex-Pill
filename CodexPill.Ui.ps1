# Vue WPF. À charger seulement après PresentationFramework.
# Tout l'état durable est explicitement en portée script: pour éviter les
# collisions de variables de PowerShell (insensible à la casse, portée dynamique).

function Get-PillBrush {
    param([string]$Color, [double]$Opacity = 1.0)
    $brushObject = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
    if ($Opacity -lt 1.0) { $brushObject = $brushObject.Clone(); $brushObject.Opacity = $Opacity }
    $brushObject.Freeze()
    return $brushObject
}

function New-PillUi {
    $resourcesXaml = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
 <FontFamily x:Key="TextFont">Segoe UI Variable Text, Segoe UI</FontFamily>
 <FontFamily x:Key="DisplayFont">Segoe UI Variable Display, Segoe UI</FontFamily>
 <Style TargetType="TextBlock"><Setter Property="Foreground" Value="#F2F3F5"/><Setter Property="FontFamily" Value="{StaticResource TextFont}"/><Setter Property="TextOptions.TextFormattingMode" Value="Ideal"/><Setter Property="TextOptions.TextRenderingMode" Value="ClearType"/></Style>
 <Style x:Key="SectionLabel" TargetType="TextBlock"><Setter Property="FontSize" Value="10"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Foreground" Value="#7C808B"/><Setter Property="FontFamily" Value="{StaticResource TextFont}"/></Style>
 <Style x:Key="QuietButton" TargetType="Button">
  <Setter Property="Foreground" Value="#A3A7B1"/><Setter Property="Background" Value="Transparent"/><Setter Property="BorderBrush" Value="Transparent"/><Setter Property="Padding" Value="10,6"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="ButtonSurface" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonSurface" Property="Background" Value="#26282E"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="ButtonSurface" Property="BorderBrush" Value="#5E636E"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="ButtonSurface" Property="Background" Value="#2F3138"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
 </Style>
 <Style x:Key="OutlineButton" TargetType="Button" BasedOn="{StaticResource QuietButton}"><Setter Property="Background" Value="#1F2025"/><Setter Property="BorderBrush" Value="#30323A"/><Setter Property="Foreground" Value="#D5D7DC"/></Style>
 <Style x:Key="Segment" TargetType="RadioButton"><Setter Property="Foreground" Value="#8D919B"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Padding" Value="10,7"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton"><Border x:Name="SegmentSurface" CornerRadius="8" Background="Transparent" BorderBrush="Transparent" BorderThickness="1" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="#D5D7DC"/></Trigger><Trigger Property="IsChecked" Value="True"><Setter TargetName="SegmentSurface" Property="Background" Value="#272930"/><Setter TargetName="SegmentSurface" Property="BorderBrush" Value="#363841"/><Setter Property="Foreground" Value="#F5F6F8"/><Setter TargetName="SegmentSurface" Property="Effect"><Setter.Value><DropShadowEffect Color="#000000" BlurRadius="6" ShadowDepth="1" Direction="270" Opacity="0.35"/></Setter.Value></Setter></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="SegmentSurface" Property="BorderBrush" Value="#6A6F7B"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="ContextMenu"><Setter Property="Foreground" Value="#E6E7E9"/><Setter Property="FontFamily" Value="{StaticResource TextFont}"/><Setter Property="FontSize" Value="12"/><Setter Property="HasDropShadow" Value="True"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ContextMenu"><Border Background="#1B1C20" BorderBrush="#33353C" BorderThickness="1" CornerRadius="12" Padding="5"><StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle"/></Border></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="MenuItem"><Setter Property="Padding" Value="9,7"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="MenuItem"><Border x:Name="MenuSurface" Background="Transparent" CornerRadius="7" Padding="{TemplateBinding Padding}"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="22"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Path x:Name="MenuCheck" Data="M 1 5 L 4 8 L 10 1.5" Stroke="#6FD6B0" StrokeThickness="1.6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" VerticalAlignment="Center" Visibility="Collapsed"/><ContentPresenter Grid.Column="1" ContentSource="Header" RecognizesAccessKey="True"/></Grid></Border><ControlTemplate.Triggers><Trigger Property="IsHighlighted" Value="True"><Setter TargetName="MenuSurface" Property="Background" Value="#2A2C32"/></Trigger><Trigger Property="IsChecked" Value="True"><Setter TargetName="MenuCheck" Property="Visibility" Value="Visible"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="Separator"><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Separator"><Border Height="1" Background="#2C2E34" Margin="8,4"/></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="ToolTip"><Setter Property="Foreground" Value="#E6E7E9"/><Setter Property="FontFamily" Value="{StaticResource TextFont}"/><Setter Property="FontSize" Value="11"/><Setter Property="HasDropShadow" Value="True"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ToolTip"><Border Background="#202126" BorderBrush="#363840" BorderThickness="1" CornerRadius="8" Padding="10,7"><ContentPresenter/></Border></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="ScrollBar"><Setter Property="Width" Value="6"/><Setter Property="MinWidth" Value="6"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar"><Track x:Name="PART_Track" IsDirectionReversed="True"><Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb"><Border Background="#3A3C44" CornerRadius="3"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb></Track></ControlTemplate></Setter.Value></Setter></Style>
</ResourceDictionary>
'@
    # Gabarit d'un rond de la pastille : anneau de la part restante, valeur au centre,
    # durée de la fenêtre en dessous. Dimensions liées à Set-PillShape (52 px, pas de 48 px).
    $pillMeterXaml = @'
   <Grid x:Name="{P}Group" Width="52" Height="52" Margin="{M}">
    <Ellipse Width="44" Height="44" Stroke="#2A2C32" StrokeThickness="4" HorizontalAlignment="Center" VerticalAlignment="Center"/>
    <Path x:Name="{P}PillRing" Width="44" Height="44" StrokeThickness="4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Stroke="#1E90FF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
    <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,1,0,0">
     <TextBlock HorizontalAlignment="Center" FontFamily="{StaticResource DisplayFont}"><Run x:Name="{P}ValueNumber" Text="—" FontSize="14" FontWeight="SemiBold"/><Run x:Name="{P}ValueUnit" Text="" FontSize="8" Foreground="#8D919B"/></TextBlock>
     <TextBlock x:Name="{P}Label" Text="" FontSize="7.5" FontWeight="SemiBold" Foreground="#7C808B" HorizontalAlignment="Center" Margin="0,-3,0,0"/>
    </StackPanel>
   </Grid>
'@
    # La pastille est un rond (une seule fenêtre de quota) ou un « 8 » horizontal
    # (session 5 h et semaine). Sa silhouette est calculée par Set-PillShape.
    $mainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Codex Pill" WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize" ShowInTaskbar="False" ShowActivated="False" SizeToContent="WidthAndHeight" UseLayoutRounding="True" SnapsToDevicePixels="True">
 <!-- RESOURCES -->
 <Grid><Grid.LayoutTransform><ScaleTransform x:Name="PillScale" ScaleX="1" ScaleY="1"/></Grid.LayoutTransform>
 <Grid x:Name="PillSurface" Margin="16" Opacity="0.94" Cursor="Hand" ToolTipService.InitialShowDelay="500" AutomationProperties.Name="Quotas restants. Cliquer pour les détails, faire glisser pour déplacer.">
  <Path x:Name="PillShape" StrokeThickness="1" HorizontalAlignment="Left" VerticalAlignment="Top">
   <Path.Stroke><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#3B3D45" Offset="0"/><GradientStop Color="#25262B" Offset="1"/></LinearGradientBrush></Path.Stroke>
   <Path.Fill><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#1F2025" Offset="0"/><GradientStop Color="#16171A" Offset="1"/></LinearGradientBrush></Path.Fill>
   <Path.Effect><DropShadowEffect Color="#000000" BlurRadius="18" ShadowDepth="4" Direction="270" Opacity="0.4"/></Path.Effect>
  </Path>
  <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" VerticalAlignment="Top">
   <!-- PRIMARY -->
   <!-- SECONDARY -->
  </StackPanel>
  <Ellipse x:Name="StatusDot" Width="9" Height="9" Fill="#7E818B" Stroke="#18191C" StrokeThickness="2" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,3,3,0" Visibility="Collapsed" IsHitTestVisible="False"/>
 </Grid>
 </Grid>
</Window>
'@
    # Gabarit d'une carte du panneau : anneau, titre, échéance.
    $cardXaml = @'
     <Border x:Name="{P}Card" Grid.Column="{C}" Margin="{M}" Background="#1C1D22" BorderBrush="#27282E" BorderThickness="1" CornerRadius="14" Padding="10,16,10,14">
      <StackPanel>
       <Grid Width="96" Height="96" HorizontalAlignment="Center">
        <Ellipse Stroke="#292B31" StrokeThickness="8" Margin="0"/>
        <Path x:Name="{P}Ring" Width="96" Height="96" StrokeThickness="8" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Stroke="#1E90FF"/>
        <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,2,0,0">
         <TextBlock HorizontalAlignment="Center" FontFamily="{StaticResource DisplayFont}"><Run x:Name="{P}BigNumber" Text="—" FontSize="25" FontWeight="SemiBold"/><Run x:Name="{P}BigUnit" Text=" %" FontSize="12" Foreground="#8D919B"/></TextBlock>
         <TextBlock Text="restant" FontSize="10" Foreground="#7C808B" HorizontalAlignment="Center" Margin="0,-1,0,0"/>
        </StackPanel>
       </Grid>
       <TextBlock x:Name="{P}Title" Text="Quota" FontSize="12.5" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,13,0,0"/>
       <TextBlock x:Name="{P}Reset" Text="En attente d’une mesure" FontSize="10.5" Foreground="#A0A3AD" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Margin="0,4,0,0"/>
       <TextBlock x:Name="{P}Remaining" Text="" FontSize="10" Foreground="#6E727D" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Margin="0,2,0,0"/>
      </StackPanel>
     </Border>
'@
    $detailXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Codex Pill · Détails" Width="376" SizeToContent="Height" MaxHeight="720" WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize" ShowInTaskbar="False" UseLayoutRounding="True" SnapsToDevicePixels="True">
 <!-- RESOURCES -->
 <Border x:Name="DetailSurface" Margin="14" CornerRadius="18" BorderThickness="1">
  <Border.RenderTransform><TranslateTransform x:Name="DetailShift"/></Border.RenderTransform>
  <Border.BorderBrush><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#383A42" Offset="0"/><GradientStop Color="#232428" Offset="1"/></LinearGradientBrush></Border.BorderBrush>
  <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#1B1C20" Offset="0"/><GradientStop Color="#141518" Offset="1"/></LinearGradientBrush></Border.Background>
  <Border.Effect><DropShadowEffect Color="#000000" BlurRadius="26" ShadowDepth="6" Direction="270" Opacity="0.42"/></Border.Effect>
  <ScrollViewer x:Name="DetailScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" MaxHeight="640">
   <StackPanel Margin="18,16,18,14">
    <Grid x:Name="DetailHeader"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
     <Border Width="34" Height="34" CornerRadius="10" Background="#202127" BorderBrush="#2E3037" BorderThickness="1" VerticalAlignment="Center"><Image x:Name="DetailLogo" Width="22" Height="22" RenderOptions.BitmapScalingMode="HighQuality"/></Border>
     <StackPanel Grid.Column="1" Margin="11,0,0,0" VerticalAlignment="Center">
      <TextBlock Text="Codex Pill" FontSize="14.5" FontWeight="SemiBold" FontFamily="{StaticResource DisplayFont}"/>
      <StackPanel Orientation="Horizontal" Margin="0,3,0,0"><Ellipse x:Name="DetailStatusDot" Width="6" Height="6" Fill="#4FD18B" VerticalAlignment="Center" Margin="0,1,6,0"/><TextBlock x:Name="StatusText" Text="Lecture des données…" FontSize="11" Foreground="#9296A0" TextTrimming="CharacterEllipsis"/></StackPanel>
     </StackPanel>
     <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Top">
      <Button x:Name="HideWidgetButton" Width="28" Height="28" Padding="0" Margin="0,0,2,0" Style="{StaticResource QuietButton}" ToolTip="Réduire dans la zone de notification" AutomationProperties.Name="Réduire dans la zone de notification"><Path Width="10" Height="10" Data="M 1 5 L 9 5" Stretch="None" Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType={x:Type Button}}}" StrokeThickness="1.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" HorizontalAlignment="Center" VerticalAlignment="Center"/></Button>
      <Button x:Name="CloseDetailButton" Width="28" Height="28" Padding="0" Style="{StaticResource QuietButton}" ToolTip="Fermer les détails (Échap)" AutomationProperties.Name="Fermer les détails"><Path Width="10" Height="10" Data="M 1.5 1.5 L 8.5 8.5 M 8.5 1.5 L 1.5 8.5" Stretch="None" Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType={x:Type Button}}}" StrokeThickness="1.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" HorizontalAlignment="Center" VerticalAlignment="Center"/></Button>
     </StackPanel>
    </Grid>
    <Border Background="#111215" BorderBrush="#24252A" BorderThickness="1" CornerRadius="11" Padding="3" Margin="0,16,0,0">
     <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <RadioButton x:Name="CodexOption" GroupName="AIProvider" Tag="Codex" Style="{StaticResource Segment}" AutomationProperties.Name="Suivre Codex"><StackPanel Orientation="Horizontal"><Path x:Name="CodexChoiceLogo" Width="14" Height="14" Stretch="Uniform" Fill="#F2F3F5" Margin="0,0,8,0" VerticalAlignment="Center"/><TextBlock Text="Codex" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center" Foreground="{Binding Foreground, RelativeSource={RelativeSource AncestorType={x:Type RadioButton}}}"/></StackPanel></RadioButton>
      <RadioButton x:Name="ClaudeOption" Grid.Column="1" GroupName="AIProvider" Tag="Claude" Style="{StaticResource Segment}" AutomationProperties.Name="Suivre Claude"><StackPanel Orientation="Horizontal"><Path x:Name="ClaudeChoiceLogo" Width="14" Height="14" Stretch="Uniform" Fill="#E0896B" Margin="0,0,8,0" VerticalAlignment="Center"/><TextBlock Text="Claude" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center" Foreground="{Binding Foreground, RelativeSource={RelativeSource AncestorType={x:Type RadioButton}}}"/></StackPanel></RadioButton>
     </Grid>
    </Border>
    <Grid Margin="2,20,2,10"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
     <TextBlock Text="QUOTAS RESTANTS" Style="{StaticResource SectionLabel}" VerticalAlignment="Center"/>
     <Border x:Name="PlanBadge" Grid.Column="1" CornerRadius="6" Padding="7,2,7,3" Visibility="Collapsed"><TextBlock x:Name="PlanText" Text="" FontSize="10" FontWeight="SemiBold"/></Border>
    </Grid>
    <Border x:Name="ClaudeSetupPanel" Background="#1C1D22" BorderBrush="#2A2C33" BorderThickness="1" CornerRadius="12" Padding="13,11" Margin="0,0,0,10" Visibility="Collapsed"><StackPanel><TextBlock x:Name="ClaudeSetupText" Text="" FontSize="11" Foreground="#B4B8C1" TextWrapping="Wrap" LineHeight="17"/><Button x:Name="EnableClaudeButton" Style="{StaticResource OutlineButton}" HorizontalAlignment="Left" Margin="0,10,0,0" FontSize="11"><TextBlock Text="Activer aussi la barre de statut du terminal" Foreground="{Binding Foreground, RelativeSource={RelativeSource AncestorType={x:Type Button}}}"/></Button></StackPanel></Border>
    <Border x:Name="NoticePanel" Background="#231F18" BorderBrush="#40372A" BorderThickness="1" CornerRadius="12" Padding="12,9" Margin="0,0,0,10" Visibility="Collapsed"><TextBlock x:Name="NoticeText" FontSize="11" Foreground="#E0BE84" TextWrapping="Wrap" LineHeight="17"/></Border>
    <Grid x:Name="CardsGrid"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition x:Name="SecondaryColumn" Width="*"/></Grid.ColumnDefinitions>
     <!-- PRIMARY CARD -->
     <!-- SECONDARY CARD -->
    </Grid>
    <Grid Margin="2,22,2,4"><TextBlock Text="ACTIVITÉ RÉCENTE" Style="{StaticResource SectionLabel}"/></Grid>
    <StackPanel x:Name="ActivityRows"/>
    <TextBlock x:Name="ActivityNote" Text="" FontSize="10" Foreground="#686C77" TextWrapping="Wrap" Margin="2,10,2,14"/>
    <Border Background="#24252A" Height="1" Margin="-18,0"/>
    <Grid Margin="0,11,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
     <StackPanel VerticalAlignment="Center" Margin="2,0,0,0"><TextBlock x:Name="SourceLabel" Text="" FontSize="10.5" Foreground="#8D919B" TextTrimming="CharacterEllipsis"/><TextBlock x:Name="VersionLabel" Text="Codex Pill" FontSize="9.5" Foreground="#5B5F69" Margin="0,2,0,0"/></StackPanel>
     <Button x:Name="RefreshButton" Grid.Column="1" Style="{StaticResource OutlineButton}" FontSize="11" Padding="11,6" ToolTip="Relire les mesures maintenant. Ne consomme aucune requête IA."><StackPanel Orientation="Horizontal"><Path Width="12" Height="12" Data="M 10.2 6 A 4.2 4.2 0 1 1 8.97 3.03 M 9.4 0.9 L 9.4 3.4 L 6.9 3.4" Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType={x:Type Button}}}" StrokeThickness="1.3" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Margin="0,0,7,0" VerticalAlignment="Center"/><TextBlock Text="Actualiser" VerticalAlignment="Center" Foreground="{Binding Foreground, RelativeSource={RelativeSource AncestorType={x:Type Button}}}"/></StackPanel></Button>
    </Grid>
   </StackPanel>
  </ScrollViewer>
 </Border>
</Window>
'@
    # Le second rond chevauche le premier de 4 px : les deux disques se fondent en « 8 ».
    $primaryMeter = $pillMeterXaml.Replace('{P}', 'Primary').Replace('{M}', '0')
    $secondaryMeter = $pillMeterXaml.Replace('{P}', 'Secondary').Replace('{M}', '-4,0,0,0')
    $primaryCard = $cardXaml.Replace('{P}', 'Primary').Replace('{C}', '0').Replace('{M}', '0,0,5,0')
    $secondaryCard = $cardXaml.Replace('{P}', 'Secondary').Replace('{C}', '1').Replace('{M}', '5,0,0,0')
    $resourceBlock = '<Window.Resources>' + $resourcesXaml + '</Window.Resources>'
    $mainMarkup = $mainXaml.Replace('<!-- RESOURCES -->', $resourceBlock).Replace('<!-- PRIMARY -->', $primaryMeter).Replace('<!-- SECONDARY -->', $secondaryMeter)
    $detailMarkup = $detailXaml.Replace('<!-- RESOURCES -->', $resourceBlock).Replace('<!-- PRIMARY CARD -->', $primaryCard).Replace('<!-- SECONDARY CARD -->', $secondaryCard)
    $mainWindow = [System.Windows.Markup.XamlReader]::Parse($mainMarkup)
    $detailWindow = [System.Windows.Markup.XamlReader]::Parse($detailMarkup)
    $view = @{
        Main = $mainWindow; Detail = $detailWindow; Controls = @{}; ActivitySignature = ''
        Theme = @{ Text = '#F2F3F5'; Muted = '#8D919B'; Quiet = '#5E626C'; Good = '#1E90FF'; Accent = '#1E90FF'; Live = '#4FD18B'; Warning = '#FFC93C'; Danger = '#FF3B3B' }
        Accents = @{ Codex = '#1E90FF'; Claude = '#E0896B' }
    }
    foreach ($controlName in @('PillScale','PillSurface','PillShape','StatusDot')) {
        $view.Controls[$controlName] = $mainWindow.FindName($controlName)
    }
    foreach ($prefix in @('Primary','Secondary')) {
        foreach ($suffix in @('Group','Label','ValueNumber','ValueUnit','PillRing')) { $view.Controls[$prefix + $suffix] = $mainWindow.FindName($prefix + $suffix) }
        foreach ($suffix in @('Card','Ring','BigNumber','BigUnit','Title','Reset','Remaining')) { $view.Controls[$prefix + $suffix] = $detailWindow.FindName($prefix + $suffix) }
    }
    foreach ($controlName in @('DetailSurface','DetailShift','DetailScroll','DetailHeader','DetailLogo','HideWidgetButton','CloseDetailButton','CodexOption','ClaudeOption','CodexChoiceLogo','ClaudeChoiceLogo','PlanBadge','PlanText','ClaudeSetupPanel','ClaudeSetupText','EnableClaudeButton','DetailStatusDot','StatusText','NoticePanel','NoticeText','CardsGrid','SecondaryColumn','ActivityRows','ActivityNote','SourceLabel','VersionLabel','RefreshButton')) {
        $view.Controls[$controlName] = $detailWindow.FindName($controlName)
    }
    $view.Controls.VersionLabel.Text = 'Codex Pill ' + $script:PillVersion
    $logoPath = Join-Path $script:PillDirectory 'assets\CodexPill.png'
    if (Test-Path -LiteralPath $logoPath -PathType Leaf) {
        $logoStream = $null
        try {
            $logoStream = [IO.File]::OpenRead($logoPath)
            $logoImage = [Windows.Media.Imaging.BitmapImage]::new()
            $logoImage.BeginInit()
            $logoImage.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $logoImage.DecodePixelWidth = 96
            $logoImage.StreamSource = $logoStream
            $logoImage.EndInit()
            $logoImage.Freeze()
            $view.Controls.DetailLogo.Source = $logoImage
            $view.Main.Icon = $logoImage
            $view.Detail.Icon = $logoImage
        } catch { Write-PillLog $_ }
        finally { if ($null -ne $logoStream) { $logoStream.Dispose() } }
    }
    # Logos vectoriels extraits des SVG officiels fournis : nets à toute taille,
    # sans fond carré. Le tracé principal de chaque fichier est le symbole.
    $view.ProviderLogos = @{}
    foreach ($logoEntry in @(@('Codex', 'OpenAI.original.svg'), @('Claude', 'Claude.original.svg'))) {
        try {
            $svgPath = Join-Path $script:PillDirectory ('assets\providers\' + $logoEntry[1])
            $svgText = [IO.File]::ReadAllText($svgPath, [Text.Encoding]::UTF8)
            $pathMatch = [regex]::Match($svgText, '(?s)<path[^>]*?\sd="([^"]+)"')
            if ($pathMatch.Success) {
                $geometry = [Windows.Media.Geometry]::Parse(($pathMatch.Groups[1].Value -replace '\s+', ' '))
                $geometry.Freeze()
                $view.ProviderLogos[$logoEntry[0]] = $geometry
                $view.Controls[$logoEntry[0] + 'ChoiceLogo'].Data = $geometry
            }
        } catch { Write-PillLog $_ }
    }
    Set-PillShape $view.Controls.PillShape -Double $true
    return $view
}

function Set-PillShape {
    param($PathElement, [bool]$Double)
    # Silhouette de la pastille : un disque de 52 px, ou deux disques espacés de
    # 48 px réunis en un seul contour (le « 8 » horizontal). Le contour de 1 px est
    # décalé d'un demi-pixel pour rester net.
    $discRadius = 25.5
    $firstDisc = [Windows.Media.EllipseGeometry]::new([Windows.Point]::new(26, 26), $discRadius, $discRadius)
    $shapeGeometry = $firstDisc
    if ($Double) {
        $secondDisc = [Windows.Media.EllipseGeometry]::new([Windows.Point]::new(74, 26), $discRadius, $discRadius)
        $shapeGeometry = [Windows.Media.CombinedGeometry]::new([Windows.Media.GeometryCombineMode]::Union, $firstDisc, $secondDisc)
    }
    $shapeGeometry.Freeze()
    $PathElement.Data = $shapeGeometry
}

function Get-PillScale {
    $scaleValue = 1.35
    if ($null -ne $script:PillSettings -and $null -ne $script:PillSettings.Scale) { $scaleValue = [Math]::Max(0.8, [Math]::Min(2.5, [double]$script:PillSettings.Scale)) }
    return $scaleValue
}

function Set-PillScale {
    param([double]$Scale)
    # Agrandissement vectoriel de toute la pastille (ombre comprise) : le rendu reste net.
    $script:PillSettings.Scale = $Scale
    $script:PillUi.Controls.PillScale.ScaleX = $Scale
    $script:PillUi.Controls.PillScale.ScaleY = $Scale
    foreach ($sizeEntry in @($script:PillUi.Controls.SizeMenus)) { if ($null -ne $sizeEntry) { $sizeEntry.IsChecked = [Math]::Abs([double]$sizeEntry.Tag - $Scale) -lt 0.01 } }
}

function Get-PillAccent {
    $accentColor = $script:PillUi.Accents[[string]$script:PillSettings.Provider]
    if (-not $accentColor) { $accentColor = $script:PillUi.Theme.Good }
    return $accentColor
}

function Update-PillProviderControls {
    if ($null -eq $script:PillUi) { return }
    $providerName = [string]$script:PillSettings.Provider
    $isClaude = $providerName -eq 'Claude'
    $viewControls = $script:PillUi.Controls
    $script:PillUi.Theme.Accent = Get-PillAccent
    [Windows.Automation.AutomationProperties]::SetName($viewControls.PillSurface, ('Quotas restants ' + $providerName + '. Cliquer pour les détails, faire glisser pour déplacer.'))
    $viewControls.CodexOption.IsChecked = -not $isClaude
    $viewControls.ClaudeOption.IsChecked = $isClaude
    $viewControls.ActivityNote.Text = if ($isClaude) { 'Conversations Claude Code de ce PC. Les quotas couvrent tout le compte.' } else { 'Tokens de session ; ils ne mesurent pas la part du quota.' }
    $viewControls.EnableClaudeButton.Visibility = if ($script:PillClaudeIntegration.Status -ne 'Enabled') { 'Visible' } else { 'Collapsed' }
    if ($null -ne $viewControls.ClaudeEnableMenu) {
        $viewControls.ClaudeEnableMenu.Visibility = if ($isClaude) { 'Visible' } else { 'Collapsed' }
        $viewControls.ClaudeDisableMenu.Visibility = if ($isClaude) { 'Visible' } else { 'Collapsed' }
        $viewControls.ClaudeEnableMenu.IsEnabled = $script:PillClaudeIntegration.Status -ne 'Enabled'
        $viewControls.ClaudeDisableMenu.IsEnabled = $script:PillClaudeIntegration.Status -eq 'Enabled'
    }
}

function Format-PillDuration {
    param([double]$Seconds)
    if ($Seconds -le 0) { return 'maintenant' }
    $minutesCount = [int][Math]::Ceiling($Seconds / 60)
    if ($minutesCount -ge 1440) { return ('{0} j {1} h' -f [int][Math]::Floor($minutesCount / 1440), [int][Math]::Floor(($minutesCount % 1440) / 60)) }
    if ($minutesCount -ge 60) { return ('{0} h {1:00}' -f [int][Math]::Floor($minutesCount / 60), ($minutesCount % 60)) }
    return ('{0} min' -f $minutesCount)
}

function Format-PillWindow {
    param($WindowData, [string]$Fallback, [switch]$Short)
    if ($null -eq $WindowData -or $null -eq $WindowData.WindowMinutes -or $WindowData.WindowMinutes -le 0) { return $Fallback }
    $windowLength = [double]$WindowData.WindowMinutes
    if ($windowLength -eq 10080) { if ($Short) { return '7 J' }; return 'Semaine' }
    if ($windowLength -eq 300 -and -not $Short) { return 'Session · 5 h' }
    if (($windowLength % 1440) -eq 0) { if ($Short) { return ('{0} J' -f ($windowLength / 1440)) }; return ('{0} jours' -f ($windowLength / 1440)) }
    if (($windowLength % 60) -eq 0) { if ($Short) { return ('{0} H' -f ($windowLength / 60)) }; return ('{0} heures' -f ($windowLength / 60)) }
    return ('{0} min' -f $windowLength)
}

function Get-PillWindowState {
    param($WindowData)
    if ($null -eq $WindowData) { return 'Missing' }
    if ($WindowData.IsExpired -or ($null -ne $WindowData.ResetAt -and [DateTimeOffset]$WindowData.ResetAt -le [DateTimeOffset]::UtcNow)) { return 'Expired' }
    if ($WindowData.IsStale -or ($null -ne $WindowData.ObservedAt -and ([DateTimeOffset]::UtcNow - [DateTimeOffset]$WindowData.ObservedAt).TotalMinutes -ge 15)) { return 'Stale' }
    return 'Ready'
}

function Set-PillRing {
    param($PathElement, [double]$Fraction)
    # Arc dessiné dans le sens horaire depuis midi ; épaisseur incluse dans le rayon.
    $ringSize = [double]$PathElement.Width
    $ringRadius = ($ringSize - [double]$PathElement.StrokeThickness) / 2
    $ringCenter = $ringSize / 2
    if ($Fraction -le 0.004) { $PathElement.Data = $null; return }
    if ($Fraction -ge 0.999) { $PathElement.Data = [Windows.Media.EllipseGeometry]::new([Windows.Point]::new($ringCenter, $ringCenter), $ringRadius, $ringRadius); return }
    $angle = 2 * [Math]::PI * $Fraction
    $startPoint = [Windows.Point]::new($ringCenter, $ringCenter - $ringRadius)
    $endPoint = [Windows.Point]::new($ringCenter + $ringRadius * [Math]::Sin($angle), $ringCenter - $ringRadius * [Math]::Cos($angle))
    $arcSegment = [Windows.Media.ArcSegment]::new($endPoint, [Windows.Size]::new($ringRadius, $ringRadius), 0, ($Fraction -gt 0.5), [Windows.Media.SweepDirection]::Clockwise, $true)
    $figure = [Windows.Media.PathFigure]::new()
    $figure.StartPoint = $startPoint
    $figure.IsClosed = $false
    [void]$figure.Segments.Add($arcSegment)
    $geometry = [Windows.Media.PathGeometry]::new()
    [void]$geometry.Figures.Add($figure)
    $geometry.Freeze()
    $PathElement.Data = $geometry
}

function Set-PillMeter {
    param([string]$Prefix, $WindowData, [string]$Fallback)
    $viewControls = $script:PillUi.Controls
    $windowState = Get-PillWindowState $WindowData
    # Sous le nombre du rond : durée courte (« 5 H », « 7 J »), rien tant qu'elle est inconnue.
    $viewControls[$Prefix + 'Label'].Text = Format-PillWindow $WindowData '' -Short
    $viewControls[$Prefix + 'Label'].Visibility = if ($viewControls[$Prefix + 'Label'].Text) { 'Visible' } else { 'Collapsed' }
    $viewControls[$Prefix + 'Title'].Text = Format-PillWindow $WindowData $Fallback
    $numberText = '—'; $unitText = ''; $remainingFraction = 0.0; $isCritical = $false
    $meterColor = $script:PillUi.Theme.Quiet
    $resetText = "En attente d’une mesure"
    $detailText = ''
    $viewControls[$Prefix + 'Card'].ToolTip = $null
    if ($windowState -eq 'Expired') {
        $resetText = 'Échéance passée'
        $detailText = "Attente d’une nouvelle mesure"
    } elseif ($windowState -ne 'Missing') {
        $usedValue = [Math]::Max(0, [Math]::Min(100, [double]$WindowData.UsedPercent))
        $remainingValue = 100 - $usedValue
        $remainingFraction = $remainingValue / 100
        $numberText = '{0:0}' -f [Math]::Floor($remainingValue)
        $unitText = ' %'
        $meterColor = Get-PillAccent
        $isCritical = $remainingValue -le 10
        if ($isCritical) { $meterColor = $script:PillUi.Theme.Danger }
        elseif ($remainingValue -le 25) { $meterColor = $script:PillUi.Theme.Warning }
        $frenchCulture = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
        $usedText = '{0:0} % utilisés' -f [Math]::Ceiling($usedValue)
        if ($null -ne $WindowData.ResetAt) {
            $resetTime = [DateTimeOffset]$WindowData.ResetAt
            $resetLocal = $resetTime.ToLocalTime()
            $durationText = Format-PillDuration (($resetTime - [DateTimeOffset]::UtcNow).TotalSeconds)
            $resetText = 'Réinit. dans ' + $durationText
            $detailText = if ($resetLocal.Date -eq [DateTimeOffset]::Now.Date) { 'à ' + $resetLocal.ToString('HH:mm', $frenchCulture) } else { $resetLocal.ToString('ddd d MMM · HH:mm', $frenchCulture) }
            $viewControls[$Prefix + 'Card'].ToolTip = $usedText + ' · réinitialisation le ' + $resetLocal.ToString('dddd d MMMM yyyy à HH:mm', $frenchCulture)
        } else {
            $resetText = 'Échéance non fournie'
            $viewControls[$Prefix + 'Card'].ToolTip = $usedText
        }
        if ($windowState -eq 'Stale') { $detailText = 'Mesure ancienne' }
    }
    $viewControls[$Prefix + 'ValueNumber'].Text = $numberText
    # Dans le rond, le « % » est collé au nombre pour tenir dans l'anneau.
    $viewControls[$Prefix + 'ValueUnit'].Text = $unitText.Trim()
    $viewControls[$Prefix + 'BigNumber'].Text = $numberText
    $viewControls[$Prefix + 'BigUnit'].Text = $unitText
    $viewControls[$Prefix + 'Reset'].Text = $resetText
    $viewControls[$Prefix + 'Remaining'].Text = $detailText
    $foregroundColor = $script:PillUi.Theme.Text
    if ($windowState -ne 'Ready') { $foregroundColor = $script:PillUi.Theme.Muted }
    # Quota critique : le nombre passe lui aussi en rouge pour sauter aux yeux.
    elseif ($isCritical) { $foregroundColor = $script:PillUi.Theme.Danger }
    $viewControls[$Prefix + 'ValueNumber'].Foreground = Get-PillBrush $foregroundColor
    $viewControls[$Prefix + 'BigNumber'].Foreground = Get-PillBrush $foregroundColor
    # Les anneaux (pastille et panneau) représentent la part RESTANTE : ils se vident à l'usage.
    $ringOpacity = if ($windowState -eq 'Stale') { 0.45 } else { 1.0 }
    $ringGlow = $null
    if ($isCritical -and $windowState -eq 'Ready') {
        # Halo rouge autour de l'anneau quand il ne reste presque plus rien.
        $ringGlow = [Windows.Media.Effects.DropShadowEffect]::new()
        $ringGlow.Color = [Windows.Media.ColorConverter]::ConvertFromString($script:PillUi.Theme.Danger)
        $ringGlow.ShadowDepth = 0; $ringGlow.BlurRadius = 9; $ringGlow.Opacity = 0.85
        $ringGlow.Freeze()
    }
    foreach ($ringName in @('PillRing', 'Ring')) {
        $ringElement = $viewControls[$Prefix + $ringName]
        $ringElement.Stroke = Get-PillBrush $meterColor
        $ringElement.Opacity = $ringOpacity
        $ringElement.Effect = $ringGlow
        Set-PillRing $ringElement $remainingFraction
    }
}

function New-PillText {
    param([string]$Text, [double]$Size = 12, [string]$Color = '#F2F3F5')
    $textElement = [System.Windows.Controls.TextBlock]::new()
    $textElement.Text = $Text
    $textElement.FontSize = $Size
    $textElement.Foreground = Get-PillBrush $Color
    return $textElement
}

function Find-PillProjectIcon {
    param([string]$Directory)
    # Recherche volontairement limitée aux emplacements et noms standard d'une
    # icône d'application, pour ne jamais afficher une image interne au projet.
    if ([string]::IsNullOrWhiteSpace($Directory) -or -not [IO.Directory]::Exists($Directory)) { return $null }
    $projectKey = ([IO.Path]::GetFileName($Directory.TrimEnd('\', '/')) -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
    $bestPath = $null; $bestScore = 0
    foreach ($folderName in @('', 'assets', 'public', 'static', 'resources', 'build', 'res', 'icons', 'images', 'img', 'web', 'app', 'src\assets', 'public\icons', 'public\images', 'assets\icons', 'assets\images', 'src-tauri\icons', 'build\icons')) {
        $folderPath = if ($folderName) { Join-Path $Directory $folderName } else { $Directory }
        if (-not [IO.Directory]::Exists($folderPath)) { continue }
        try { $candidateFiles = @([IO.Directory]::GetFiles($folderPath) | Select-Object -First 300) } catch { continue }
        foreach ($candidatePath in $candidateFiles) {
            $extension = [IO.Path]::GetExtension($candidatePath).ToLowerInvariant()
            if ($extension -notin @('.png', '.ico', '.jpg', '.jpeg')) { continue }
            $baseName = [IO.Path]::GetFileNameWithoutExtension($candidatePath).ToLowerInvariant()
            $score = 0
            if ($projectKey -and ($baseName -replace '[^a-z0-9]', '') -eq $projectKey) { $score = 100 }
            elseif ($baseName -in @('icon', 'app-icon', 'appicon', 'app_icon', 'icon-app')) { $score = 90 }
            elseif ($baseName -match '^(apple-touch-icon|android-chrome-(192|256|512)|icon-(128|192|256|512)|icon@\dx|icon_(256|512)|(128|256|512)x(128|256|512))') { $score = 85 }
            elseif ($baseName -match '^favicon') { $score = 70 }
            elseif ($baseName -in @('logo', 'app-logo', 'applogo', 'logo-app')) { $score = 60 }
            elseif ($extension -eq '.ico' -and $folderName -in @('', 'assets', 'public', 'build', 'resources')) { $score = 50 }
            if ($score -eq 0) { continue }
            if ($extension -eq '.png') { $score += 4 } elseif ($extension -eq '.ico') { $score += 2 }
            if ($folderName -eq '') { $score += 1 }
            if ($score -le $bestScore) { continue }
            try { if (([IO.FileInfo]::new($candidatePath)).Length -gt 2097152) { continue } } catch { continue }
            $bestPath = $candidatePath; $bestScore = $score
        }
    }
    return $bestPath
}

function Get-PillProjectIcon {
    param([string]$Directory)
    if ([string]::IsNullOrWhiteSpace($Directory)) { return $null }
    if ($null -eq $script:PillUi.ProjectIcons) { $script:PillUi.ProjectIcons = @{} }
    $cacheKey = $Directory.ToLowerInvariant()
    if ($script:PillUi.ProjectIcons.ContainsKey($cacheKey)) { return $script:PillUi.ProjectIcons[$cacheKey] }
    $iconImage = $null
    $iconPath = Find-PillProjectIcon $Directory
    if ($iconPath) {
        $iconStream = $null
        try {
            $iconStream = [IO.FileStream]::new($iconPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            if ([IO.Path]::GetExtension($iconPath) -ieq '.ico') {
                # Une icône Windows contient plusieurs tailles : la plus grande est la plus nette.
                $decoder = [Windows.Media.Imaging.BitmapDecoder]::Create($iconStream, [Windows.Media.Imaging.BitmapCreateOptions]::None, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
                $iconImage = @($decoder.Frames | Sort-Object { $_.PixelWidth } -Descending)[0]
            } else {
                $bitmapImage = [Windows.Media.Imaging.BitmapImage]::new()
                $bitmapImage.BeginInit()
                $bitmapImage.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bitmapImage.DecodePixelWidth = 64
                $bitmapImage.StreamSource = $iconStream
                $bitmapImage.EndInit()
                $iconImage = $bitmapImage
            }
            if ($iconImage.CanFreeze) { $iconImage.Freeze() }
        } catch { $iconImage = $null }
        finally { if ($null -ne $iconStream) { $iconStream.Dispose() } }
    }
    $script:PillUi.ProjectIcons[$cacheKey] = $iconImage
    return $iconImage
}

function Update-PillActivity {
    param($Snapshot)
    $activityItems = @($Snapshot.Activity | Select-Object -First 3)
    $activityStamp = (@($activityItems | ForEach-Object { '{0}:{1}:{2}' -f $_.SessionId, $_.LastActivity, $_.TotalTokens }) -join '|')
    # La minute est incluse pour garder les âges à jour sans recréer chaque tick.
    $activityStamp += ':' + [DateTimeOffset]::UtcNow.ToString('yyyyMMddHHmm') + ':' + $script:PillSettings.Provider
    if ($activityStamp -eq $script:PillUi.ActivitySignature) { return }
    $script:PillUi.ActivitySignature = $activityStamp
    $rowsPanel = $script:PillUi.Controls.ActivityRows
    $rowsPanel.Children.Clear()
    if ($activityItems.Count -eq 0) {
        $emptyElement = New-PillText 'Aucune session locale récente.' 11 '#7C808B'
        $emptyElement.Margin = [Windows.Thickness]::new(2, 10, 0, 2)
        [void]$rowsPanel.Children.Add($emptyElement)
        return
    }
    $accentColor = Get-PillAccent
    foreach ($activityItem in $activityItems) {
        $rowElement = [System.Windows.Controls.Grid]::new()
        $rowElement.Margin = [Windows.Thickness]::new(0, 10, 0, 0)
        foreach ($columnWidth in @([Windows.GridLength]::Auto, [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star), [Windows.GridLength]::Auto)) {
            $columnObject = [System.Windows.Controls.ColumnDefinition]::new(); $columnObject.Width = $columnWidth
            [void]$rowElement.ColumnDefinitions.Add($columnObject)
        }
        $projectText = if ([string]::IsNullOrWhiteSpace([string]$activityItem.Project)) { 'Sans projet' } else { [string]$activityItem.Project }
        # Pastille d'initiale, teintée par l'accent du fournisseur.
        $avatarElement = [System.Windows.Controls.Border]::new()
        $avatarElement.Width = 30; $avatarElement.Height = 30
        $avatarElement.CornerRadius = [Windows.CornerRadius]::new(9)
        $avatarElement.Background = Get-PillBrush $accentColor 0.13
        $avatarElement.BorderBrush = Get-PillBrush $accentColor 0.22
        $avatarElement.BorderThickness = [Windows.Thickness]::new(1)
        $projectDirectory = if ($activityItem.PSObject.Properties['Cwd']) { [string]$activityItem.Cwd } else { '' }
        $projectIcon = Get-PillProjectIcon $projectDirectory
        if ($null -ne $projectIcon) {
            # Icône de l'application du projet sur une tuile neutre.
            $avatarElement.Background = Get-PillBrush '#202127'
            $avatarElement.BorderBrush = Get-PillBrush '#2D2F36'
            $iconElement = [System.Windows.Controls.Image]::new()
            $iconElement.Source = $projectIcon
            $iconElement.Width = 20; $iconElement.Height = 20
            [Windows.Media.RenderOptions]::SetBitmapScalingMode($iconElement, [Windows.Media.BitmapScalingMode]::HighQuality)
            $avatarElement.Child = $iconElement
        } else {
            $initialElement = New-PillText $projectText.Substring(0, 1).ToUpperInvariant() 12 $accentColor
            $initialElement.FontWeight = 'SemiBold'
            $initialElement.HorizontalAlignment = 'Center'; $initialElement.VerticalAlignment = 'Center'
            $avatarElement.Child = $initialElement
        }
        [void]$rowElement.Children.Add($avatarElement)
        $labelPanel = [System.Windows.Controls.StackPanel]::new()
        $labelPanel.Margin = [Windows.Thickness]::new(11, 0, 10, 0)
        $labelPanel.VerticalAlignment = 'Center'
        [Windows.Controls.Grid]::SetColumn($labelPanel, 1)
        $nameElement = New-PillText $projectText 12
        $nameElement.FontWeight = 'Medium'
        $nameElement.TextTrimming = 'CharacterEllipsis'
        $nameElement.ToolTip = if ($activityItem.PSObject.Properties['Cwd'] -and $activityItem.Cwd) { [string]$activityItem.Cwd } else { $projectText }
        [void]$labelPanel.Children.Add($nameElement)
        $ageText = 'Session locale'
        if ($null -ne $activityItem.LastActivity) {
            $ageSeconds = ([DateTimeOffset]::UtcNow - [DateTimeOffset]$activityItem.LastActivity).TotalSeconds
            $ageText = if ($ageSeconds -lt 60) { "À l’instant" } else { 'Il y a ' + (Format-PillDuration $ageSeconds) }
        }
        $ageElement = New-PillText $ageText 10.5 '#757984'
        $ageElement.Margin = [Windows.Thickness]::new(0, 1, 0, 0)
        [void]$labelPanel.Children.Add($ageElement)
        [void]$rowElement.Children.Add($labelPanel)
        $valueLabel = ''
        if ($null -ne $activityItem.TotalTokens) {
            $tokenCount = [double]$activityItem.TotalTokens
            if ($tokenCount -ge 1000000) { $valueLabel = ('{0:0.#} M tok.' -f ($tokenCount / 1000000)) }
            elseif ($tokenCount -ge 1000) { $valueLabel = ('{0:0.#} k tok.' -f ($tokenCount / 1000)) }
            else { $valueLabel = ('{0:0} tok.' -f $tokenCount) }
        } elseif ($activityItem.PSObject.Properties['Detail'] -and $activityItem.Detail) { $valueLabel = [string]$activityItem.Detail }
        if ($valueLabel) {
            $valueBadge = [System.Windows.Controls.Border]::new()
            $valueBadge.CornerRadius = [Windows.CornerRadius]::new(6)
            $valueBadge.Padding = [Windows.Thickness]::new(7, 2, 7, 3)
            $valueBadge.Background = Get-PillBrush '#202127'
            $valueBadge.BorderBrush = Get-PillBrush '#2B2D33'
            $valueBadge.BorderThickness = [Windows.Thickness]::new(1)
            $valueBadge.VerticalAlignment = 'Center'
            $valueBadge.Child = New-PillText $valueLabel 10.5 '#A0A3AD'
            [Windows.Controls.Grid]::SetColumn($valueBadge, 2)
            [void]$rowElement.Children.Add($valueBadge)
        }
        [void]$rowsPanel.Children.Add($rowElement)
    }
}

function Get-PillSnapshotValue {
    param($Snapshot, [string]$Name)
    if ($null -eq $Snapshot) { return $null }
    $property = $Snapshot.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Update-PillUi {
    param($Snapshot)
    if ($null -eq $Snapshot) { return }
    if ($null -ne $Snapshot.Provider -and $Snapshot.Provider -ne $script:PillSettings.Provider) { return }
    $isClaude = $script:PillSettings.Provider -eq 'Claude'
    $expectedSource = if ($isClaude) { $script:PillClaudeHome } else { $script:PillCodexHome }
    $snapshotSource = Get-PillSnapshotValue $Snapshot 'SourceHome'
    if ($null -ne $snapshotSource -and $snapshotSource -ne $expectedSource) { return }
    $integrationState = Get-PillSnapshotValue $Snapshot 'IntegrationState'
    if ($isClaude -and $null -ne $integrationState -and $integrationState -ne $script:PillClaudeIntegration.Status) {
        $script:PillClaudeIntegration = [pscustomobject]@{ Status = $integrationState }
        Update-PillProviderControls
    }
    $script:PillSnapshot = $Snapshot
    $viewControls = $script:PillUi.Controls
    $displayPrimary = $Snapshot.Primary
    $displaySecondary = $Snapshot.Secondary
    if ($null -eq $displayPrimary -and $null -ne $displaySecondary) { $displayPrimary = $displaySecondary; $displaySecondary = $null }
    Set-PillMeter 'Primary' $displayPrimary 'Session'
    Set-PillMeter 'Secondary' $displaySecondary 'Semaine'
    $singleQuota = ($null -ne $displayPrimary -and $null -eq $displaySecondary)
    $secondVisibility = if ($singleQuota) { 'Collapsed' } else { 'Visible' }
    $viewControls.SecondaryCard.Visibility = $secondVisibility
    # La pastille ne montre deux ronds que si les deux quotas sont connus ; sinon un seul rond.
    $doubleRing = ($null -ne $displayPrimary -and $null -ne $displaySecondary)
    $viewControls.SecondaryGroup.Visibility = if ($doubleRing) { 'Visible' } else { 'Collapsed' }
    Set-PillShape $viewControls.PillShape -Double $doubleRing
    $viewControls.SecondaryColumn.Width = if ($singleQuota) { [Windows.GridLength]::new(0) } else { [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star) }
    $viewControls.PrimaryCard.Margin = if ($singleQuota) { [Windows.Thickness]::new(0) } else { [Windows.Thickness]::new(0, 0, 5, 0) }

    $planName = [string](Get-PillSnapshotValue $Snapshot 'Plan')
    $accentColor = Get-PillAccent
    if ($planName) {
        $viewControls.PlanText.Text = $(if ($isClaude) { 'Claude ' } else { '' }) + $planName
        $viewControls.PlanText.Foreground = Get-PillBrush $accentColor
        $viewControls.PlanBadge.Background = Get-PillBrush $accentColor 0.12
        $viewControls.PlanBadge.Visibility = 'Visible'
    } else { $viewControls.PlanBadge.Visibility = 'Collapsed' }

    $primaryState = Get-PillWindowState $displayPrimary
    $secondaryState = Get-PillWindowState $displaySecondary
    $quotaSource = [string](Get-PillSnapshotValue $Snapshot 'Source')
    $apiError = [string](Get-PillSnapshotValue $Snapshot 'ApiError')
    $statusMessage = 'Lecture des données…'
    $noticeMessage = ''
    $setupMessage = ''
    $statusColor = $script:PillUi.Theme.Quiet
    if ($script:PillDemoMode) {
        $statusMessage = 'Aperçu · données de démonstration'
        $noticeMessage = 'Mode démo : les valeurs de cette fenêtre sont fictives.'
        $statusColor = $script:PillUi.Theme.Warning
    } elseif ($Snapshot.Status -eq 'Missing' -and $isClaude) {
        $statusMessage = 'Connexion Claude introuvable'
        $setupMessage = 'Ouvre Claude Code (extension VS Code ou terminal) et connecte-toi à ton compte. Le widget lira ensuite tes quotas automatiquement, sans rien saisir.'
    } elseif ($Snapshot.Status -eq 'Missing') {
        $statusMessage = 'Dossier de sessions introuvable'
        $noticeMessage = 'Ouvre une session Codex locale ou choisis le dossier .codex dans le menu de la pastille.'
    } elseif ($Snapshot.Status -eq 'Error') {
        $statusMessage = 'Lecture momentanément indisponible'
        $noticeMessage = 'Les données sont inaccessibles. Le widget réessaie automatiquement.'
        $statusColor = $script:PillUi.Theme.Warning
    } elseif ($null -eq $Snapshot.Primary -and $null -eq $Snapshot.Secondary) {
        $statusMessage = 'En attente de ' + $script:PillSettings.Provider
        if ($isClaude) {
            $noticeMessage = switch ($apiError) {
                'Expired' { "Le renouvellement de la connexion Claude n’a pas abouti. Nouvel essai automatique dans 2 minutes ; inutile de redémarrer Claude." }
                'Refreshing' { 'Renouvellement de la connexion Claude en cours…' }
                'LoginRequired' { "La connexion Claude Code de VS Code n’est plus valide. Tape /login dans Claude Code (VS Code ou terminal) quand tu as un moment ; l’application de bureau n’est pas concernée." }
                'RateLimited' { "Le service d’usage limite temporairement les demandes. Nouvelle tentative dans quelques minutes." }
                'Unavailable' { "Le service d’usage de Claude ne répond pas. Vérifie la connexion Internet ; nouvelle tentative automatique." }
                default { 'Interrogation du compte Claude en cours…' }
            }
        } else { $noticeMessage = "Aucun quota dans les journaux lus. Une nouvelle interaction Codex peut produire une mesure ; certains modes de connexion n’en fournissent pas." }
    } else {
        $sourceWord = if ($quotaSource -eq 'Account') { 'En direct' } else { 'Mesure locale' }
        if ($null -ne $Snapshot.LastUpdated) {
            $measurementAge = ([DateTimeOffset]::UtcNow - [DateTimeOffset]$Snapshot.LastUpdated).TotalSeconds
            $statusMessage = if ($measurementAge -lt 60) { $sourceWord + " · à l’instant" } else { $sourceWord + ' · il y a ' + (Format-PillDuration $measurementAge) }
        }
        $statusColor = $script:PillUi.Theme.Live
        if ($primaryState -eq 'Expired' -or $secondaryState -eq 'Expired') {
            $statusColor = $script:PillUi.Theme.Warning
            $noticeMessage = "Une échéance est passée. Le quota reste inconnu jusqu’à la prochaine mesure."
        } elseif ($primaryState -eq 'Stale' -or $secondaryState -eq 'Stale') {
            $statusColor = $script:PillUi.Theme.Warning
            $noticeMessage = if ($isClaude -and $apiError -eq 'LoginRequired') { "Dernière mesure connue : la connexion Claude Code de VS Code n’est plus valide. Tape /login dans Claude Code quand tu as un moment." }
                elseif ($isClaude -and ($apiError -eq 'Expired' -or $apiError -eq 'Refreshing')) { "Dernière mesure connue : renouvellement de la connexion Claude en cours, nouvel essai automatique." }
                else { 'Dernière mesure connue. La consommation sur un autre appareil peut ne pas encore apparaître ici.' }
        }
    }
    $viewControls.StatusText.Text = $statusMessage
    $viewControls.StatusDot.Fill = Get-PillBrush $statusColor
    # Par discrétion, la pastille n'affiche son point d'état que s'il y a quelque chose à signaler.
    $viewControls.StatusDot.Visibility = if ($statusColor -eq $script:PillUi.Theme.Live) { 'Collapsed' } else { 'Visible' }
    $viewControls.DetailStatusDot.Fill = Get-PillBrush $statusColor
    $viewControls.NoticeText.Text = $noticeMessage
    $viewControls.NoticePanel.Visibility = if ($noticeMessage) { 'Visible' } else { 'Collapsed' }
    $viewControls.ClaudeSetupText.Text = $setupMessage
    $viewControls.ClaudeSetupPanel.Visibility = if ($setupMessage) { 'Visible' } else { 'Collapsed' }
    $viewControls.SourceLabel.Text = if ($isClaude) {
        if ($quotaSource -eq 'StatusLine') { 'Source : barre de statut Claude Code' } else { 'Source : compte Claude (comme /usage)' }
    } else { 'Source : journaux Codex locaux' }
    $viewControls.SourceLabel.ToolTip = if ($isClaude) { $script:PillClaudeHome } else { $script:PillCodexHome }
    $tooltipText = $script:PillSettings.Provider + ' · quotas restants · ' + $statusMessage
    foreach ($windowEntry in @(@('Primary', $displayPrimary), @('Secondary', $displaySecondary))) {
        if ($null -ne $windowEntry[1]) {
            $tooltipText += "`n" + $viewControls[$windowEntry[0] + 'Title'].Text + ' : ' + $viewControls[$windowEntry[0] + 'BigNumber'].Text + $viewControls[$windowEntry[0] + 'BigUnit'].Text + ' restant · ' + $viewControls[$windowEntry[0] + 'Reset'].Text
        }
    }
    $viewControls.PillSurface.ToolTip = $tooltipText + "`nClic : détails · Glisser : déplacer · Clic droit : menu"
    Update-PillActivity $Snapshot
}

function Move-PillIntoView {
    param([switch]$Reset)
    $windowObject = $script:PillUi.Main
    $windowObject.UpdateLayout()
    $windowWidth = [Math]::Max(40, $windowObject.ActualWidth)
    $windowHeight = [Math]::Max(40, $windowObject.ActualHeight)
    if ($Reset -or [double]::IsNaN($windowObject.Left) -or [double]::IsNaN($windowObject.Top)) {
        $workRect = [Windows.SystemParameters]::WorkArea
        $windowObject.Left = $workRect.Right - $windowWidth - 12
        $windowObject.Top = $workRect.Top + 12
        return
    }
    # Les limites d'écran sont en pixels physiques : conversion selon le DPI de la fenêtre.
    $windowHandle = [Windows.Interop.WindowInteropHelper]::new($windowObject).Handle
    if ($windowHandle -eq [IntPtr]::Zero) { return }
    $sourceObject = [Windows.Interop.HwndSource]::FromHwnd($windowHandle)
    $transformObject = $sourceObject.CompositionTarget.TransformToDevice
    $physicalRect = [Drawing.Rectangle]::new([int]($windowObject.Left * $transformObject.M11), [int]($windowObject.Top * $transformObject.M22), [int]($windowWidth * $transformObject.M11), [int]($windowHeight * $transformObject.M22))
    $visibleArea = 0
    foreach ($screenObject in [Windows.Forms.Screen]::AllScreens) {
        $intersection = [Drawing.Rectangle]::Intersect($physicalRect, $screenObject.WorkingArea)
        $visibleArea = [Math]::Max($visibleArea, $intersection.Width * $intersection.Height)
    }
    if ($visibleArea -lt ($physicalRect.Width * $physicalRect.Height * 0.65)) {
        $workRect = [Windows.SystemParameters]::WorkArea
        $windowObject.Left = $workRect.Right - $windowWidth - 12
        $windowObject.Top = $workRect.Top + 12
    }
}

function Test-PillOnRightHalf {
    param([double]$CenterX)
    # Vrai si ce point horizontal (unités WPF) est dans la moitié droite de l'écran de la pastille.
    $windowHandle = [Windows.Interop.WindowInteropHelper]::new($script:PillUi.Main).Handle
    if ($windowHandle -eq [IntPtr]::Zero) { return $false }
    $screenArea = [Windows.Forms.Screen]::FromHandle($windowHandle).WorkingArea
    $scaleObject = [Windows.Interop.HwndSource]::FromHwnd($windowHandle).CompositionTarget.TransformFromDevice
    return $CenterX -gt (($screenArea.Left + $screenArea.Width / 2) * $scaleObject.M11)
}

function Start-PillDetailAnimation {
    param([double]$FromOffset)
    # Apparition courte : fondu et léger glissement, comme un menu volant Windows.
    $easing = [Windows.Media.Animation.CubicEase]::new()
    $easing.EasingMode = [Windows.Media.Animation.EasingMode]::EaseOut
    $duration = [Windows.Duration]::new([TimeSpan]::FromMilliseconds(170))
    $fadeAnimation = [Windows.Media.Animation.DoubleAnimation]::new(0.0, 1.0, $duration)
    $fadeAnimation.EasingFunction = $easing
    $slideAnimation = [Windows.Media.Animation.DoubleAnimation]::new($FromOffset, 0.0, $duration)
    $slideAnimation.EasingFunction = $easing
    $script:PillUi.Controls.DetailSurface.BeginAnimation([Windows.UIElement]::OpacityProperty, $fadeAnimation)
    $script:PillUi.Controls.DetailShift.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $slideAnimation)
}

function Show-PillDetails {
    $detailObject = $script:PillUi.Detail
    if ($detailObject.IsVisible) { $detailObject.Hide(); return }
    if ($null -ne $script:PillSnapshot) { Update-PillUi $script:PillSnapshot }
    $detailObject.Topmost = $script:PillUi.Main.Topmost
    $detailObject.MaxHeight = [Math]::Max(260, [Windows.SystemParameters]::WorkArea.Height - 16)
    $script:PillUi.Controls.DetailScroll.MaxHeight = [Math]::Max(180, $detailObject.MaxHeight - 40)
    if ($null -eq $detailObject.Owner) { $detailObject.Owner = $script:PillUi.Main }
    $script:PillUi.Controls.DetailSurface.Opacity = 0
    $detailObject.Show()
    $detailObject.UpdateLayout()
    $mainHandle = [Windows.Interop.WindowInteropHelper]::new($script:PillUi.Main).Handle
    $activeScreen = [Windows.Forms.Screen]::FromHandle($mainHandle)
    $mainSource = [Windows.Interop.HwndSource]::FromHwnd($mainHandle)
    $scaleObject = $mainSource.CompositionTarget.TransformFromDevice
    $screenLeft = $activeScreen.WorkingArea.Left * $scaleObject.M11
    $screenTop = $activeScreen.WorkingArea.Top * $scaleObject.M22
    $screenRight = $activeScreen.WorkingArea.Right * $scaleObject.M11
    $screenBottom = $activeScreen.WorkingArea.Bottom * $scaleObject.M22
    # Panneau aligné sur le bord droit de la pastille (celle-ci est souvent en haut à droite).
    $alignedLeft = $script:PillUi.Main.Left + $script:PillUi.Main.ActualWidth - $detailObject.ActualWidth
    $detailObject.Left = [Math]::Max($screenLeft, [Math]::Min($alignedLeft, $screenRight - $detailObject.ActualWidth))
    # La marge transparente de la pastille (16 px, agrandie avec elle) est recouverte par le panneau.
    $pillMargin = 16 * (Get-PillScale) + 2
    $preferredTop = $script:PillUi.Main.Top + $script:PillUi.Main.ActualHeight - $pillMargin
    $slideFrom = -8.0
    if ($preferredTop + $detailObject.ActualHeight -gt $screenBottom) { $preferredTop = $script:PillUi.Main.Top - $detailObject.ActualHeight + $pillMargin; $slideFrom = 8.0 }
    $detailObject.Top = [Math]::Max($screenTop, [Math]::Min($preferredTop, $screenBottom - $detailObject.ActualHeight))
    Start-PillDetailAnimation $slideFrom
    [void]$detailObject.Activate()
}

function Add-PillMenuItem {
    param($Menu, [string]$Text, [scriptblock]$Action, [switch]$Checkable, [bool]$Checked = $false)
    $menuEntry = [Windows.Controls.MenuItem]::new()
    $menuEntry.Header = $Text
    $menuEntry.IsCheckable = $Checkable
    $menuEntry.IsChecked = $Checked
    $menuEntry.Add_Click($Action)
    [void]$Menu.Items.Add($menuEntry)
    return $menuEntry
}

function Connect-PillUi {
    $script:PillUi.Main.Topmost = [bool]$script:PillSettings.Topmost
    $script:PillUi.Controls.PillSurface.Opacity = [double]$script:PillSettings.Opacity
    $script:PillUi.Controls.PillSurface.Add_MouseEnter({ $script:PillUi.Controls.PillSurface.Opacity = 1.0 })
    $script:PillUi.Controls.PillSurface.Add_MouseLeave({ $script:PillUi.Controls.PillSurface.Opacity = [double]$script:PillSettings.Opacity })
    $script:PillDragStart = $null
    $script:PillWasDragged = $false
    $script:PillUi.Controls.PillSurface.Add_MouseLeftButtonDown({
        param($senderObject, $mouseEvent)
        $script:PillDragStart = $mouseEvent.GetPosition($script:PillUi.Main)
        $script:PillWasDragged = $false
    })
    $script:PillUi.Controls.PillSurface.Add_MouseMove({
        param($senderObject, $mouseEvent)
        if ($mouseEvent.LeftButton -ne [Windows.Input.MouseButtonState]::Pressed -or $null -eq $script:PillDragStart -or $script:PillWasDragged) { return }
        $cursorPoint = $mouseEvent.GetPosition($script:PillUi.Main)
        if ([Math]::Abs($cursorPoint.X - $script:PillDragStart.X) -lt [Windows.SystemParameters]::MinimumHorizontalDragDistance -and [Math]::Abs($cursorPoint.Y - $script:PillDragStart.Y) -lt [Windows.SystemParameters]::MinimumVerticalDragDistance) { return }
        $script:PillWasDragged = $true
        $script:PillUi.Detail.Hide()
        try { $script:PillUi.Main.DragMove(); Move-PillIntoView; Save-PillSettings } catch { Write-PillLog $_ }
        $script:PillDragStart = $null
    })
    $script:PillUi.Controls.PillSurface.Add_MouseLeftButtonUp({
        param($senderObject, $mouseEvent)
        if (-not $script:PillWasDragged -and $null -ne $script:PillDragStart) { try { Show-PillDetails } catch { Write-PillLog $_ } }
        $script:PillDragStart = $null
    })
    $script:PillUi.Controls.CloseDetailButton.Add_Click({ $script:PillUi.Detail.Hide() })
    $script:PillUi.Controls.HideWidgetButton.Add_Click({ Hide-PillWidget })
    $script:PillUi.Detail.Add_PreviewKeyDown({ param($senderObject, $keyEvent) if ($keyEvent.Key -eq 'Escape') { $script:PillUi.Detail.Hide(); $keyEvent.Handled = $true } })
    $script:PillUi.Detail.Add_Deactivated({
        $clickedPill = $script:PillUi.Main.IsMouseOver -and [Windows.Input.Mouse]::LeftButton -eq [Windows.Input.MouseButtonState]::Pressed
        if (-not $script:PillExiting -and -not $clickedPill -and $script:PillUi.Detail.IsVisible) { $script:PillUi.Detail.Hide() }
    })
    $script:PillUi.Detail.Add_Closing({
        param($senderObject, $closingEvent)
        if (-not $script:PillExiting) { $closingEvent.Cancel = $true; $script:PillUi.Detail.Hide() }
    })
    $script:PillUi.Controls.CodexOption.Add_Checked({ Set-PillProvider -Provider 'Codex' })
    $script:PillUi.Controls.ClaudeOption.Add_Checked({ Set-PillProvider -Provider 'Claude' })
    $script:PillUi.Controls.EnableClaudeButton.Add_Click({ Enable-PillClaudeTracking })
    $script:PillUi.Controls.RefreshButton.Add_Click({
        $script:PillUi.ProjectIcons = @{}; $script:PillUi.ActivitySignature = ''
        if ($script:PillSettings.Provider -eq 'Claude') { Refresh-PillClaudeIntegration; Update-PillProviderControls }
        Request-PillRefresh
    })
    $contextMenu = [Windows.Controls.ContextMenu]::new()
    $contextMenu.Resources = $script:PillUi.Main.Resources
    [void](Add-PillMenuItem $contextMenu 'Afficher les détails' { try { Show-PillDetails } catch { Write-PillLog $_ } })
    [void](Add-PillMenuItem $contextMenu 'Masquer la pastille' { Hide-PillWidget })
    [void](Add-PillMenuItem $contextMenu 'Actualiser les mesures' { Request-PillRefresh })
    [void]$contextMenu.Items.Add([Windows.Controls.Separator]::new())
    [void](Add-PillMenuItem $contextMenu 'Toujours au premier plan' {
        param($senderObject, $clickEvent)
        $script:PillSettings.Topmost = [bool]$senderObject.IsChecked
        $script:PillUi.Main.Topmost = $script:PillSettings.Topmost
        $script:PillUi.Detail.Topmost = $script:PillSettings.Topmost
        Save-PillSettings
        Update-PillTray
    } -Checkable -Checked $script:PillSettings.Topmost)
    [void](Add-PillMenuItem $contextMenu 'Masquer la fenêtre de commande' {
        param($senderObject, $clickEvent)
        $previousConsolePreference = [bool]$script:PillSettings.HideConsole
        try {
            Set-PillConsoleHidden -Hidden ([bool]$senderObject.IsChecked)
            Save-PillSettings
            Update-PillTray
        } catch {
            $senderObject.IsChecked = $previousConsolePreference
            Write-PillLog $_
            [void][Windows.MessageBox]::Show('La fenêtre de commande ne peut pas être modifiée. Consulte le journal depuis le menu.', 'Codex Pill')
        }
    } -Checkable -Checked $script:PillSettings.HideConsole)
    [void](Add-PillMenuItem $contextMenu 'Démarrer avec Windows' {
        param($senderObject, $clickEvent)
        try { Set-PillStartup -Enabled ([bool]$senderObject.IsChecked) }
        catch { $senderObject.IsChecked = -not $senderObject.IsChecked; Write-PillLog $_; [void][Windows.MessageBox]::Show("Le raccourci de démarrage n’a pas pu être modifié.", 'Codex Pill') }
    } -Checkable -Checked (Test-Path -LiteralPath $script:PillStartupLink))
    [void]$contextMenu.Items.Add([Windows.Controls.Separator]::new())
    # Trois tailles au choix (le modèle de menu n'affiche pas de sous-menus).
    $script:PillUi.Controls.SizeMenus = @()
    foreach ($sizeChoice in @(@('Taille normale', 1.0), @('Grande taille', 1.35), @('Très grande taille', 1.7))) {
        $sizeEntry = Add-PillMenuItem $contextMenu $sizeChoice[0] {
            param($senderObject, $clickEvent)
            Set-PillScale ([double]$senderObject.Tag)
            Save-PillSettings
        } -Checkable
        $sizeEntry.Tag = $sizeChoice[1]
        $script:PillUi.Controls.SizeMenus += $sizeEntry
    }
    [void]$contextMenu.Items.Add([Windows.Controls.Separator]::new())
    [void](Add-PillMenuItem $contextMenu 'Replacer en haut à droite' { Move-PillIntoView -Reset; Save-PillSettings })
    [void](Add-PillMenuItem $contextMenu 'Choisir le dossier des données…' { Select-PillSource })
    $script:PillUi.Controls.ClaudeEnableMenu = Add-PillMenuItem $contextMenu 'Activer la barre de statut Claude Code' { Enable-PillClaudeTracking }
    $script:PillUi.Controls.ClaudeDisableMenu = Add-PillMenuItem $contextMenu 'Désactiver la barre de statut Claude Code' { Disable-PillClaudeTracking }
    [void](Add-PillMenuItem $contextMenu 'Ouvrir le journal des erreurs' { Open-PillErrorLog })
    [void]$contextMenu.Items.Add([Windows.Controls.Separator]::new())
    [void](Add-PillMenuItem $contextMenu 'Quitter Codex Pill' { $script:PillUi.Main.Close() })
    $contextMenu.Add_Opened({ Update-PillProviderControls; Update-PillTray })
    $script:PillUi.Controls.PillSurface.ContextMenu = $contextMenu
    Set-PillScale (Get-PillScale)
    $script:PillPlaced = $false
    $script:PillUi.Main.Add_SizeChanged({
        param($senderObject, $sizeEvent)
        # Passage d'un rond à deux (ou l'inverse) : une pastille rangée dans la moitié
        # droite de l'écran garde son bord droit en place au lieu de déborder.
        if (-not $script:PillPlaced -or -not $sizeEvent.WidthChanged -or $sizeEvent.PreviousSize.Width -le 0) { return }
        try {
            $mainWindow = $script:PillUi.Main
            if (Test-PillOnRightHalf ($mainWindow.Left + $sizeEvent.PreviousSize.Width / 2)) {
                $mainWindow.Left -= $sizeEvent.NewSize.Width - $sizeEvent.PreviousSize.Width
                Save-PillSettings
            }
        } catch { Write-PillLog $_ }
    })
    $script:PillUi.Main.Add_Loaded({
        # Windows crée toute fenêtre avec une largeur minimale (environ 130 px) : plus
        # large qu'un rond seul. Recalculer l'ajustement au contenu rend sa vraie taille.
        $script:PillUi.Main.SizeToContent = 'Manual'
        $script:PillUi.Main.SizeToContent = 'WidthAndHeight'
        $script:PillUi.Main.UpdateLayout()
        try { New-PillTray } catch { Write-PillLog $_ }
        try {
            if ($null -ne $script:PillSettings.Left -and $null -ne $script:PillSettings.Top) {
                $script:PillUi.Main.Left = [double]$script:PillSettings.Left
                $script:PillUi.Main.Top = [double]$script:PillSettings.Top
                # À droite de l'écran, c'est le bord droit mémorisé qui fait foi.
                $savedRight = $script:PillSettings.Right
                $currentWidth = $script:PillUi.Main.ActualWidth
                if ($null -ne $savedRight -and $currentWidth -gt 0 -and (Test-PillOnRightHalf ([double]$savedRight - $currentWidth / 2))) {
                    $script:PillUi.Main.Left = [double]$savedRight - $currentWidth
                }
                Move-PillIntoView
            } else { Move-PillIntoView -Reset }
        } catch { Write-PillLog $_; Move-PillIntoView -Reset }
        $script:PillPlaced = $true
    })
    $script:PillUi.Main.Add_Closing({
        $script:PillExiting = $true
        Remove-PillTray
        Save-PillSettings
        if ($null -ne $script:PillUi.Detail) { $script:PillUi.Detail.Close() }
    })
}
