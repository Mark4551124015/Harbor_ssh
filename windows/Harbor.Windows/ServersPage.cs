using Harbor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private void RenderServers()
    {
        PageContent.Children.Clear();
        hostDetails = Stack(20);
        PageContent.Children.Add(Scroll(hostDetails));
        var host = config.Document.Hosts.FirstOrDefault(h => h.Alias == selectedAlias) ?? config.Document.Hosts.FirstOrDefault();
        if (host is not null) { selectedAlias = host.Alias; RenderHostDetails(host); }
        else
        {
            hostDetails.Children.Add(Text("Your workspace starts here.", 24));
            hostDetails.Children.Add(Muted("Add a connection using the sidebar."));
            hostDetails.Children.Add(ActionButton("New connection", () => EditHostAsync(null), Symbol.Add, accent: true));
        }
    }

    private void PopulateHosts()
    {
        RenderSidebarHosts();
        if (page == "workbench") RenderWorkbench();
        if (page == "servers") RenderServers();
    }

    private void RenderHostDetails(SshHost host)
    {
        if (hostDetails is null) return;
        hostDetails.Children.Clear();
        PageTitle.Text = host.Alias;
        PageTitle.FontSize = 21.5;
        PageDescription.FontSize = 10;
        if (PageTitle.Parent is StackPanel titleStack) titleStack.Spacing = 4;
        var groupName = preferences.Value.HostGroups.GetValueOrDefault(host.Alias, "Ungrouped");
        var tags = preferences.Value.HostTags.GetValueOrDefault(host.Alias, []);
        PageDescription.Text = $"{groupName} · {host.HostName}{(tags.Count == 0 ? "" : $" · {string.Join(" ", tags.Select(tag => $"#{tag}"))}")}";
        if (host.HostName.Length == 0) PageDescription.Text = $"{groupName}{(tags.Count == 0 ? "" : $" · {string.Join(" ", tags.Select(tag => $"#{tag}"))}")}";
        PageMark.Child = HostMark(host, 42); PageMark.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent); PageMark.Visibility = Visibility.Visible;
        HeaderActions.Children.Clear();
        HeaderActions.Children.Add(FavoriteButton(host, 18));
        var save = ActionButton("Save", async () =>
        {
            if (saveCurrentHost is null) DraftSaveButton(host, new StackPanel());
            if (saveCurrentHost is not null) await saveCurrentHost();
        }, Symbol.Save);
        save.IsEnabled = host.CanEdit;
        save.Width = 100; save.Height = 40;
        hostSaveButton = save;
        HeaderActions.Children.Add(save);
        HeaderActions.Children.Add(ActionButton("Open Terminal", () => LaunchConnectionAsync(host.Alias), Symbol.Go, accent: true));
        if (detailAlias != host.Alias) { detailAlias = host.Alias; detailTab = "Overview"; }
        var layers = new Grid { MinHeight = 200 };
        hostDetails.Children.Add(layers);
        var transition = new HarborPageTransition(layers);
        void PopulateTab()
        {
            saveCurrentHost = null;
            var body = Stack(20);
            switch (detailTab)
            {
                case "General": RenderGeneralDetails(host, body); break;
                case "Connection": RenderConnectionDetails(host, body); break;
                case "Advanced": RenderAdvancedDetails(host, body); break;
                case "Port mapping": RenderConfigMappings(host, body); break;
                default:
                    var info = Stack(12);
                    var infoHeading = new Grid();
                    var infoTitle = Text("Connection details", 13); infoTitle.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold; infoHeading.Children.Add(infoTitle);
                    var status = Muted(processes?.Sessions.Any(session => session.Active && session.Rule.HostAlias == host.Alias) == true ? "Tunnels running" : "Tunnels inactive", 11);
                    status.HorizontalAlignment = HorizontalAlignment.Right; infoHeading.Children.Add(status); info.Children.Add(infoHeading);
                    foreach (var (label, value) in new[] { ("Host", host.HostName.Length == 0 ? "Not configured" : host.HostName), ("Username", host.User.Length == 0 ? "Default user" : host.User), ("Port", host.Port.Length == 0 ? "22" : host.Port) })
                    {
                        var row = new Grid { Padding = new Thickness(0, 5, 0, 5), ColumnSpacing = 12 };
                        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(108) }); row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                        row.Children.Add(Muted(label)); var field = Text(value, 13); Grid.SetColumn(field, 1); row.Children.Add(field); info.Children.Add(row);
                    }
                    body.Children.Add(Card(info));
                    var preview = Stack(12);
                    var commandHeading = new Grid(); commandHeading.Children.Add(Text("SSH command", 14));
                    var copy = ActionButton("", async () => Copy(SshCommands.DisplayCommand("ssh.exe", await ConnectionArgumentsAsync(host.Alias))), Symbol.Copy);
                    copy.Style = (Style)Application.Current.Resources["HarborIconButtonStyle"];
                    copy.Padding = new Thickness(0); copy.Content = HarborIcon(Symbol.Copy, 14); AddButtonHover(copy);
                    copy.HorizontalAlignment = HorizontalAlignment.Right;
                    ToolTipService.SetToolTip(copy, "Copy SSH command");
                    Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(copy, "Copy SSH command");
                    commandHeading.Children.Add(copy); preview.Children.Add(commandHeading);
                    preview.Children.Add(Muted("Run this command in your terminal to connect."));
                    var command = Text(SshCommands.DisplayCommand("ssh.exe", SshCommands.Connect(config.Path, host.Alias)), 12);
                    command.FontFamily = new FontFamily("Consolas"); command.IsTextSelectionEnabled = true;
                    preview.Children.Add(Card(command)); body.Children.Add(preview);
                    var mappings = Stack(12); mappings.Children.Add(Text("Port forwarding", 13));
                    var configured = config.Document.HostOptions(host).Where(option => option.Key is "localforward" or "remoteforward" or "dynamicforward").ToList();
                    if (configured.Count == 0) mappings.Children.Add(Card(Muted("Add forwarding settings in the Port mapping tab.")));
                    foreach (var option in configured) mappings.Children.Add(Card(Text($"{(option.Key == "dynamicforward" ? "SOCKS5" : option.Key == "remoteforward" ? "Remote" : "Local")} · {option.Value}", 12)));
                    body.Children.Add(mappings);
                    break;
            }
            if (!host.CanEdit) body.Children.Add(Muted("This connection belongs to a compound or repeated Host block. Edit it in your SSH config editor."));
            var canvas = new Grid { Style = (Style)Application.Current.Resources["HarborCanvasStyle"] }; canvas.Children.Add(body);
            transition.Show(canvas, MotionEnabled);
            UpdateHostSaveState();
        }
        var tabs = new HarborTabStrip(["Overview", "General", "Connection", "Advanced", "Port mapping"], detailTab,
            ThemeBrush("HarborTextBrush"), ThemeBrush("HarborMutedBrush"), ThemeBrush("HarborAccentBrush"), () => MotionEnabled,
            tab => { detailTab = tab; PopulateTab(); }, capsule: true, selectedTint: ThemeBrush("HarborAccentBrush"));
        hostDetails.Children.Insert(0, tabs);
        PopulateTab();
    }
    private async Task RefreshHostsAsync()
    {
        await config.LoadAsync();
        PopulateHosts();
        ShowNotice($"Loaded {config.Document.Hosts.Count} named hosts from SSH config.", InfoBarSeverity.Success);
    }

    private async Task EditHostAsync(SshHost? host, string? initialGroup = null)
    {
        var form = Stack();
        TextBox Field(string label, string value, string placeholder = "")
        {
            var input = new HarborTextBox { Header = label, Text = value, PlaceholderText = placeholder, MinWidth = 360 };
            form.Children.Add(input);
            return input;
        }
        var alias = Field("Alias", host?.Alias ?? "", "production");
        var address = Field("Host name or IP address", host?.HostName ?? "", "server.example.com");
        var user = Field("Username", host?.User ?? "", "Inherit from SSH config");
        var port = Field("Port", host?.Port ?? "", "Inherit from SSH config");
        var identity = Field("Identity file", host?.IdentityFile ?? "", "~/.ssh/id_ed25519");
        var jump = Field("Jump hosts", host?.ProxyJump ?? "", "bastion,internal-gateway");
        var group = Field("Group", host is null ? (initialGroup is "Favorites" or "Ungrouped" ? "" : initialGroup ?? "") : preferences.Value.HostGroups.GetValueOrDefault(host.Alias, ""), "Ungrouped");
        form.Children.Add(Muted("Other directives and comments are preserved. Existing files are backed up in config_bk before saving."));
        var error = Text("");
        error.Style = (Style)Application.Current.Resources["HarborErrorTextStyle"];
        form.Children.Add(error);
        var dialogScroll = new ScrollViewer { Content = form, MaxHeight = 500, HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden };
        var dialog = Dialog(host is null ? "Add server" : "Edit server", dialogScroll, "Save");
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            var deferral = args.GetDeferral();
            try
            {
                var draft = new HostDraft(alias.Text.Trim(), address.Text.Trim(), user.Text.Trim(), port.Text.Trim(), identity.Text.Trim(), jump.Text.Trim());
                if (group.Text.Trim().Equals("Favorites", StringComparison.OrdinalIgnoreCase) || group.Text.Length > 80 || group.Text.Any(char.IsControl))
                    throw new ArgumentException("Choose a group name up to 80 characters. Favorites is reserved.");
                if (host is not null && host.Alias != draft.Alias && processes?.Sessions.Any(session => session.Active && session.Rule.HostAlias == host.Alias) == true)
                    throw new InvalidOperationException("Stop this server's port forwards before renaming it.");
                await config.SaveHostAsync(draft, host);
                selectedAlias = draft.Alias;
            }
            catch (Exception exception) { args.Cancel = true; error.Text = exception.Message; }
            finally { deferral.Complete(); }
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            PopulateHosts();
            ShowNotice("SSH config saved.", InfoBarSeverity.Success);
            if (settingsLoaded)
            {
                preferences.Value.HostGroups.Remove(host?.Alias ?? selectedAlias!);
                if (group.Text.Trim().Length > 0) preferences.Value.HostGroups[selectedAlias!] = group.Text.Trim();
                try { await SavePreferencesAsync(); }
                catch (Exception exception) { ShowNotice($"SSH config saved, but group preferences could not be saved: {exception.Message}", InfoBarSeverity.Warning); }
                PopulateHosts();
            }
            if (host is not null && host.Alias != selectedAlias && settingsLoaded)
            {
                MigrateHostMetadata(host.Alias, selectedAlias!);
                if (preferences.Value.Favorites.Remove(host.Alias)) preferences.Value.Favorites.Add(selectedAlias!);
                preferences.Value.Forwards = preferences.Value.Forwards.Select(rule => rule.HostAlias == host.Alias ? rule with { HostAlias = selectedAlias! } : rule).ToList();
                try { await SavePreferencesAsync(); }
                catch (Exception exception) { ShowNotice($"SSH config saved, but Windows preferences could not be updated: {exception.Message}", InfoBarSeverity.Warning); }
                PopulateHosts();
            }
        }
    }

    private async Task DeleteHostAsync(SshHost host)
    {
        var dialog = Dialog("Delete server?", Text($"Remove '{host.Alias}' from your SSH config? A backup will be kept in config_bk."), "Delete");
        dialog.DefaultButton = ContentDialogButton.Close;
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        if (processes?.Sessions.Any(s => s.Active && s.Rule.HostAlias == host.Alias) == true)
            throw new InvalidOperationException("Stop this server's port forwards before deleting it.");
        await config.DeleteHostAsync(host);
        preferences.Value.Favorites.Remove(host.Alias);
        preferences.Value.HostGroups.Remove(host.Alias);
        preferences.Value.HostTags.Remove(host.Alias);
        preferences.Value.HostIcons.Remove(host.Alias);
        preferences.Value.ConnectionProxies.Remove(host.Alias);
        preferences.Value.RecentHosts.RemoveAll(alias => alias == host.Alias);
        preferences.Value.Forwards.RemoveAll(rule => rule.HostAlias == host.Alias);
        await SavePreferencesAsync();
        PopulateHosts();
        ShowNotice("Server deleted. Its previous config is in config_bk.", InfoBarSeverity.Success);
    }
}
