using Harbor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private async Task LaunchConnectionAsync(string alias)
    {
        WindowsIntegration.LaunchTerminal(WindowsIntegration.FindOpenSsh("ssh.exe"), await ConnectionArgumentsAsync(alias), preferences.Value.PreferWindowsTerminal);
        if (preferences.Value.RecordRecent)
        {
            preferences.Value.RecentHosts.RemoveAll(value => value == alias);
            preferences.Value.RecentHosts.Insert(0, alias);
            if (preferences.Value.RecentHosts.Count > 20) preferences.Value.RecentHosts.RemoveRange(20, preferences.Value.RecentHosts.Count - 20);
            await SavePreferencesAsync();
            if (page == "workbench") RenderWorkbench();
        }
    }

    private async Task ChangeHostGroupAsync(SshHost host)
    {
        var form = new Grid { RowSpacing = 12 };
        form.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); form.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); form.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        form.Children.Add(Muted("Choose an existing group or enter a new name."));
        var input = new HarborTextBox { Text = preferences.Value.HostGroups.GetValueOrDefault(host.Alias, ""), PlaceholderText = "Group name (empty to ungroup)" };
        Grid.SetRow(input, 1); form.Children.Add(input); input.Loaded += (_, _) => input.Focus(FocusState.Programmatic);
        var choices = new WrapPanel(); foreach (var name in ConnectionGroups()) choices.Children.Add(ActionButton(name, () => { input.Text = name; return Task.CompletedTask; }));
        var scroller = Scroll(choices); Grid.SetRow(scroller, 2); form.Children.Add(scroller);
        var result = await ShowSheetAsync("Organize host", form, "Save group", () => input.Text.Trim(), 400, 280, () => input.Text.Length <= 80 && !input.Text.Any(char.IsControl));
        if (result is null) return;
        preferences.Value.HostGroups.Remove(host.Alias);
        if (result.Length > 0 && result != "Ungrouped") { preferences.Value.HostGroups[host.Alias] = result; preferences.Value.ExplicitGroups.Add(result); }
        await SavePreferencesAsync(); PopulateHosts();
    }
    private static readonly Dictionary<string, string> HostIconGlyphs = new()
    {
        ["Server"] = "\uE968", ["Desktop"] = "\uE7F4", ["Laptop"] = "\uE770", ["Cloud"] = "\uE753",
        ["Database"] = "\uE8F1", ["Code"] = "\uE943", ["Network"] = "\uE774", ["Shield"] = "\uEA18",
        ["Home"] = "\uE80F", ["Lab"] = "\uE9F5", ["Folder"] = "\uE8B7", ["Briefcase"] = "\uE821",
        ["Archive"] = "\uE7B8", ["Build"] = "\uE80A"
    };
    private static readonly Dictionary<string, uint> GroupPalette = new()
    {
        ["Teal"] = 0x69BDB0, ["Violet"] = 0xAA9BDC, ["Amber"] = 0xE5A16B, ["Blue"] = 0x7FAED5, ["Rose"] = 0xD68EAA
    };
    private IEnumerable<string> ConnectionGroups() => preferences.Value.ExplicitGroups.Concat(preferences.Value.HostGroups.Values)
        .Where(name => !string.IsNullOrWhiteSpace(name) && name is not "Ungrouped" and not "Favorites")
        .Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(name => name, StringComparer.OrdinalIgnoreCase);

    private Brush GroupBrush(string group)
    {
        var chosen = preferences.Value.GroupColors.GetValueOrDefault(group, "");
        var packed = group == "Favorites" ? 0xE5A16Bu : GroupPalette.GetValueOrDefault(chosen,
            GroupPalette.Values.ElementAt(group.EnumerateRunes().Sum(rune => rune.Value) % GroupPalette.Count));
        if (Root.ActualTheme == ElementTheme.Light)
            packed = packed switch { 0x69BDB0 => 0x28796D, 0xAA9BDC => 0x7354A6, 0xE5A16B => 0x9A5427, 0x7FAED5 => 0x386FA3, 0xD68EAA => 0xA34F70, _ => packed };
        return new SolidColorBrush(Windows.UI.Color.FromArgb(255, (byte)(packed >> 16), (byte)(packed >> 8), (byte)packed));
    }

    private UIElement HostMark(SshHost host, double size)
    {
        var color = GroupBrush(preferences.Value.HostGroups.GetValueOrDefault(host.Alias, "Ungrouped"));
        UIElement glyph;
        if (preferences.Value.HostIcons.TryGetValue(host.Alias, out var icon) && HostIconGlyphs.TryGetValue(icon, out var glyphCode))
            glyph = new FontIcon { Glyph = glyphCode, FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"), FontSize = size * 0.52, Foreground = color, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        else
            glyph = new TextBlock { Text = host.Alias.Length == 0 ? "?" : host.Alias[..1].ToUpperInvariant(), FontFamily = (FontFamily)Application.Current.Resources["HarborUIFont"], FontSize = size * 0.39, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Foreground = color, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        return new Border { Width = size, Height = size, CornerRadius = new CornerRadius(size * 0.25), Background = new SolidColorBrush(Windows.UI.Color.FromArgb(33,
            (byte)((color as SolidColorBrush)?.Color.R ?? 0), (byte)((color as SolidColorBrush)?.Color.G ?? 0), (byte)((color as SolidColorBrush)?.Color.B ?? 0))),
            Child = glyph, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
    }

    private void MigrateHostMetadata(string oldAlias, string alias)
    {
        var prefs = preferences.Value;
        if (prefs.HostTags.Remove(oldAlias, out var tags)) prefs.HostTags[alias] = tags;
        if (prefs.HostIcons.Remove(oldAlias, out var icon)) prefs.HostIcons[alias] = icon;
        if (prefs.ConnectionProxies.Remove(oldAlias, out var proxy)) prefs.ConnectionProxies[alias] = proxy;
        foreach (var order in prefs.HostOrder.Values)
            for (var i = 0; i < order.Count; i++) if (order[i] == oldAlias) order[i] = alias;
        for (var i = 0; i < prefs.RecentHosts.Count; i++) if (prefs.RecentHosts[i] == oldAlias) prefs.RecentHosts[i] = alias;
    }

    private async Task RenameHostAsync(SshHost host)
    {
        var alias = new HarborTextBox { Text = host.Alias, MinWidth = 320 };
        var error = Muted(""); var form = Stack(); form.Children.Add(alias); form.Children.Add(error);
        var dialog = Dialog("Rename connection", form, "Rename");
        dialog.Loaded += (_, _) => { alias.Focus(FocusState.Programmatic); alias.SelectAll(); };
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            var deferral = args.GetDeferral();
            try
            {
                var name = alias.Text.Trim();
                if (name == host.Alias) return;
                if (processes?.Sessions.Any(session => session.Active && session.Rule.HostAlias == host.Alias) == true)
                    throw new InvalidOperationException("Stop this connection's mappings before renaming it.");
                await config.SaveHostAsync(new HostDraft(name, host.HostName, host.User, host.Port, host.IdentityFile, host.ProxyJump), host);
                var prefs = preferences.Value;
                MigrateHostMetadata(host.Alias, name);
                if (prefs.HostGroups.Remove(host.Alias, out var group)) prefs.HostGroups[name] = group;
                if (prefs.Favorites.Remove(host.Alias)) prefs.Favorites.Add(name);
                prefs.Forwards = prefs.Forwards.Select(rule => rule.HostAlias == host.Alias ? rule with { HostAlias = name } : rule).ToList();
                selectedAlias = name;
                await SavePreferencesAsync();
            }
            catch (Exception exception) { args.Cancel = true; error.Text = exception.Message; }
            finally { deferral.Complete(); }
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary) PopulateHosts();
    }

    private async Task EditTagsAsync(SshHost host)
    {
        var input = new HarborTextBox { Text = string.Join(", ", preferences.Value.HostTags.GetValueOrDefault(host.Alias, [])), PlaceholderText = "work, production", MinWidth = 340 };
        var form = Stack(); form.Children.Add(Muted("Separate tags with commas. Clear the field to remove all tags.")); form.Children.Add(input);
        var suggestions = new WrapPanel();
        foreach (var tag in preferences.Value.HostTags.Values.SelectMany(tags => tags).Distinct().OrderBy(tag => tag))
            suggestions.Children.Add(ActionButton($"#{tag}", () =>
            {
                var tags = NormalizeTags(input.Text).ToList(); if (!tags.Remove(tag)) tags.Add(tag); input.Text = string.Join(", ", tags); return Task.CompletedTask;
            }));
        form.Children.Add(suggestions);
        if (await Dialog("Server tags", form, "Save tags").ShowAsync() != ContentDialogResult.Primary) return;
        var normalized = NormalizeTags(input.Text).ToList();
        if (normalized.Count == 0) preferences.Value.HostTags.Remove(host.Alias); else preferences.Value.HostTags[host.Alias] = normalized;
        await SavePreferencesAsync(); PopulateHosts();
    }

    private static IEnumerable<string> NormalizeTags(string text) => text.Split([',', '，']).Select(tag => tag.Trim().TrimStart('#')).Where(tag => tag.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase);

    private Button IconChoice(string name, string glyph, double width, double height, Func<Task> action)
    {
        var button = ActionButton("", action);
        button.Style = (Style)Application.Current.Resources["HarborQuietButtonStyle"];
        button.Background = ThemeBrush("HarborBackgroundBrush");
        button.BorderThickness = new Thickness(1);
        button.BorderBrush = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        button.Content = new FontIcon { Glyph = glyph, FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"), FontSize = 23 };
        button.Width = width; button.Height = height; button.Padding = new Thickness(0);
        ToolTipService.SetToolTip(button, name);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(button, name);
        return button;
    }

    private async Task ChooseHostIconAsync(SshHost host)
    {
        var choices = new WrapPanel();
        var dialog = Dialog("Connection icon", choices, "Done");
        dialog.SecondaryButtonText = "Use initial";
        dialog.SecondaryButtonClick += async (_, _) => await RunAsync(async () =>
        {
            preferences.Value.HostIcons.Remove(host.Alias); await SavePreferencesAsync(); PopulateHosts();
        });
        foreach (var entry in HostIconGlyphs.Take(10))
        {
            var button = IconChoice(entry.Key, entry.Value, 56, 48, async () =>
            {
                preferences.Value.HostIcons[host.Alias] = entry.Key;
                await SavePreferencesAsync(); PopulateHosts(); dialog.Hide();
            });
            button.Foreground = GroupBrush(preferences.Value.HostGroups.GetValueOrDefault(host.Alias, "Ungrouped"));
            if (preferences.Value.HostIcons.GetValueOrDefault(host.Alias) == entry.Key) button.BorderBrush = ThemeBrush("HarborAccentBrush");
            choices.Children.Add(button);
        }
        await dialog.ShowAsync();
    }

    private async Task GroupAppearanceAsync(string group)
    {
        var form = Stack(18);
        var dialog = Dialog(group, form, "Done");
        void Populate()
        {
            form.Children.Clear(); form.Children.Add(Muted("Color", 11));
            var colors = Row(10);
            foreach (var entry in GroupPalette)
            {
                var button = ActionButton(preferences.Value.GroupColors.GetValueOrDefault(group) == entry.Key ? "✓" : "", async () =>
                {
                    preferences.Value.GroupColors[group] = entry.Key;
                    await SavePreferencesAsync(); PopulateHosts(); Populate();
                });
                button.Style = (Style)Application.Current.Resources["HarborQuietButtonStyle"];
                button.Width = 30; button.Height = 30; button.Padding = new Thickness(0); button.CornerRadius = new CornerRadius(15);
                var packed = entry.Value; button.Background = new SolidColorBrush(Windows.UI.Color.FromArgb(255, (byte)(packed >> 16), (byte)(packed >> 8), (byte)packed));
                ToolTipService.SetToolTip(button, entry.Key); Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(button, entry.Key); colors.Children.Add(button);
            }
            form.Children.Add(colors); form.Children.Add(Muted("Icon", 11));
            var icons = new WrapPanel();
            foreach (var entry in HostIconGlyphs.Where(entry => entry.Key is not "Desktop" and not "Laptop"))
            {
                var button = IconChoice(entry.Key, entry.Value, 48, 42, async () =>
                {
                    preferences.Value.GroupIcons[group] = entry.Key;
                    await SavePreferencesAsync(); PopulateHosts(); Populate();
                });
                button.Foreground = GroupBrush(group);
                if (preferences.Value.GroupIcons.GetValueOrDefault(group) == entry.Key) button.BorderBrush = GroupBrush(group);
                icons.Children.Add(button);
            }
            form.Children.Add(icons);
            form.Children.Add(ActionButton("Reset", async () =>
            {
                preferences.Value.GroupIcons.Remove(group); preferences.Value.GroupColors.Remove(group);
                await SavePreferencesAsync(); PopulateHosts(); Populate();
            }));
        }
        Populate(); await dialog.ShowAsync();
    }
}
