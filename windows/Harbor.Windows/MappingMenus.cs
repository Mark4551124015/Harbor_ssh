using Harbor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.System;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private readonly HashSet<Guid> selectedMappings = [];
    private Guid? mappingAnchor;
    private TextBlock? mappingSelectionLabel;
    private Button? mappingClearButton;
    private Button? mappingStartButton;
    private Button? mappingStopButton;
    private IReadOnlyList<ForwardRule> CurrentMappingScope() => preferences.Value.Forwards.Where(rule => selectedMappings.Count > 0 ? selectedMappings.Contains(rule.Id) :
        (mappingTag == "All tags" || rule.Tags.Contains(mappingTag)) && $"{rule.HostAlias} {rule.Group} {rule.Label} {string.Join(' ', rule.Tags)}".Contains(mappingSearch, StringComparison.OrdinalIgnoreCase)).ToList();
    private void UpdateMappingCount()
    {
        if (mappingSelectionLabel is not null) mappingSelectionLabel.Text = selectedMappings.Count == 0 ? "All mappings" : $"{selectedMappings.Count} selected";
        if (mappingClearButton is not null) mappingClearButton.Visibility = selectedMappings.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        if (mappingStartButton is not null) mappingStartButton.IsEnabled = CurrentMappingScope().Any(rule => !IsMappingActive(rule));
        if (mappingStopButton is not null) mappingStopButton.IsEnabled = CurrentMappingScope().Any(IsMappingActive);
    }
    private bool IsMappingActive(ForwardRule rule) => processes?.Sessions.Any(session => session.Rule.Id == rule.Id && session.Active) == true;
    private IReadOnlyList<ForwardRule> MappingScope(ForwardRule rule) => selectedMappings.Contains(rule.Id) ? preferences.Value.Forwards.Where(value => selectedMappings.Contains(value.Id)).ToList() : [rule];
    private void SelectMapping(ForwardRule rule, IReadOnlyList<ForwardRule> visible)
    {
        if (KeyDown(VirtualKey.Shift) && mappingAnchor is Guid anchor)
        {
            var ids = visible.Select(value => value.Id).ToList(); var start = ids.IndexOf(anchor); var end = ids.IndexOf(rule.Id);
            if (start >= 0 && end >= 0)
            {
                if (!KeyDown(VirtualKey.Control)) selectedMappings.Clear();
                selectedMappings.UnionWith(ids.Skip(Math.Min(start, end)).Take(Math.Abs(end - start) + 1));
            }
        }
        else if (KeyDown(VirtualKey.Control)) { if (!selectedMappings.Remove(rule.Id)) selectedMappings.Add(rule.Id); mappingAnchor = rule.Id; }
        else { selectedMappings.Clear(); selectedMappings.Add(rule.Id); mappingAnchor = rule.Id; }
    }
    private void UpdateMappingSelection(DependencyObject root)
    {
        UpdateMappingCount();
        UpdateMappingSelectionChildren(root);
    }
    private void UpdateMappingSelectionChildren(DependencyObject root)
    {
        if (root is Border border && border.Tag is Guid id) border.BorderBrush = ThemeBrush(selectedMappings.Contains(id) ? "HarborAccentBrush" : "HarborBorderBrush");
        for (var i = 0; i < Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(root); i++) UpdateMappingSelectionChildren(Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(root, i));
    }

    private async Task ToggleMappingAsync(ForwardRule rule)
    {
        if (processes is null) throw new IOException("Install Windows OpenSSH Client and restart Harbor.");
        if (IsMappingActive(rule)) await processes.StopAsync(rule.Id);
        else await processes.StartAsync(rule);
        RenderForwards();
    }

    private async Task RunMappingsAsync(IEnumerable<ForwardRule> rules, bool start)
    {
        var failures = new List<string>();
        foreach (var rule in rules.ToArray())
        {
            try
            {
                if (start && !IsMappingActive(rule))
                {
                    if (processes is null) throw new IOException("OpenSSH Client is unavailable.");
                    await processes.StartAsync(rule);
                }
                else if (!start && processes is not null) await processes.StopAsync(rule.Id);
            }
            catch (Exception exception) { failures.Add($"{rule.HostAlias}: {exception.Message}"); }
        }
        RenderForwards();
        if (failures.Count > 0) ShowNotice(string.Join("\n", failures), InfoBarSeverity.Error);
    }

    private MenuFlyout MappingMenu(ForwardRule? rule = null, string? group = null)
    {
        var menu = HarborMenu();
        void Item(string text, Symbol icon, Func<Task> action, bool enabled = true)
        {
            var item = new MenuFlyoutItem { Text = text, Icon = HarborIcon(icon), IsEnabled = enabled };
            item.Click += async (_, _) => await RunAsync(action); menu.Items.Add(item);
        }
        if (rule is not null)
        {
            Item("Edit mapping…", Symbol.Edit, () => EditForwardAsync(rule), config.Document.Hosts.Count > 0);
            Item(IsMappingActive(rule) ? "Stop mapping" : "Start mapping", IsMappingActive(rule) ? Symbol.Stop : Symbol.Play, () => RunMappingsAsync(MappingScope(rule), !IsMappingActive(rule)));
            var toggle = (MenuFlyoutItem)menu.Items[^1];
            menu.Opening += (_, _) => toggle.Text = IsMappingActive(rule) ? (MappingScope(rule).Count > 1 ? "Stop selected" : "Stop mapping") : (MappingScope(rule).Count > 1 ? "Start selected" : "Start mapping");
            var move = new MenuFlyoutSubItem { Text = "Move to group", Icon = HarborIcon(Symbol.Folder) };
            foreach (var name in preferences.Value.MappingGroups.Concat(preferences.Value.Forwards.Select(value => value.Group)).Where(name => name.Length > 0).Distinct().OrderBy(name => name).Append(""))
            {
                var target = name;
                var item = new ToggleMenuFlyoutItem { Text = name.Length == 0 ? "Ungrouped" : name, IsChecked = rule.Group == name };
                item.Click += async (_, _) => await RunAsync(() => MoveMappingsAsync(MappingScope(rule), target)); move.Items.Add(item);
            }
            move.Items.Add(new MenuFlyoutSeparator());
            var create = new MenuFlyoutItem { Text = "New group…", Icon = HarborIcon(Symbol.Folder) };
            create.Click += async (_, _) => await RunAsync(() => MappingGroupAsync(null, MappingScope(rule))); move.Items.Add(create); menu.Items.Add(move);
            Item("Copy mapping value", Symbol.Copy, () =>
            {
                var target = rule.TargetHost.Contains(':') ? $"[{rule.TargetHost}]" : rule.TargetHost;
                Copy(rule.Kind == ForwardKind.Socks ? rule.ListenPort.ToString() : $"{rule.ListenPort}:{target}:{rule.TargetPort}"); return Task.CompletedTask;
            });
            menu.Items.Add(new MenuFlyoutSeparator());
        }
        Item("New mapping", Symbol.Add, () => EditForwardAsync(null, rule?.Group ?? group), config.Document.Hosts.Count > 0);
        Item("New group…", Symbol.Folder, () => MappingGroupAsync(null, []));
        if (rule is null && group is not null)
        {
            var members = preferences.Value.Forwards.Where(value => value.Group == group).ToArray();
            menu.Items.Add(new MenuFlyoutSeparator());
            Item("Start group", Symbol.Play, () => RunMappingsAsync(members, true), members.Any(value => !IsMappingActive(value)));
            Item("Stop group", Symbol.Stop, () => RunMappingsAsync(members, false), members.Any(IsMappingActive));
            if (group.Length > 0)
            {
                menu.Items.Add(new MenuFlyoutSeparator());
                Item("Rename group…", Symbol.Edit, () => MappingGroupAsync(group, []));
                Item("Remove group…", Symbol.Delete, async () =>
                {
                    var dialog = Dialog("Remove mapping group?", Text("The mappings will be moved to Ungrouped."), "Remove group");
                    dialog.DefaultButton = ContentDialogButton.Close;
                    if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
                    preferences.Value.MappingGroups.Remove(group); await MoveMappingsAsync(members, "");
                });
            }
        }
        if (rule is not null)
        {
            menu.Items.Add(new MenuFlyoutSeparator());
            Item("Remove mapping", Symbol.Delete, async () =>
            {
                var scope = MappingScope(rule);
                foreach (var value in scope) if (processes is not null) await processes.StopAsync(value.Id);
                preferences.Value.Forwards.RemoveAll(value => scope.Any(selected => selected.Id == value.Id));
                await SavePreferencesAsync(); selectedMappings.Clear(); RenderForwards();
            });
            var remove = (MenuFlyoutItem)menu.Items[^1];
            menu.Opening += (_, _) => remove.Text = MappingScope(rule).Count > 1 ? "Remove selected mappings" : "Remove mapping";
        }
        return menu;
    }

    private async Task MoveMappingsAsync(IEnumerable<ForwardRule> rules, string group)
    {
        var ids = rules.Select(rule => rule.Id).ToHashSet();
        preferences.Value.Forwards = preferences.Value.Forwards.Select(rule => ids.Contains(rule.Id) ? rule with { Group = group } : rule).ToList();
        if (group.Length > 0) preferences.Value.MappingGroups.Add(group);
        await SavePreferencesAsync(); RenderForwards();
    }
    private async Task MappingGroupAsync(string? previous, IReadOnlyList<ForwardRule> selection)
    {
        var name = new HarborTextBox { Header = "Group name", Text = previous ?? "", MinWidth = 300 };
        var dialog = Dialog(previous is null ? "New group" : "Edit mapping group", name, previous is null ? "Create group" : "Save group");
        dialog.PrimaryButtonClick += (_, args) => args.Cancel = name.Text.Trim().Length > 80 || name.Text.Any(char.IsControl) || (previous is null && name.Text.Trim().Length == 0);
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        var group = name.Text.Trim();
        if (previous is not null)
        {
            preferences.Value.MappingGroups.Remove(previous); collapsedMappings.Remove(previous);
            selection = preferences.Value.Forwards.Where(rule => rule.Group == previous).ToList();
        }
        if (group.Length > 0) preferences.Value.MappingGroups.Add(group);
        await MoveMappingsAsync(selection, group);
    }
}
