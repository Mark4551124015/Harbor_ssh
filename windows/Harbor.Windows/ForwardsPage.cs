using Harbor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private string mappingSearch = "";
    private string mappingTag = "All tags";
    private readonly HashSet<string> collapsedMappings = [];
    private void RenderForwards()
    {
        if (page != "forwards") return;
        PageContent.Children.Clear();
        HeaderActions.Children.Clear();
        HeaderActions.Children.Add(ActionButton("New mapping", AddForwardAsync, Symbol.Add, accent: true));
        var panel = Stack(16);
        panel.ContextFlyout = MappingMenu();
        var selectionActions = new WrapPanel { VerticalAlignment = VerticalAlignment.Center };
        var stop = ActionButton("Stop", () => RunMappingsAsync(CurrentMappingScope(), false), Symbol.Stop); mappingStopButton = stop;
        var start = ActionButton("Start", () => RunMappingsAsync(CurrentMappingScope(), true), Symbol.Play); mappingStartButton = start;
        selectionActions.Children.Add(stop); selectionActions.Children.Add(start);
        var selectionCount = Muted(selectedMappings.Count == 0 ? "All mappings" : $"{selectedMappings.Count} selected");
        selectionCount.VerticalAlignment = VerticalAlignment.Center; selectionCount.Margin = new Thickness(4, 0, 4, 0);
        selectionActions.Children.Add(selectionCount);
        mappingSelectionLabel = selectionCount;
        mappingClearButton = ActionButton("Clear selection", () => { selectedMappings.Clear(); RenderForwards(); return Task.CompletedTask; });
        selectionActions.Children.Add(mappingClearButton);
        panel.Children.Add(selectionActions);
        var searchBox = new AutoSuggestBox { PlaceholderText = "Find a mapping…", Text = mappingSearch, QueryIcon = HarborIcon(Symbol.Find) };
        var tagPicker = new ComboBox { ItemsSource = new[] { "All tags" }.Concat(preferences.Value.Forwards.SelectMany(rule => rule.Tags).Distinct().OrderBy(tag => tag)).ToArray(), SelectedItem = mappingTag, MinWidth = 150 };
        var filters = new Grid { ColumnSpacing = 12 };
        filters.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        filters.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        filters.Children.Add(searchBox); Grid.SetColumn(tagPicker, 1); filters.Children.Add(tagPicker); panel.Children.Add(filters);
        var groupsPanel = Stack(16); panel.Children.Add(groupsPanel);
        void PopulateMappings()
        {
            groupsPanel.Children.Clear();
            var rules = preferences.Value.Forwards.Where(rule => (mappingTag == "All tags" || rule.Tags.Contains(mappingTag)) && $"{rule.HostAlias} {rule.Group} {rule.Label} {string.Join(' ', rule.Tags)}".Contains(mappingSearch, StringComparison.OrdinalIgnoreCase)).ToList();
            selectedMappings.RemoveWhere(id => preferences.Value.Forwards.All(rule => rule.Id != id));
            var groups = rules.Select(rule => rule.Group).Concat(mappingSearch.Length == 0 && mappingTag == "All tags" ? preferences.Value.MappingGroups : []).Distinct().OrderBy(group => group.Length == 0 ? 1 : 0).ThenBy(group => group);
            foreach (var group in groups)
            {
                var rows = Stack(10);
                var members = rules.Where(rule => rule.Group == group).ToList();
                foreach (var rule in members)
                {
                    var card = new Grid { ColumnSpacing = 12 };
                    card.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(36) });
                    card.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                    card.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                    var mark = HarborIcon(rule.Kind == ForwardKind.Socks ? Symbol.World : Symbol.Switch, 17);
                    mark.Foreground = GroupBrush("Development");
                    card.Children.Add(new Border { Width = 36, Height = 36, CornerRadius = new CornerRadius(9), Background = ThemeBrush("HarborSelectionBrush"), Child = mark });
                    var details = Stack(5);
                    var title = Text($"{rule.HostAlias} · {(rule.Kind == ForwardKind.Socks ? "SOCKS5 proxy" : rule.Kind == ForwardKind.Remote ? "Remote forward" : "Local forward")}", 12);
                    title.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold; details.Children.Add(title);
                    details.Children.Add(Muted(rule.Label, 11));
                    if (rule.Tags.Count > 0) details.Children.Add(Muted(string.Join("  ", rule.Tags.Select(tag => $"#{tag}")), 11));
                    var session = processes?.Sessions.FirstOrDefault(session => session.Rule.Id == rule.Id);
                    details.Children.Add(Muted(IsMappingActive(rule) ? "Running" : "Stopped", 10));
                    if (session is not null && session.Error.Length > 0) details.Children.Add(Muted(session.Error));
                    Grid.SetColumn(details, 1); card.Children.Add(details);
                    var actions = Row(6); actions.VerticalAlignment = VerticalAlignment.Center;
                    var toggle = ActionButton(IsMappingActive(rule) ? "Stop" : "Start", () => ToggleMappingAsync(rule), IsMappingActive(rule) ? Symbol.Stop : Symbol.Play);
                    toggle.Width = 120; actions.Children.Add(toggle);
                    var edit = ActionButton("", () => EditForwardAsync(rule));
                    edit.Style = (Style)Application.Current.Resources["HarborIconButtonStyle"]; edit.Padding = new Thickness(0); edit.Content = HarborIcon(Symbol.Edit, 15);
                    ToolTipService.SetToolTip(edit, "Edit mapping"); actions.Children.Add(edit);
                    var remove = ActionButton("", async () =>
                    {
                        if (processes is not null) await processes.StopAsync(rule.Id);
                        preferences.Value.Forwards.RemoveAll(value => value.Id == rule.Id);
                        await SavePreferencesAsync(); RenderForwards();
                    });
                    remove.Style = (Style)Application.Current.Resources["HarborIconButtonStyle"]; remove.Padding = new Thickness(0); remove.Content = HarborIcon(Symbol.Delete, 15);
                    ToolTipService.SetToolTip(remove, "Remove mapping"); actions.Children.Add(remove);
                    Grid.SetColumn(actions, 2); card.Children.Add(actions);
                    var container = Card(card); container.Tag = rule.Id; container.ContextFlyout = MappingMenu(rule);
                    if (selectedMappings.Contains(rule.Id)) container.BorderBrush = ThemeBrush("HarborAccentBrush");
                    container.RightTapped += (_, _) => { if (!selectedMappings.Contains(rule.Id)) { selectedMappings.Clear(); selectedMappings.Add(rule.Id); } UpdateMappingSelection(groupsPanel); };
                    container.Tapped += (_, args) =>
                    {
                        var source = args.OriginalSource as DependencyObject;
                        while (source is not null && source != container) { if (source is Button) return; source = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(source); }
                        SelectMapping(rule, rules); UpdateMappingSelection(groupsPanel); args.Handled = true;
                    };
                    rows.Children.Add(container);
                }
                var section = new HarborHostSection(group.Length == 0 ? "Ungrouped" : group, members.Count, rows, collapsedMappings.Contains(group), () => MotionEnabled);
                section.HeaderButton.ContextFlyout = MappingMenu(null, group);
                section.Toggled += value => { if (value) collapsedMappings.Add(group); else collapsedMappings.Remove(group); };
                groupsPanel.Children.Add(section);
            }
            if (groupsPanel.Children.Count == 0) groupsPanel.Children.Add(Card(Muted("No mappings. Create a secure route with New mapping.")));
            UpdateMappingCount();
        }
        searchBox.TextChanged += (_, _) => { mappingSearch = searchBox.Text; PopulateMappings(); };
        tagPicker.SelectionChanged += (_, _) => { mappingTag = tagPicker.SelectedItem as string ?? "All tags"; PopulateMappings(); };
        PopulateMappings(); PageContent.Children.Add(Scroll(panel));
    }
    private Task AddForwardAsync() => EditForwardAsync(null);

    private async Task EditForwardAsync(ForwardRule? original, string? initialGroup = null)
    {
        var resume = original is not null && IsMappingActive(original);
        ForwardRule? saved = null;
        var hosts = config.Document.Hosts.Select(host => host.Alias).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        if (hosts.Count == 0) throw new InvalidOperationException("Add a server before creating a port forward.");
        var form = Stack();
        var host = new ComboBox { Header = "Server", ItemsSource = hosts, SelectedIndex = 0, HorizontalAlignment = HorizontalAlignment.Stretch, MinWidth = 360 };
        if (original is not null) host.SelectedItem = original.HostAlias;
        var kind = new ComboBox { Header = "Forward type", ItemsSource = Enum.GetValues<ForwardKind>(), SelectedItem = original?.Kind ?? ForwardKind.Local, HorizontalAlignment = HorizontalAlignment.Stretch };
        var listen = new HarborTextBox { Header = "Listen port (loopback only)", Text = original?.ListenPort.ToString() ?? "", PlaceholderText = "8080" };
        var target = new HarborTextBox { Header = "Destination host", Text = original?.TargetHost ?? "127.0.0.1", IsEnabled = original?.Kind != ForwardKind.Socks };
        var targetPort = new HarborTextBox { Header = "Destination port", Text = original?.TargetPort.ToString() ?? "", PlaceholderText = "80", IsEnabled = original?.Kind != ForwardKind.Socks };
        var group = new HarborTextBox { Header = "Group", Text = original?.Group ?? initialGroup ?? "", PlaceholderText = "Ungrouped" };
        var tags = new HarborTextBox { Header = "Tags", Text = string.Join(", ", original?.Tags ?? []), PlaceholderText = "work, database" };
        var hint = Muted("Local: connect from this PC to a service reached by the server.");
        kind.SelectionChanged += (_, _) =>
        {
            var selected = (ForwardKind)kind.SelectedItem;
            target.IsEnabled = targetPort.IsEnabled = selected != ForwardKind.Socks;
            hint.Text = selected switch
            {
                ForwardKind.Local => "Local: connect from this PC to a service reached by the server.",
                ForwardKind.Remote => "Remote: listen on the server's loopback and reach a service from this PC.",
                _ => "SOCKS: listen on this PC's loopback. Configure your client to use SOCKS5."
            };
        };
        foreach (var input in new UIElement[] { host, kind, listen, target, targetPort, group, tags, hint }) form.Children.Add(input);
        var error = Text("");
        error.Style = (Style)Application.Current.Resources["HarborErrorTextStyle"];
        form.Children.Add(error);
        var dialogScroll = new ScrollViewer { Content = form, MaxHeight = 520, HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden };
        var dialog = Dialog(original is null ? "New mapping" : "Edit mapping", dialogScroll, original is null ? "Add mapping" : "Save mapping");
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            var deferral = args.GetDeferral();
            ForwardRule? rule = null;
            try
            {
                if (!int.TryParse(listen.Text, out var listenNumber)) throw new ArgumentException("Enter a valid listen port.");
                var selected = (ForwardKind)kind.SelectedItem;
                var targetNumber = 0;
                if (selected != ForwardKind.Socks && !int.TryParse(targetPort.Text, out targetNumber))
                    throw new ArgumentException("Enter a valid destination port.");
                if (host.SelectedItem is not string alias) throw new ArgumentException("Select an existing connection.");
                rule = new ForwardRule(original?.Id ?? Guid.NewGuid(), alias, selected, listenNumber, target.Text.Trim(), targetNumber) { Group = group.Text.Trim(), Tags = NormalizeTags(tags.Text).ToList() };
                rule.Validate();
                if (original is not null) preferences.Value.Forwards.Remove(original);
                preferences.Value.Forwards.Add(rule);
                await SavePreferencesAsync();
                saved = rule;
            }
            catch (Exception exception)
            {
                if (rule is not null) preferences.Value.Forwards.Remove(rule);
                if (original is not null && !preferences.Value.Forwards.Contains(original)) preferences.Value.Forwards.Add(original);
                args.Cancel = true;
                error.Text = exception.Message;
            }
            finally { deferral.Complete(); }
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            RenderForwards();
            if (resume && saved is not null && processes is not null) { await processes.StopAsync(saved.Id); await processes.StartAsync(saved); }
        }
    }

    private void RenderActivity()
    {
        if (page != "activity") return;
        PageContent.Children.Clear();
        var panel = Stack(16);
        var toolbar = new WrapPanel();
        toolbar.Children.Add(ActionButton("Refresh", () => { RenderActivity(); return Task.CompletedTask; }, Symbol.Refresh));
        toolbar.Children.Add(ActionButton("Stop all forwards", async () =>
        {
            var dialog = Dialog("Stop all port forwards?", Text("Connections through these forwards will close."), "Stop all");
            dialog.DefaultButton = ContentDialogButton.Close;
            if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
            foreach (var session in processes?.Sessions ?? []) processes?.Stop(session.Rule.Id);
        }, Symbol.Stop));
        HeaderActions.Children.Clear(); HeaderActions.Children.Add(toolbar);
        var sessions = processes?.Sessions ?? [];
        if (sessions.Count == 0)
        {
            var empty = Stack();
            empty.Children.Add(Text("No forwarding activity yet", 24));
            empty.Children.Add(Muted("Start a port forward to see its process, start time and diagnostics here. Terminal connections are managed by your terminal."));
            panel.Children.Add(Card(empty));
        }
        foreach (var session in sessions)
        {
            var info = Stack(8);
            info.Children.Add(Text(session.Rule.HostAlias, 18));
            info.Children.Add(Text(session.Rule.Label));
            info.Children.Add(Muted($"PID {session.ProcessId} · Started {session.StartedAt.LocalDateTime:g} · {session.Status}"));
            if (session.Error.Length > 0) info.Children.Add(Muted(session.Error));
            if (session.Active) info.Children.Add(ActionButton("Stop process", () => { processes?.Stop(session.Rule.Id); return Task.CompletedTask; }, Symbol.Stop));
            panel.Children.Add(Card(info));
        }
        PageContent.Children.Add(Scroll(panel));
    }
}
