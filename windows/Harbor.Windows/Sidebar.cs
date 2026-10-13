using Harbor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Media.Imaging;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private readonly string[] navigationPages = ["workbench", "activity", "forwards", "keys"];
    private Storyboard? navigationMotion;
    private Storyboard? sidebarSearchMotion;
    private bool sidebarSearchVisible;
    private int navigationIndex = -1;
    private HashSet<string> priorSidebarRows = [];
    private HashSet<string> priorSidebarGroups = [];
    private bool sidebarWasRendered;
    private Dictionary<string, double> priorSidebarPositions = [];
    private void BuildNavigation()
    {
        var labels = new[] { "Workbench", "Activity", "Port mappings", "Keys" };
        var icons = new[] { Symbol.AllApps, Symbol.Clock, Symbol.Switch, Symbol.Permissions };
        for (var i = 0; i < labels.Length; i++)
        {
            var target = navigationPages[i];
            var button = ActionButton(labels[i], () => { ShowPage(target); return Task.CompletedTask; }, icons[i], hover: false);
            button.Height = 42;
            button.Style = (Style)Application.Current.Resources["HarborNavigationButtonStyle"];
            AddButtonHover(button, fillBounds: true);
            NavigationItems.Children.Add(button);
        }
        var menu = new MenuFlyout();
        var refresh = new MenuFlyoutItem { Text = "Refresh SSH config", Icon = new SymbolIcon(Symbol.Refresh) };
        refresh.Click += async (_, _) => await RunAsync(RefreshHostsAsync);
        var open = new MenuFlyoutItem { Text = "Open SSH config", Icon = new SymbolIcon(Symbol.OpenFile) };
        open.Click += (_, _) => WindowsIntegration.OpenConfig(config.Path);
        menu.Items.Add(refresh);
        menu.Items.Add(open);
        SidebarSearch.ContextFlyout = menu;
        SidebarHosts.ContextFlyout = ConnectionMenu(null);
        LibraryScrollViewer.ContextFlyout = ConnectionMenu(null);
        selectedHosts.IntersectWith(config.Document.Hosts.Select(host => host.Alias));
    }

    private void SelectNavigation(string target)
    {
        var index = Array.IndexOf(navigationPages, target);
        var previousIndex = navigationIndex;
        navigationIndex = index;
        var from = NavigationHighlightOffset.Y;
        navigationMotion?.Stop();
        NavigationHighlightOffset.Y = from;
        NavigationHighlight.Visibility = index < 0 ? Visibility.Collapsed : Visibility.Visible;
        SettingsButton.Foreground = ThemeBrush("HarborMutedBrush");
        for (var i = 0; i < NavigationItems.Children.Count; i++)
            ((Button)NavigationItems.Children[i]).Foreground = ThemeBrush(i == index ? "HarborAccentBrush" : "HarborMutedBrush");
        if (index < 0) return;
        if (!MotionEnabled) { NavigationHighlightOffset.Y = index * 48; NavigationHighlight.Opacity = 1; }
        else
        {
            navigationMotion = new Storyboard();
            var slide = previousIndex >= 0;
            if (!slide) NavigationHighlightOffset.Y = index * 48;
            NavigationHighlight.Opacity = 1;
            var animation = new DoubleAnimation
            {
                From = slide ? from : 0, To = slide ? index * 48 : 1, Duration = TimeSpan.FromMilliseconds(slide ? 280 : 190), EnableDependentAnimation = true,
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
            };
            Storyboard.SetTarget(animation, slide ? NavigationHighlightOffset : NavigationHighlight);
            Storyboard.SetTargetProperty(animation, slide ? "Y" : "Opacity");
            navigationMotion.Children.Add(animation);
            var current = navigationMotion;
            current.Completed += (_, _) =>
            {
                if (navigationMotion != current) return;
                current.Stop(); NavigationHighlightOffset.Y = index * 48; NavigationHighlight.Opacity = 1; navigationMotion = null;
            };
            navigationMotion.Begin();
        }
    }

    private void SidebarSearch_TextChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args)
    {
        search = sender.Text;
        if (initialized) RenderSidebarHosts();
    }

    private void OpenSidebarSearch()
    {
        if (sidebarSearchVisible) { SidebarSearch.Focus(FocusState.Programmatic); return; }
        sidebarSearchVisible = true;
        AnimateSidebarSearch(true);
        SidebarSearch.Focus(FocusState.Programmatic);
    }

    private void CloseSidebarSearch(bool returnFocus = true)
    {
        if (!sidebarSearchVisible) return;
        sidebarSearchVisible = false;
        if (returnFocus) NewConnectionButton.Focus(FocusState.Programmatic);
        SidebarSearch.Text = "";
        if (search.Length > 0) { search = ""; RenderSidebarHosts(); }
        AnimateSidebarSearch(false);
    }

    private void SidebarSearchPanel_SizeChanged(object sender, SizeChangedEventArgs args) =>
        SidebarSearchPanel.Clip = new RectangleGeometry { Rect = new Windows.Foundation.Rect(0, 0, args.NewSize.Width, args.NewSize.Height) };

    private void AnimateSidebarSearch(bool visible)
    {
        // Preserve the visible values when an interrupted animation reverses.
        var height = SidebarSearchPanel.ActualHeight;
        var opacity = SidebarSearchPanel.Opacity;
        sidebarSearchMotion?.Stop();
        sidebarSearchMotion = null;
        SidebarSearchPanel.Height = height;
        SidebarSearchPanel.Opacity = opacity;
        SidebarSearchPanel.Visibility = Visibility.Visible;
        SidebarSearchPanel.IsHitTestVisible = visible;
        var targetHeight = visible ? 36 : 0;
        var targetOpacity = visible ? 1 : 0;
        if (!MotionEnabled)
        {
            SidebarSearchPanel.Height = targetHeight;
            SidebarSearchPanel.Opacity = targetOpacity;
            SidebarSearchPanel.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
            return;
        }
        var motion = new Storyboard();
        var resize = new DoubleAnimation
        {
            From = height, To = targetHeight, Duration = TimeSpan.FromMilliseconds(220),
            EnableDependentAnimation = true,
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
        };
        var fade = new DoubleAnimation
        {
            From = opacity, To = targetOpacity, Duration = TimeSpan.FromMilliseconds(220),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
        };
        Storyboard.SetTarget(resize, SidebarSearchPanel); Storyboard.SetTargetProperty(resize, "Height"); motion.Children.Add(resize);
        Storyboard.SetTarget(fade, SidebarSearchPanel); Storyboard.SetTargetProperty(fade, "Opacity"); motion.Children.Add(fade);
        motion.Completed += (_, _) =>
        {
            if (sidebarSearchMotion != motion) return;
            motion.Stop();
            SidebarSearchPanel.Height = targetHeight;
            SidebarSearchPanel.Opacity = targetOpacity;
            SidebarSearchPanel.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
            sidebarSearchMotion = null;
        };
        sidebarSearchMotion = motion;
        motion.Begin();
    }

    private void SidebarSearch_KeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs args)
    {
        if (args.Key != Windows.System.VirtualKey.Escape) return;
        args.Handled = true;
        CloseSidebarSearch();
    }

    private void SidebarRoot_PointerPressed(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs args)
    {
        if (!sidebarSearchVisible || SidebarSearch.Text.Length > 0) return;
        var source = args.OriginalSource as DependencyObject;
        if (IsWithin(source, SidebarSearchPanel)) return;
        CloseSidebarSearch(returnFocus: false);
    }

    private static bool IsWithin(DependencyObject? element, DependencyObject ancestor)
    {
        for (var current = element; current is not null; current = VisualTreeHelper.GetParent(current))
            if (ReferenceEquals(current, ancestor)) return true;
        return false;
    }

    private async void NewConnection_Click(object sender, RoutedEventArgs args) => await RunAsync(() => EditHostAsync(null));
    private void Settings_Click(object sender, RoutedEventArgs args) => ShowPage("settings");

    private void RenderSidebarHosts()
    {
        RestoreStickyHeader();
        priorSidebarPositions = CaptureSidebarPositions();
        priorSidebarGroups = SidebarHosts.Children.OfType<HarborHostSection>().Select(section => section.HeaderButton.Tag as string ?? "").ToHashSet();
        priorSidebarRows = SidebarHosts.Children.OfType<HarborHostSection>().SelectMany(section => section.HostButtons.Select(button => $"{section.HeaderButton.Tag}\0{button.Tag}")).ToHashSet();
        SidebarHosts.Children.Clear();
        SidebarHosts.ContextFlyout = ConnectionMenu(null);
        LibraryScrollViewer.ContextFlyout = ConnectionMenu(null);
        var hosts = config.Document.Hosts.Where(h => $"{h.Alias} {h.Subtitle} {preferences.Value.HostGroups.GetValueOrDefault(h.Alias, "")} {string.Join(' ', preferences.Value.HostTags.GetValueOrDefault(h.Alias, []))}".Contains(search, StringComparison.OrdinalIgnoreCase)).ToList();
        var favorites = hosts.Where(h => preferences.Value.Favorites.Contains(h.Alias)).ToList();
        var sectionNames = ConnectionGroups().Concat(favorites.Count > 0 ? new[] { "Favorites" } : []).OrderBy(name =>
        {
            var index = preferences.Value.SectionOrder.IndexOf(name);
            return index >= 0 ? index : name == "Favorites" ? -1 : int.MaxValue;
        }).ToList();
        foreach (var group in sectionNames)
        {
            if (group == "Favorites") { AddSidebarGroup(group, favorites, true); continue; }
            var members = hosts.Where(h => preferences.Value.HostGroups.GetValueOrDefault(h.Alias) == group).ToList();
            if (search.Length == 0 || members.Count > 0) AddSidebarGroup(group, members, false);
        }
        var ungrouped = hosts.Where(h => !preferences.Value.HostGroups.TryGetValue(h.Alias, out var name) || string.IsNullOrWhiteSpace(name)).ToList();
        if (ungrouped.Count > 0) AddSidebarGroup("Ungrouped", ungrouped, false);
        if (hosts.Count == 0) SidebarHosts.Children.Add(Muted(search.Length > 0 ? "No matching connections." : "Add your first connection."));
        UpdateHostSelection();
        SidebarHosts.UpdateLayout();
        AnimateSidebarReflow(priorSidebarPositions);
        sidebarWasRendered = true;
        UpdateStickyHeader();
    }

    private Dictionary<string, double> CaptureSidebarPositions()
    {
        var positions = new Dictionary<string, double>(StringComparer.Ordinal);
        if (!sidebarWasRendered || SidebarHosts.ActualHeight <= 0) return positions;
        foreach (var section in SidebarHosts.Children.OfType<HarborHostSection>())
        {
            var group = section.HeaderButton.Tag as string ?? "";
            try
            {
                positions[$"group\0{group}"] = section.TransformToVisual(SidebarHosts).TransformPoint(new Windows.Foundation.Point()).Y;
                foreach (var button in section.HostButtons)
                    positions[$"host\0{group}\0{button.Tag}"] = button.TransformToVisual(SidebarHosts).TransformPoint(new Windows.Foundation.Point()).Y;
            }
            catch (InvalidOperationException) { }
        }
        return positions;
    }

    private void AnimateSidebarReflow(IReadOnlyDictionary<string, double> previous)
    {
        if (!MotionEnabled || previous.Count == 0) return;
        foreach (var section in SidebarHosts.Children.OfType<HarborHostSection>())
        {
            var group = section.HeaderButton.Tag as string ?? "";
            AnimateFromOldPosition(section, $"group\0{group}", previous);
            foreach (var button in section.HostButtons)
                AnimateFromOldPosition(button, $"host\0{group}\0{button.Tag}", previous);
        }
    }

    private void AnimateFromOldPosition(FrameworkElement element, string key, IReadOnlyDictionary<string, double> previous)
    {
        if (!previous.TryGetValue(key, out var oldY)) return;
        double newY;
        try { newY = element.TransformToVisual(SidebarHosts).TransformPoint(new Windows.Foundation.Point()).Y; }
        catch (InvalidOperationException) { return; }
        var delta = oldY - newY;
        if (Math.Abs(delta) < 1) return;
        var offset = new Microsoft.UI.Xaml.Media.TranslateTransform { Y = delta };
        element.RenderTransform = offset;
        var storyboard = new Storyboard();
        var animation = new DoubleAnimation { From = delta, To = 0, Duration = TimeSpan.FromMilliseconds(280), EnableDependentAnimation = true, EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } };
        Storyboard.SetTarget(animation, offset); Storyboard.SetTargetProperty(animation, "Y"); storyboard.Children.Add(animation);
        storyboard.Completed += (_, _) =>
        {
            storyboard.Stop();
            if (ReferenceEquals(element.RenderTransform, offset)) element.RenderTransform = null;
        };
        storyboard.Begin();
    }

    private void AddSidebarGroup(string name, IReadOnlyList<SshHost> hosts, bool favorites)
    {
        var content = Stack(4);
        var order = preferences.Value.HostOrder.GetValueOrDefault(name, []);
        foreach (var host in hosts.OrderBy(host => { var index = order.IndexOf(host.Alias); return index >= 0 ? index : int.MaxValue; }))
        {
            var row = new Grid { ColumnSpacing = 10, Padding = new Thickness(4, 4, 4, 4) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(28) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.Children.Add(HostMark(host, 28));
            var text = Stack(3);
            var title = Text(host.Alias, 12);
            title.TextWrapping = TextWrapping.NoWrap;
            title.TextTrimming = TextTrimming.CharacterEllipsis;
            text.Children.Add(title);
            if (preferences.Value.ShowServerAddresses)
            {
                var address = Muted(host.Destination, 10);
                address.TextWrapping = TextWrapping.NoWrap;
                address.TextTrimming = TextTrimming.CharacterEllipsis;
                text.Children.Add(address);
            }
            Grid.SetColumn(text, 1);
            row.Children.Add(text);
            var favorite = FavoriteButton(host, 12);
            favorite.Width = 24; favorite.Height = 24;
            Grid.SetColumn(favorite, 2); row.Children.Add(favorite);
            var button = new Button { Content = row, MinHeight = 44, HorizontalContentAlignment = HorizontalAlignment.Stretch,
                Style = (Style)Application.Current.Resources["HarborNavigationButtonStyle"], Padding = new Thickness(6, 4, 6, 4) };
            button.Tag = host.Alias;
            button.DataContext = name;
            AddButtonHover(button);
            button.Click += (_, _) => { if (!suppressSidebarClick) SelectHost(host, name); };
            button.RightTapped += (_, _) => SelectContextHost(host, name);
            button.ContextFlyout = ConnectionMenu(host);
            ConfigureHostDrag(button, host);
            ConfigureSidebarDrop(button, name, host.Alias);
            content.Children.Add(button);
            if (sidebarWasRendered && priorSidebarGroups.Contains(name) && !priorSidebarRows.Contains($"{name}\0{host.Alias}")) AnimateReveal(button);
        }
        var section = new HarborHostSection(name, hosts.Count, content,
            preferences.Value.CollapsedGroups.Contains(name), () => MotionEnabled, favorites);
        section.HeaderButton.ContextFlyout = ConnectionMenu(null, name);
        section.HeaderButton.Tag = name;
        ConfigureSidebarDrop(section.HeaderButton, name, null);
        ConfigureGroupDrag(section.HeaderButton, name);
        section.SetAppearance(preferences.Value.GroupIcons.TryGetValue(name, out var icon) ? HostIconGlyphs.GetValueOrDefault(icon, "\uE8B7") : null, GroupBrush(name));
        section.Toggled += async collapsed => await RunAsync(async () =>
        {
            if (collapsed) preferences.Value.CollapsedGroups.Add(name); else preferences.Value.CollapsedGroups.Remove(name);
            await SavePreferencesAsync();
        });
        SidebarHosts.Children.Add(section);
        if (sidebarWasRendered && !priorSidebarGroups.Contains(name)) AnimateReveal(section);
    }

    private Brush ThemeBrush(string key)
    {
        if (Root.Resources.TryGetValue(key, out var local)) return (Brush)local;
        var dictionaries = Application.Current.Resources.ThemeDictionaries;
        var dictionary = (ResourceDictionary)dictionaries[Root.ActualTheme == ElementTheme.Light ? "Light" : "Default"];
        return (Brush)dictionary[key];
    }

    private void UpdateAccent()
    {
        var dark = Root.ActualTheme == ElementTheme.Dark;
        var colors = preferences.Value.Accent switch
        {
            "Teal" => (0xFF28796DUL, 0xFF69BDB0UL), "Blue" => (0xFF386FA3UL, 0xFF7FAED5UL),
            "Violet" => (0xFF7354A6UL, 0xFFAA9BDCUL), "Rose" => (0xFFA34F70UL, 0xFFD68EAAUL),
            _ => (0xFF9A5427UL, 0xFFE5A16BUL)
        };
        var packed = dark ? colors.Item2 : colors.Item1;
        var color = Windows.UI.Color.FromArgb(255, (byte)(packed >> 16), (byte)(packed >> 8), (byte)packed);
        var brush = new SolidColorBrush(color);
        Root.Resources["HarborAccentBrush"] = brush;
        Root.Resources["HarborSelectionBrush"] = new SolidColorBrush(Windows.UI.Color.FromArgb(dark ? (byte)77 : (byte)61, color.R, color.G, color.B));
        foreach (var key in new[] { "AccentFillColorDefaultBrush", "AccentFillColorSecondaryBrush", "AccentFillColorTertiaryBrush", "AccentTextFillColorPrimaryBrush" }) Root.Resources[key] = brush;
        ApplyAccentButton(NewConnectionButton);
        AppWindow.TitleBar.ButtonForegroundColor = dark ? Microsoft.UI.Colors.White : Microsoft.UI.Colors.Black;
        if (initialized) { SelectNavigation(page); RenderSidebarHosts(); }
    }

    private void ApplyAccentButton(Button button)
    {
        var brush = ThemeBrush("HarborAccentBrush");
        button.Background = brush;
        button.Foreground = new SolidColorBrush(Root.ActualTheme == ElementTheme.Dark ? Microsoft.UI.Colors.Black : Microsoft.UI.Colors.White);
        foreach (var key in new[] { "AccentButtonBackground", "AccentButtonBackgroundPointerOver", "AccentButtonBackgroundPressed", "AccentButtonBorderBrush" }) button.Resources[key] = brush;
        foreach (var key in new[] { "AccentButtonForeground", "AccentButtonForegroundPointerOver", "AccentButtonForegroundPressed" }) button.Resources[key] = button.Foreground;
    }

    private void ApplyAccentToggle(HarborSwitch toggle)
    {
        toggle.OnBrush = ThemeBrush("HarborAccentBrush");
        toggle.MotionAllowed = () => MotionEnabled;
        toggle.OffBrush = ThemeBrush("HarborBorderBrush");
        toggle.Refresh();
        toggle.MinWidth = 0;
        toggle.Width = 44;
        toggle.VerticalAlignment = VerticalAlignment.Center;
        foreach (var key in new[] { "ToggleSwitchFillOn", "ToggleSwitchFillOnPointerOver", "ToggleSwitchFillOnPressed" }) toggle.Resources[key] = ThemeBrush("HarborAccentBrush");
    }
}
