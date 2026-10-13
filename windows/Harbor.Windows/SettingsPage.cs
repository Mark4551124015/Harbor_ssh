using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Media.Animation;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private string settingsCategory = "All";
    private string settingsSearch = "";

    private void RenderSettings()
    {
        PageContent.Children.Clear();
        var layout = new Grid { RowSpacing = 16 };
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var searchBox = new AutoSuggestBox { Text = settingsSearch, PlaceholderText = "Search settings…", Width = 260, HorizontalAlignment = HorizontalAlignment.Right, QueryIcon = new SymbolIcon(Symbol.Find) };
        settingsSearchBox = searchBox;
        HeaderActions.Children.Clear(); HeaderActions.Children.Add(searchBox);
        var categories = new[] { "All", "Appearance", "Connections", "Proxy", "Data & privacy", "Keyboard shortcuts", "About" };
        var layers = new Grid(); Grid.SetRow(layers, 1); layout.Children.Add(layers);
        var contentTransition = new HarborPageTransition(layers);
        void Populate()
        {
            var sections = Stack(18);
            bool Include(string category, string keywords) => (settingsCategory == "All" || settingsCategory == category) &&
                $"{category} {keywords}".Contains(settingsSearch, StringComparison.OrdinalIgnoreCase);
            if (Include("Appearance", "theme accent color motion animation addresses")) sections.Children.Add(AppearanceSettings());
            if (Include("Connections", "start page terminal windows console timeout keep alive")) sections.Children.Add(ConnectionSettings());
            if (Include("Proxy", "network SOCKS5 HTTP system host port updates 代理")) sections.Children.Add(ProxySettings());
            if (Include("Data & privacy", "config preferences files folder backup local")) sections.Children.Add(StorageSettings());
            if (Include("Keyboard shortcuts", "keyboard tab escape enter"))
            {
                var shortcuts = Stack(16); shortcuts.Children.Add(Text("Keyboard shortcuts", 18));
                shortcuts.Children.Add(Text("Quick connect                              Ctrl+K\nSearch settings or connections    Ctrl+F\nNew connection                           Ctrl+N\nSave SSH configuration               Ctrl+S\nSettings                                       Ctrl+,\nBack / close dialog                      Esc\nRename selected connection        F2\nSelect connections                       Ctrl+click / Shift+click")); sections.Children.Add(Card(shortcuts));
            }
            if (Include("About", "harbor winui version license preview"))
            {
                var about = Stack(12); about.Children.Add(Text("Harbor", 23));
                about.Children.Add(Muted($"Version {System.Reflection.Assembly.GetExecutingAssembly().GetName().Version}\nWindows · WinUI 3 / C#\nApache License 2.0 · Copyright 2026 mark455"));
                var automatic = new HarborSwitch { IsOn = preferences.Value.AutoCheckUpdates, OnContent = "", OffContent = "" };
                ApplyAccentToggle(automatic);
                automatic.Toggled += async (_, _) => await RunAsync(async () => { preferences.Value.AutoCheckUpdates = automatic.IsOn; await SavePreferencesAsync(); });
                about.Children.Add(SettingRow("Automatically check for updates", "Check for compatible Windows updates at startup and notify when available.", automatic));
                AddUpdateControls(about);
                about.Children.Add(Muted("Activity monitors local OpenSSH client processes and Harbor-managed forwards.")); sections.Children.Add(Card(about));
            }
            if (sections.Children.Count == 0) sections.Children.Add(Muted("No matching settings."));
            var canvas = new Grid { Style = (Style)Application.Current.Resources["HarborCanvasStyle"] };
            canvas.Children.Add(Scroll(sections));
            contentTransition.Show(canvas, MotionEnabled);
        }
        var tabs = new HarborTabStrip(categories, settingsCategory, ThemeBrush("HarborTextBrush"), ThemeBrush("HarborMutedBrush"), ThemeBrush("HarborAccentBrush"), () => MotionEnabled,
            category => { settingsCategory = category; Populate(); }, selectedTint: ThemeBrush("HarborAccentBrush"));
        layout.Children.Add(tabs);
        searchBox.TextChanged += (_, _) => { settingsSearch = searchBox.Text; Populate(); };
        Populate(); PageContent.Children.Add(layout);
    }

    private Border AppearanceSettings()
    {
        var section = Stack(24); section.Children.Add(SettingsSectionHeading("Appearance", "\uE790"));
        var banner = Row(16);
        banner.Children.Add(new Border { Width = 44, Height = 44, CornerRadius = new CornerRadius(10), Background = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 23, 42, 66)), Child = new HarborMarkView { Width = 40, Height = 40 } });
        var welcome = Stack(4); welcome.Children.Add(Text("Make Harbor yours", 16)); welcome.Children.Add(Muted("Changes appear immediately.")); banner.Children.Add(welcome);
        var bannerLayout = new Grid { ColumnSpacing = 16 };
        bannerLayout.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        bannerLayout.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        bannerLayout.Children.Add(banner);
        var accentMark = new Border { Width = 8, Height = 32, CornerRadius = new CornerRadius(4), Background = ThemeBrush("HarborAccentBrush"), VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(accentMark, 1); bannerLayout.Children.Add(accentMark);
        section.Children.Add(new Border { Child = bannerLayout, Padding = new Thickness(14), CornerRadius = new CornerRadius(10), Background = ThemeBrush("HarborBackgroundBrush") });
        var theme = Segments(["System", "Light", "Dark"], preferences.Value.Theme, async value =>
        {
            preferences.Value.Theme = value; ApplyTheme(); await SavePreferencesAsync(); RenderSettings();
        });
        section.Children.Add(SettingRow("Theme", "Follow Windows or choose a fixed appearance.", theme));
        var accents = Row(8);
        foreach (var (name, light, dark) in new[] { ("Copper", 0x9A5427, 0xE5A16B), ("Teal", 0x28796D, 0x69BDB0), ("Blue", 0x386FA3, 0x7FAED5), ("Violet", 0x7354A6, 0xAA9BDC), ("Rose", 0xA34F70, 0xD68EAA) })
        {
            var hex = Root.ActualTheme == ElementTheme.Dark ? dark : light;
            var color = Windows.UI.Color.FromArgb(255, (byte)(hex >> 16), (byte)(hex >> 8), (byte)hex);
            var button = ActionButton("", async () =>
            {
                preferences.Value.Accent = name; UpdateAccent(); await SavePreferencesAsync(); RenderSettings();
            }, hover: false);
            button.Style = (Style)Application.Current.Resources["HarborQuietButtonStyle"];
            button.Background = new SolidColorBrush(color); button.Foreground = new SolidColorBrush(Microsoft.UI.Colors.White);
            button.Width = 32; button.Height = 32; button.Padding = new Thickness(0); button.CornerRadius = new CornerRadius(16);
            SetColorSwatchContent(button, preferences.Value.Accent == name);
            ToolTipService.SetToolTip(button, name); Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(button, name); accents.Children.Add(button);
        }
        section.Children.Add(SettingRow("Accent color", preferences.Value.Accent, accents));
        var reduce = new HarborSwitch { IsOn = preferences.Value.ReduceMotion, OnContent = "", OffContent = "" };
        ApplyAccentToggle(reduce);
        reduce.Toggled += async (_, _) => await RunAsync(async () => { preferences.Value.ReduceMotion = reduce.IsOn; if (reduce.IsOn) transition?.Finish(); await SavePreferencesAsync(); });
        section.Children.Add(SettingRow("Reduce motion", "Keep transitions still. Windows accessibility settings also apply.", reduce));
        var addresses = new HarborSwitch { IsOn = preferences.Value.ShowServerAddresses, OnContent = "", OffContent = "" };
        ApplyAccentToggle(addresses);
        addresses.Toggled += async (_, _) => await RunAsync(async () => { preferences.Value.ShowServerAddresses = addresses.IsOn; RenderSidebarHosts(); await SavePreferencesAsync(); });
        section.Children.Add(SettingRow("Show server addresses", "Display hostnames below connections in the sidebar.", addresses));
        return Card(section);
    }

    private Border ConnectionSettings()
    {
        var section = Stack(24); section.Children.Add(SettingsSectionHeading("Connections", "\uE8AB"));
        var start = Segments(["Workbench", "Mappings", "Keys"], preferences.Value.StartPage switch { "forwards" => "Mappings", "keys" => "Keys", _ => "Workbench" }, async value =>
        {
            preferences.Value.StartPage = value switch { "Mappings" => "forwards", "Keys" => "keys", _ => "workbench" }; await SavePreferencesAsync();
        });
        section.Children.Add(SettingRow("Start page", "Where Harbor opens next time.", start));
        var terminal = Segments(["Windows Terminal", "Console"], preferences.Value.PreferWindowsTerminal ? "Windows Terminal" : "Console", async value =>
        {
            preferences.Value.PreferWindowsTerminal = value == "Windows Terminal"; await SavePreferencesAsync();
        });
        section.Children.Add(SettingRow("Open connections in", "Windows Terminal falls back to a console when unavailable.", terminal));
        section.Children.Add(SettingRow("Connection timeout", "For new tunnels; server-specific options take priority.", Segments(["10s", "15s", "30s", "60s"], $"{preferences.Value.ConnectTimeout}s", async value =>
        {
            preferences.Value.ConnectTimeout = int.Parse(value.TrimEnd('s')); await SavePreferencesAsync();
        })));
        section.Children.Add(SettingRow("Keep-alive interval", "For new tunnels. Detects a lost connection after three missed replies.", Segments(["Off", "30s", "60s"], preferences.Value.KeepAlive == 0 ? "Off" : $"{preferences.Value.KeepAlive}s", async value =>
        {
            preferences.Value.KeepAlive = value == "Off" ? 0 : int.Parse(value.TrimEnd('s')); await SavePreferencesAsync();
        })));
        return Card(section);
    }

    private Border StorageSettings()
    {
        var section = Stack(18); section.Children.Add(SettingsSectionHeading("Data & privacy", "\uE72E"));
        var recent = new HarborSwitch { IsOn = preferences.Value.RecordRecent, OnContent = "", OffContent = "" };
        ApplyAccentToggle(recent);
        recent.Toggled += async (_, _) => await RunAsync(async () => { preferences.Value.RecordRecent = recent.IsOn; await SavePreferencesAsync(); });
        section.Children.Add(SettingRow("Remember recent connections", "Record successfully opened terminal sessions on this PC.", recent));
        var clear = ActionButton("Clear history", async () => { preferences.Value.RecentHosts.Clear(); await SavePreferencesAsync(); RenderSettings(); });
        clear.IsEnabled = preferences.Value.RecentHosts.Count > 0;
        section.Children.Add(SettingRow("Recent history", $"{preferences.Value.RecentHosts.Count} recent connections.", clear));
        section.Children.Add(SettingRow("Harbor data", "Groups, preferences and independent mappings.", ActionButton("Show in Explorer", () => { WindowsIntegration.RevealFile(preferences.Path); return Task.CompletedTask; })));
        section.Children.Add(SettingRow("SSH configuration", "Host settings in ~/.ssh/config.", ActionButton("Show config", () => { WindowsIntegration.RevealFile(config.Path); return Task.CompletedTask; })));
        return Card(section);
    }

    private Grid SettingRow(string title, string description, FrameworkElement control)
    {
        var row = new Grid { ColumnSpacing = 20, RowSpacing = 10 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); row.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var text = Stack(5); text.Children.Add(Text(title)); text.Children.Add(Muted(description, 12)); row.Children.Add(text);
        control.VerticalAlignment = VerticalAlignment.Center; Grid.SetColumn(control, 1); row.Children.Add(control);
        text.VerticalAlignment = VerticalAlignment.Center;
        row.SizeChanged += (_, args) =>
        {
            var compact = args.NewSize.Width < 620;
            control.HorizontalAlignment = compact ? HorizontalAlignment.Left : HorizontalAlignment.Right;
            Grid.SetColumn(control, compact ? 0 : 1); Grid.SetRow(control, compact ? 1 : 0); Grid.SetColumnSpan(control, compact ? 2 : 1); Grid.SetColumnSpan(text, compact ? 2 : 1);
        };
        return row;
    }

    private StackPanel SettingsSectionHeading(string title, string glyph)
    {
        var heading = Row(10);
        heading.Children.Add(new FontIcon { Glyph = glyph, FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"), FontSize = 16, Foreground = ThemeBrush("HarborAccentBrush"), Width = 20, Height = 20 });
        var label = Text(title, 14); label.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold; label.VerticalAlignment = VerticalAlignment.Center;
        heading.Children.Add(label); return heading;
    }

    private FrameworkElement Segments(string[] values, string selected, Func<string, Task> changed)
    {
        var selector = new Grid { Padding = new Thickness(3), CornerRadius = new CornerRadius(9), Background = ThemeBrush("HarborBackgroundBrush"),
            Width = values.Length * (values.Max(value => value.Length) * 7 + 24), Height = 34, HorizontalAlignment = HorizontalAlignment.Right };
        var index = Math.Max(0, Array.IndexOf(values, selected));
        for (var i = 0; i < values.Length; i++) selector.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var offset = new TranslateTransform();
        var indicator = new Border { CornerRadius = new CornerRadius(7), Background = ThemeBrush("HarborSurfaceBrush"),
            BorderThickness = new Thickness(0), HorizontalAlignment = HorizontalAlignment.Left, IsHitTestVisible = false, RenderTransform = offset };
        Grid.SetColumnSpan(indicator, values.Length); selector.Children.Add(indicator);
        Storyboard? motion = null;
        var revision = 0;
        selector.SizeChanged += (_, args) => { var cell = Math.Max(0, (args.NewSize.Width - 6) / values.Length); indicator.Width = cell; offset.X = index * cell; };
        for (var i = 0; i < values.Length; i++)
        {
            var item = i;
            var button = new Button { Content = values[i], Style = (Style)Application.Current.Resources["HarborNavigationButtonStyle"],
                HorizontalContentAlignment = HorizontalAlignment.Center, Padding = new Thickness(8, 4, 8, 4), Foreground = ThemeBrush("HarborTextBrush") };
            button.Style = (Style)Application.Current.Resources["HarborTabButtonStyle"];
            button.HorizontalAlignment = HorizontalAlignment.Stretch;
            button.VerticalAlignment = VerticalAlignment.Stretch;
            button.VerticalContentAlignment = VerticalAlignment.Center;
            button.MinHeight = 0;
            button.MinWidth = 0;
            Grid.SetColumn(button, i); selector.Children.Add(button);
            button.Click += async (_, _) =>
            {
                var request = ++revision;
                var start = offset.X; motion?.Stop(); offset.X = start; index = item;
                var target = item * Math.Max(0, (selector.ActualWidth - 6) / values.Length);
                if (!MotionEnabled) offset.X = target;
                else
                {
                    motion = new Storyboard();
                    var slide = new DoubleAnimation { From = start, To = target, Duration = TimeSpan.FromMilliseconds(280), EnableDependentAnimation = true,
                        EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } };
                    Storyboard.SetTarget(slide, offset); Storyboard.SetTargetProperty(slide, "X"); motion.Children.Add(slide); motion.Begin();
                    await Task.Delay(280);
                }
                if (request != revision) return;
                await RunAsync(() => changed(values[item]));
            };
        }
        return selector;
    }

    private void SetColorSwatchContent(Button button, bool selected)
    {
        button.HorizontalContentAlignment = HorizontalAlignment.Center;
        button.VerticalContentAlignment = VerticalAlignment.Center;
        button.Content = new FontIcon
        {
            Glyph = "\uE73E", FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"),
            FontSize = 14, Width = 16, Height = 16,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            Foreground = new SolidColorBrush(Microsoft.UI.Colors.White), Opacity = selected ? 1 : 0
        };
        AddButtonHover(button);
    }
}
