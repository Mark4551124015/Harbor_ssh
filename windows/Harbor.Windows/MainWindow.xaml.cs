using Harbor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.ApplicationModel.DataTransfer;

namespace Harbor.Desktop;

public sealed partial class MainWindow : Window
{
    private readonly SshConfigStore config;
    private readonly PreferencesStore preferences;
    private readonly string sshDirectory;
    private readonly string? smokeReport;
    private readonly string? smokeDirectory;
    private SshProcessManager? processes;
    private LocalSshProcessMonitor? localSshMonitor;
    private string page = "workbench";
    private string search = "";
    private string? selectedAlias;
    private bool initialized;
    private bool settingsLoaded;
    private Grid PageContent = new();
    private TextBlock PageTitle = new();
    private TextBlock PageDescription = new();
    private Border PageMark = new();
    private WrapPanel HeaderActions = new();
    private HarborPageTransition? transition;
    private Task? dialogFocusReveal;
    private StackPanel? hostDetails;

    public MainWindow(string? smokeReport = null)
    {
        this.smokeReport = smokeReport;
        if (smokeReport is not null)
        {
            smokeDirectory = Path.Combine(Path.GetTempPath(), "Harbor.UISmoke", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(smokeDirectory);
            File.WriteAllText(Path.Combine(smokeDirectory, "config"), "# Fictional UI smoke-test hosts\nHost edge-gateway\n HostName edge.example.invalid\n User deploy\n Port 22\nHost design-lab\n HostName lab.example.invalid\n User developer\n Port 22\nHost production-api\n HostName api.example.invalid\n User deploy\n Port 2222\nHost build-runner\n HostName build.example.invalid\n User ci\n Port 22\n");
        }
        sshDirectory = smokeDirectory ?? WindowsIntegration.SshDirectory;
        config = new SshConfigStore(Path.Combine(sshDirectory, "config"));
        preferences = new PreferencesStore(smokeDirectory is not null ? Path.Combine(smokeDirectory, "settings.json") :
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Harbor.Windows", "settings.json"));
        InitializeComponent();
        AddButtonHover(SettingsButton);
        Root.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler(SidebarRoot_PointerPressed), true);
        var version = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version;
        SidebarVersion.Text = $"v{version?.Major}.{version?.Minor}.{version?.Build}";
        transition = new HarborPageTransition(PageLayers);
        BuildNavigation();
        ConfigureKeyboard();
        ConfigureSidebarSelection();
        ConfigureManualSidebarDragSurface();
        ConfigureStickyHeaders();
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "harbor.ico"));
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(TitleBar);
        AppWindow.TitleBar.ButtonBackgroundColor = Microsoft.UI.Colors.Transparent;
        AppWindow.TitleBar.ButtonInactiveBackgroundColor = Microsoft.UI.Colors.Transparent;
        Root.ActualThemeChanged += (_, _) =>
        {
            UpdateAccent();
            if (initialized) DispatcherQueue.TryEnqueue(() =>
            {
                if (page == "settings") RenderSettings();
                else if (page == "workbench") RenderWorkbench();
                else if (page == "servers") RenderServers();
                else if (page == "forwards") RenderForwards();
                else if (page == "activity") RenderActivity();
                else if (page == "keys") _ = RunAsync(RenderKeysAsync);
            });
        };
        Root.SizeChanged += (_, args) => SidebarColumn.Width = new GridLength(args.NewSize.Width < 1000 ? 220 : 240);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1240, 820));
        if (Microsoft.UI.Composition.SystemBackdrops.MicaController.IsSupported())
            SystemBackdrop = new MicaBackdrop();
        Root.Loaded += Initialize;
        Closed += (_, _) => { localSshMonitor?.Dispose(); processes?.Dispose(); };
    }

    private async void Initialize(object sender, RoutedEventArgs args)
    {
        if (initialized) return;
        initialized = true;
        var errors = new List<string>();
        try { await preferences.LoadAsync(); settingsLoaded = true; }
        catch (Exception exception) { errors.Add($"Could not read Windows settings: {exception.Message}"); }
        ApplyTheme();
        try { await config.LoadAsync(); }
        catch (Exception exception) { errors.Add($"Could not read SSH config: {exception.Message}"); }
        try
        {
            processes = new SshProcessManager(WindowsIntegration.FindOpenSsh("ssh.exe"), config.Path, () => (preferences.Value.ConnectTimeout, preferences.Value.KeepAlive), BuildProxyCommandAsync);
            processes.Changed += () => DispatcherQueue.TryEnqueue(() =>
            {
                if (page == "forwards") RenderForwards();
                if (page == "activity") RenderActivity();
                if (page == "workbench") RenderWorkbench();
            });
        }
        catch (Exception exception) { errors.Add(exception.Message); }
        localSshMonitor = new LocalSshProcessMonitor();
        localSshMonitor.Changed += () => DispatcherQueue.TryEnqueue(() =>
        {
            if (page == "activity") RenderActivity();
            if (page == "workbench") RenderWorkbench();
        });
        PopulateHosts();
        ShowPage(preferences.Value.StartPage is "forwards" or "keys" or "activity" ? preferences.Value.StartPage : "workbench");
        if (errors.Count > 0) ShowNotice(string.Join("\n", errors), InfoBarSeverity.Warning);
        if (MotionEnabled)
        {
            try { await PlayLaunchAsync(); }
            catch (Exception exception) { errors.Add($"Native focus animation: {exception.Message}"); ShowNotice(errors[^1], InfoBarSeverity.Warning); }
        }
        if (smokeReport is not null) await SmokeTestAsync(errors);
        else if (preferences.Value.AutoCheckUpdates) _ = CheckStartupVersionAsync();
    }

    private async Task SmokeTestAsync(List<string> errors)
    {
        var checks = new List<string>();
        try
        {
            if (errors.Count > 0) throw new InvalidOperationException(string.Join("\n", errors));
            checks.Add("PASS native compositor launch focus reveal");
            preferences.Value.Forwards.Add(new ForwardRule(Guid.NewGuid(), "edge-gateway", ForwardKind.Socks, 1080));
            preferences.Value.Favorites.UnionWith(["edge-gateway", "design-lab"]);
            preferences.Value.HostGroups["design-lab"] = "Development";
            foreach (var alias in new[] { "edge-gateway", "production-api", "build-runner" }) preferences.Value.HostGroups[alias] = "Production";
            PopulateHosts();
            foreach (var theme in new[] { "Light", "Dark" })
            {
                preferences.Value.Theme = theme;
                ApplyTheme();
                foreach (var target in new[] { "workbench", "servers", "forwards", "keys", "activity", "settings" })
                {
                    ShowPage(target);
                    if (target == "keys") await RenderKeysAsync();
                    await Task.Delay(240);
                    Root.UpdateLayout();
                    if (PageContent.Children.Count == 0 || PageContent.ActualWidth <= 0 || PageContent.ActualHeight <= 0)
                        throw new InvalidOperationException($"{target}: content did not lay out.");
                    if (Root.ActualTheme.ToString() != theme)
                        throw new InvalidOperationException($"{target}: theme did not apply.");
                    if (target is "workbench" or "settings" or "servers" or "forwards") await CapturePreviewAsync($"{smokeReport}-{theme}-{target}.png");
                    if (target == "servers")
                    {
                        var anchor = SidebarHosts.Children.OfType<HarborHostSection>().SelectMany(section => section.HostButtons).First();
                        var menu = ConnectionMenu(config.Document.Hosts.First());
                        menu.ShowAt(anchor); await Task.Delay(200);
                        try
                        {
                            var popup = VisualTreeHelper.GetOpenPopupsForXamlRoot(Root.XamlRoot).FirstOrDefault(value => value.Child is MenuFlyoutPresenter);
                            if (popup?.Child is UIElement presenter) await CapturePreviewAsync($"{smokeReport}-{theme}-context-menu.png", presenter);
                        }
                        finally { menu.Hide(); }
                        foreach (var tab in new[] { "General", "Connection", "Advanced" })
                        {
                            detailTab = tab; RenderServers(); await Task.Delay(260);
                            await CapturePreviewAsync($"{smokeReport}-{theme}-host-{tab}.png");
                        }
                        var options = PickAdvancedOptionAsync([]); await Task.Delay(360);
                        await CapturePreviewAsync($"{smokeReport}-{theme}-option-picker.png"); dismissSheet?.Invoke(); await options;
                        var organize = ChangeHostGroupAsync(config.Document.Hosts.First()); await Task.Delay(360);
                        await CapturePreviewAsync($"{smokeReport}-{theme}-organize-host.png"); dismissSheet?.Invoke(); await organize;
                        detailTab = "Overview"; RenderServers();
                    }
                    checks.Add($"PASS {theme}: {target}");
                }
                var quick = QuickConnectAsync();
                await Task.Delay(400);
                await CapturePreviewAsync($"{smokeReport}-{theme}-quick-connect.png");
                quickConnectCompletion?.TrySetResult(null);
                await quick;
                checks.Add($"PASS {theme}: searchable quick connect overlay");
            }
            if (MotionEnabled)
            {
                ShowPage("workbench"); await Task.Delay(60);
                var outgoing = PageLayers.Children.OfType<Grid>().Last();
                var opacity = outgoing.Opacity;
                ShowPage("keys");
                if (Math.Abs(outgoing.Opacity - opacity) > 0.02 || outgoing.IsHitTestVisible)
                    throw new InvalidOperationException("Interrupted page transition did not freeze the outgoing page.");
                await Task.Delay(40); ShowPage("settings"); await Task.Delay(240);
                var settleDeadline = DateTime.UtcNow.AddSeconds(2);
                while (PageLayers.Children.Count > 1 && DateTime.UtcNow < settleDeadline) await Task.Delay(30);
                if (PageLayers.Children.Count != 1 || !PageLayers.Children[0].IsHitTestVisible)
                    throw new InvalidOperationException($"Rapid navigation did not settle: {PageLayers.Children.Count} layers, opacity {PageLayers.Children.OfType<Grid>().Last().Opacity}.");
                checks.Add("PASS interrupted navigation retains its canvas and disables outgoing input");
                Root.UpdateLayout();
                var libraryY = LibraryScrollViewer.TransformToVisual(Root).TransformPoint(new Windows.Foundation.Point()).Y;
                OpenSidebarSearch(); await Task.Delay(90); Root.UpdateLayout();
                var searchHeight = SidebarSearchPanel.ActualHeight;
                var shiftedY = LibraryScrollViewer.TransformToVisual(Root).TransformPoint(new Windows.Foundation.Point()).Y;
                if (searchHeight <= 0 || searchHeight >= 36 || Math.Abs(shiftedY - libraryY - searchHeight) > 1)
                    throw new InvalidOperationException($"Search expansion jumped: height {searchHeight}, library shift {shiftedY - libraryY}.");
                CloseSidebarSearch(); Root.UpdateLayout();
                if (Math.Abs(SidebarSearchPanel.ActualHeight - searchHeight) > 1)
                    throw new InvalidOperationException("Reversing search expansion jumped to an endpoint.");
                await Task.Delay(280); Root.UpdateLayout();
                if (SidebarSearchPanel.Visibility != Visibility.Collapsed || Math.Abs(LibraryScrollViewer.TransformToVisual(Root).TransformPoint(new Windows.Foundation.Point()).Y - libraryY) > 1)
                    throw new InvalidOperationException("Search collapse did not restore the sidebar layout.");
                checks.Add("PASS sidebar search height and library slide together, including reversal");
                foreach (var hostRow in SidebarHosts.Children.OfType<HarborHostSection>().SelectMany(section => section.HostButtons))
                {
                    var hoverLayer = (Grid)hostRow.Content;
                    var rowContent = hoverLayer.Children.OfType<Grid>().Single();
                    if (hostRow.ActualHeight < 44 || rowContent.ActualHeight < 28 || rowContent.ActualWidth <= 0)
                        throw new InvalidOperationException($"Server row {hostRow.Tag} collapsed: button {hostRow.ActualHeight}, content {rowContent.ActualWidth}x{rowContent.ActualHeight}.");
                }
                checks.Add("PASS server rows retain their content height after search layout changes");
                ShowPage("workbench"); ShowPage("keys"); ShowPage("settings");
                await Task.Delay(300);
                Root.UpdateLayout(); settingsSearchBox!.Focus(FocusState.Programmatic);
                if (FocusedSearch() is null) throw new InvalidOperationException("Settings search did not receive focus for Escape check.");
                HandleEscape();
                if (page != "settings" || FocusedSearch() is not null)
                    throw new InvalidOperationException("Escape did not leave search focus before navigating.");
                HandleEscape();
                if (page != "keys") throw new InvalidOperationException("Escape did not return to the previous page.");
                HandleEscape();
                if (page != "workbench") throw new InvalidOperationException("Escape did not return home.");
                checks.Add("PASS Escape leaves search focus, then returns to the previous page and home");
                SidebarLibraryViewport.Height = 120;
                SidebarLibraryViewport.VerticalAlignment = VerticalAlignment.Top;
                Root.UpdateLayout();
                LibraryScrollViewer.ChangeView(null, 0, null, true); await Task.Delay(80);
                UpdateStickyHeader();
                var stickyGroups = SidebarHosts.Children.OfType<HarborHostSection>().ToArray();
                var originalHeader = stickyGroups[0].HeaderButton;
                if (stickySection != stickyGroups[0] || StickyGroupHeader.Child != originalHeader || stickyGroups[0].HeaderSlot.Children.Count != 0)
                    throw new InvalidOperationException("Top header was not prepared as a single fixed button before scrolling.");
                var originalHeaderHeight = originalHeader.ActualHeight;
                foreach (var offset in new double[] { 1, 2, 4, 8, 12 })
                {
                    LibraryScrollViewer.ChangeView(null, offset, null, true); await Task.Delay(40); Root.UpdateLayout(); UpdateStickyHeader();
                    if (stickySection != stickyGroups[0] || StickyGroupHeader.Child != originalHeader || Math.Abs(LibraryScrollViewer.VerticalOffset - offset) > 0.5 || Math.Abs(StickyGroupHeaderOffset.Y) > 0.5)
                        throw new InvalidOperationException($"First scroll changed the sticky header or scroll offset at {offset}.");
                    if (Math.Abs(originalHeader.ActualHeight - originalHeaderHeight) > 0.5 || StickyGroupHeader.ActualHeight - originalHeader.ActualHeight < 5.5)
                        throw new InvalidOperationException("Sticky header changed button height or lost its bottom gap.");
                }
                LibraryScrollViewer.ChangeView(null, 12, null, true); await Task.Delay(100); UpdateStickyHeader();
                if (StickyGroupHeader.Child != originalHeader || stickySection != stickyGroups[0] || !originalHeader.AllowDrop || originalHeader.ContextFlyout is null)
                    throw new InvalidOperationException("Sticky header did not preserve the original interactive button.");
                var nextTop = stickyGroups[1].HeaderSlot.TransformToVisual(SidebarHosts).TransformPoint(new Windows.Foundation.Point()).Y;
                LibraryScrollViewer.ChangeView(null, nextTop - StickyGroupHeader.Height / 2, null, true); await Task.Delay(100); UpdateStickyHeader();
                if (stickySection != stickyGroups[0] || StickyGroupHeaderOffset.Y >= -1)
                    throw new InvalidOperationException("The next group did not push the sticky header upward.");
                LibraryScrollViewer.ChangeView(null, nextTop + 2, null, true); await Task.Delay(100); UpdateStickyHeader();
                if (stickySection != stickyGroups[1]) throw new InvalidOperationException("Sticky header did not switch to the next group.");
                stickySection.Toggle(); await Task.Delay(340); UpdateStickyHeader();
                if (StickyGroupHeader.Child is Button pinned && !SidebarHosts.Children.OfType<HarborHostSection>().Any(section => section.HeaderButton == pinned))
                    throw new InvalidOperationException("Collapsed group left a stale sticky header.");
                stickyGroups[1].Toggle(); await Task.Delay(340);
                LibraryScrollViewer.ChangeView(null, LibraryScrollViewer.ScrollableHeight, null, true); await Task.Delay(100); UpdateStickyHeader();
                if (stickySection != stickyGroups.Last()) throw new InvalidOperationException("Incorrect sticky header at the list bottom.");
                OpenSidebarSearch(); await Task.Delay(280);
                SidebarSearch.Text = "no-matching-sticky-host";
                SidebarSearch_TextChanged(SidebarSearch, null!); await Task.Delay(100); UpdateStickyHeader();
                if (stickySection is not null || StickyGroupHeader.Child is not null) throw new InvalidOperationException($"Filtering left a stale sticky header: query '{search}', sections {SidebarHosts.Children.Count}.");
                SidebarSearch.Text = ""; SidebarSearch_TextChanged(SidebarSearch, null!); await Task.Delay(100);
                CloseSidebarSearch(); await Task.Delay(280);
                preferences.Value.SectionOrder = stickyGroups.Select(section => (string)section.HeaderButton.Tag).Reverse().ToList();
                RenderSidebarHosts(); Root.UpdateLayout(); UpdateStickyHeader();
                if (stickySection is not null && !SidebarHosts.Children.Contains(stickySection)) throw new InvalidOperationException("Reordering left an old sticky section.");
                await Task.Delay(340); // Let the existing group reorder animation settle.
                LibraryScrollViewer.ChangeView(null, 0, null, true); await Task.Delay(100); UpdateStickyHeader();
                var topGroup = SidebarHosts.Children.OfType<HarborHostSection>().First();
                if (stickySection != topGroup || StickyGroupHeader.Child != topGroup.HeaderButton || SidebarHosts.Children.OfType<HarborHostSection>().Any(section => section.HeaderSlot.Children.Count != (section == stickySection ? 0 : 1)))
                    throw new InvalidOperationException("Returning to the top left a duplicate or empty header slot.");
                SidebarLibraryViewport.Height = double.NaN; SidebarLibraryViewport.VerticalAlignment = VerticalAlignment.Stretch;
                Root.UpdateLayout();
                checks.Add("PASS sticky headers: top, push-off, replacement, collapse, bottom, filtering, reorder, resize and retained menu/drop button");
                var activityPreview = ShowActivityDetailAsync(new ObservedSshProcess(-1, DateTimeOffset.Now.AddMinutes(-2), "ssh.exe", "ssh", "127.0.0.1:22", "127.0.0.1:1080"));
                await Task.Delay(350);
                if (dismissSheet is null) throw new InvalidOperationException("SSH activity detail did not open.");
                await CapturePreviewAsync($"{smokeReport}-activity-detail.png");
                dismissSheet(); await activityPreview;
                if (dismissSheet is not null) throw new InvalidOperationException("SSH activity detail did not close.");
                checks.Add("PASS SSH activity opens details with diagnostics and closes cleanly");
                var group = SidebarHosts.Children.OfType<HarborHostSection>().First();
                var firstRow = group.FirstRow;
                group.Toggle(); await Task.Delay(140); group.Toggle(); await Task.Delay(340);
                if (!ReferenceEquals(firstRow, group.FirstRow) || group.ContentHeight <= 0)
                    throw new InvalidOperationException("Interrupted group expansion did not preserve its rows.");
                checks.Add("PASS group collapse and expansion preserve row instances");
            }
            else checks.Add("PASS Windows system reduced-motion preference respected");
            var previewDialog = Dialog("Quick connect", new ComboBox { Header = "Connection", ItemsSource = new[] { "edge-gateway", "design-lab" }, SelectedIndex = 0, Width = 360 }, "Connect ↗");
            var dialogLoaded = new TaskCompletionSource();
            ((Grid)previewDialog.Content).Loaded += (_, _) => dialogLoaded.TrySetResult();
            var dialogShowing = previewDialog.ShowAsync();
            try
            {
                await dialogLoaded.Task.WaitAsync(TimeSpan.FromSeconds(3));
                await Task.Delay(400);
                if (dialogFocusReveal is not null) await dialogFocusReveal;
                checks.Add("PASS native dialog focus reveal");
            }
            finally { previewDialog.Hide(); await dialogShowing; }
            preferences.Value.ReduceMotion = true;
            ShowPage("workbench");
            if (PageLayers.Children.Count != 1 || PageLayers.Children.OfType<Grid>().Single().Opacity != 1)
                throw new InvalidOperationException("Reduced motion did not bypass transitions.");
            checks.Add("PASS reduced motion");
            await preferences.SaveAsync();
            var restoredPreferences = new PreferencesStore(preferences.Path);
            await restoredPreferences.LoadAsync();
            if (restoredPreferences.Value.Accent != preferences.Value.Accent || restoredPreferences.Value.Forwards.Count != preferences.Value.Forwards.Count ||
                !restoredPreferences.Value.Favorites.SetEquals(preferences.Value.Favorites) || restoredPreferences.Value.HostGroups.Count != preferences.Value.HostGroups.Count)
                throw new InvalidOperationException("Published settings serialization roundtrip failed.");
            checks.Add("PASS published settings serialization roundtrip");
            File.WriteAllLines(smokeReport!, checks.Append("PASS Windows UI smoke test"));
        }
        catch (Exception exception) { File.WriteAllText(smokeReport!, exception.ToString()); }
        finally
        {
            processes?.Dispose();
            Close();
            // The directory was created exclusively for this run, under the fixed test root.
            if (smokeDirectory is not null && Path.GetFullPath(smokeDirectory).StartsWith(
                Path.GetFullPath(Path.Combine(Path.GetTempPath(), "Harbor.UISmoke")) + Path.DirectorySeparatorChar,
                StringComparison.OrdinalIgnoreCase)) Directory.Delete(smokeDirectory, recursive: true);
        }
    }

    private async Task CapturePreviewAsync(string path, UIElement? element = null)
    {
        var bitmap = new RenderTargetBitmap();
        await bitmap.RenderAsync(element ?? Root);
        var pixels = await bitmap.GetPixelsAsync();
        var bytes = new byte[pixels.Length];
        using (var reader = Windows.Storage.Streams.DataReader.FromBuffer(pixels)) reader.ReadBytes(bytes);
        using var stream = File.Create(path);
        var encoder = await Windows.Graphics.Imaging.BitmapEncoder.CreateAsync(Windows.Graphics.Imaging.BitmapEncoder.PngEncoderId, stream.AsRandomAccessStream());
        encoder.SetPixelData(Windows.Graphics.Imaging.BitmapPixelFormat.Bgra8, Windows.Graphics.Imaging.BitmapAlphaMode.Premultiplied,
            (uint)bitmap.PixelWidth, (uint)bitmap.PixelHeight, 96, 96, bytes);
        await encoder.FlushAsync();
    }

    private void ShowPage(string next)
    {
        if (next != page && !navigatingBack)
        {
            if (next == "workbench") pageHistory.Clear();
            else pageHistory.Push(page);
        }
        if (next != "servers") { selectedHosts.Clear(); sidebarFocusKey = null; UpdateHostSelection(); }
        else if (selectedAlias is not null && (sidebarFocusKey is null || !sidebarFocusKey.EndsWith("\0" + selectedAlias, StringComparison.Ordinal)))
        {
            selectedHosts.Clear(); selectedHosts.Add(selectedAlias);
            sidebarFocusKey = $"{preferences.Value.HostGroups.GetValueOrDefault(selectedAlias, "Ungrouped")}\0{selectedAlias}";
        }
        page = next;
        Notice.IsOpen = false;
        PageContent = new Grid();
        PageTitle = Text("", 28);
        PageTitle.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        PageDescription = Muted("", 13);
        (PageTitle.Text, PageDescription.Text) = next switch
        {
            "workbench" => ("Connection desk", "Pick a host. Get to work."),
            "forwards" => ("Port mappings", "Secure routes for your local and remote services."),
            "keys" => ("SSH keys", "Public keys and fingerprints from your Windows SSH folder."),
            "activity" => ("SSH activity", "Local OpenSSH connections, including ssh.exe launched by terminals and other applications."),
            "settings" => ("Settings", "A workspace that feels like yours."),
            _ => ("Connection", "Manage this host and open it in your terminal.")
        };
        var frame = new Grid { RowSpacing = 20, Style = (Style)Application.Current.Resources["HarborCanvasStyle"] };
        frame.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        frame.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var heading = Stack(6);
        heading.VerticalAlignment = VerticalAlignment.Center;
        heading.Children.Add(PageTitle);
        heading.Children.Add(PageDescription);
        PageMark = new Border { Width = 42, Height = 42, CornerRadius = new CornerRadius(10), VerticalAlignment = VerticalAlignment.Center, Visibility = Visibility.Collapsed };
        var identity = new Grid { ColumnSpacing = 12 };
        identity.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        identity.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        identity.Children.Add(PageMark); Grid.SetColumn(heading, 1); identity.Children.Add(heading);
        HeaderActions = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
        var headingRow = new Grid { ColumnSpacing = 16 };
        headingRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        headingRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        headingRow.Children.Add(identity); Grid.SetColumn(HeaderActions, 1); headingRow.Children.Add(HeaderActions);
        var header = Stack(24);
        if (next == "workbench")
        {
            var eyebrow = new Grid(); eyebrow.Children.Add(Muted("WORKBENCH", 10));
            var local = Muted("ON YOUR WINDOWS PC  ·  LOCAL", 9); local.HorizontalAlignment = HorizontalAlignment.Right; eyebrow.Children.Add(local);
            header.Children.Add(eyebrow);
        }
        header.Children.Add(headingRow); frame.Children.Add(header);
        Grid.SetRow(PageContent, 1);
        frame.Children.Add(PageContent);
        transition!.Show(frame, MotionEnabled);
        SelectNavigation(next);
        switch (next)
        {
            case "workbench": RenderWorkbench(); break;
            case "forwards": RenderForwards(); break;
            case "keys": _ = RunAsync(RenderKeysAsync); break;
            case "activity": RenderActivity(); break;
            case "settings": RenderSettings(); break;
            default: RenderServers(); break;
        }
        UpdateHostSelection();
    }

    private async Task RunAsync(Func<Task> action)
    {
        try { await action(); }
        catch (Exception exception) { ShowNotice(exception.Message, InfoBarSeverity.Error); }
    }

    private void ShowNotice(string text, InfoBarSeverity severity = InfoBarSeverity.Informational)
    {
        Notice.Message = text;
        Notice.Severity = severity;
        Notice.IsOpen = true;
    }

    private Task SavePreferencesAsync()
    {
        if (!settingsLoaded)
            throw new IOException("Windows settings could not be read. Fix or move the settings file, then restart Harbor before saving preferences.");
        return preferences.SaveAsync();
    }

    private void ApplyTheme()
    {
        Root.RequestedTheme = preferences.Value.Theme switch
        {
            "Light" => ElementTheme.Light, "Dark" => ElementTheme.Dark, _ => ElementTheme.Default
        };
        UpdateAccent();
    }

    private bool MotionEnabled => !preferences.Value.ReduceMotion && new Windows.UI.ViewManagement.UISettings().AnimationsEnabled;

    private static StackPanel Stack(double spacing = 12) => new() { Spacing = spacing };
    private static StackPanel Row(double spacing = 8) => new() { Orientation = Orientation.Horizontal, Spacing = spacing };
    private static TextBlock Text(string text, double size = 14) => new()
    {
        Text = text, FontSize = size, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = false,
        Style = (Style)Application.Current.Resources["HarborTextStyle"]
    };
    private static TextBlock Muted(string text, double size = 12)
    {
        var label = Text(text, size);
        label.Style = (Style)Application.Current.Resources["HarborMutedTextStyle"];
        return label;
    }

    private Button ActionButton(string label, Func<Task> action, Symbol? icon = null, bool accent = false, bool hover = true)
    {
        var button = new Button { Style = (Style)Application.Current.Resources["HarborActionButtonStyle"], Padding = new Thickness(12, 8, 12, 8), CornerRadius = new CornerRadius(8), Foreground = ThemeBrush("HarborTextBrush") };
        var content = Row();
        content.VerticalAlignment = VerticalAlignment.Center;
        if (icon is not null) content.Children.Add(HarborIcon(icon.Value));
        if (label.Length > 0) content.Children.Add(new TextBlock { Text = label, FontFamily = (FontFamily)Application.Current.Resources["HarborUIFont"], FontSize = 12, VerticalAlignment = VerticalAlignment.Center });
        button.Content = content;
        if (hover) AddButtonHover(button);
        if (accent) ApplyAccentButton(button);
        button.Click += async (_, _) =>
        {
            button.IsEnabled = false;
            await RunAsync(action);
            button.IsEnabled = true;
        };
        return button;
    }

    private static Border Card(UIElement child) => new()
    {
        Child = child, Style = (Style)Application.Current.Resources["HarborCardStyle"]
    };

    private static ScrollViewer Scroll(UIElement content) => new()
    {
        Content = content, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        VerticalScrollBarVisibility = ScrollBarVisibility.Hidden, Padding = new Thickness(0)
    };

    private static void Copy(string value)
    {
        var package = new DataPackage();
        package.SetText(value);
        Clipboard.SetContent(package);
    }

    private ContentDialog Dialog(string title, UIElement content, string primary)
    {
        var animated = new Grid { RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5) };
        animated.Children.Add(content);
        animated.Loaded += (_, _) =>
        {
            if (!MotionEnabled) return;
            var scale = new ScaleTransform { ScaleX = 1.08, ScaleY = 1.08 }; animated.RenderTransform = scale;
            var storyboard = new Storyboard();
            foreach (var property in new[] { "ScaleX", "ScaleY" })
            {
                var animation = new DoubleAnimation { From = 1.08, To = 1, Duration = TimeSpan.FromMilliseconds(320), EnableDependentAnimation = true, EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } };
                Storyboard.SetTarget(animation, scale); Storyboard.SetTargetProperty(animation, property); storyboard.Children.Add(animation);
            }
            storyboard.Begin();
            dialogFocusReveal = HarborFocusReveal.PlayAsync(animated, 320, 8);
            _ = RunAsync(async () => await dialogFocusReveal);
        };
        return new ContentDialog
        {
            XamlRoot = Root.XamlRoot, RequestedTheme = Root.RequestedTheme, Title = title,
            Content = animated, PrimaryButtonText = primary, CloseButtonText = "Cancel",
            Background = ThemeBrush("HarborSurfaceBrush"), Foreground = ThemeBrush("HarborTextBrush"),
            PrimaryButtonStyle = (Style)Application.Current.Resources["HarborActionButtonStyle"],
            CloseButtonStyle = (Style)Application.Current.Resources["HarborActionButtonStyle"],
            SecondaryButtonStyle = (Style)Application.Current.Resources["HarborActionButtonStyle"],
            DefaultButton = ContentDialogButton.Primary
        };
    }

    private static void AddField(StackPanel panel, string title, string value)
    {
        var field = Stack(4);
        field.Children.Add(Muted(title));
        field.Children.Add(Text(string.IsNullOrEmpty(value) ? "Inherited from SSH config" : value));
        panel.Children.Add(field);
    }
}
