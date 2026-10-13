using Harbor.Core;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;
using Windows.UI.Core;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private readonly HashSet<string> selectedHosts = new(StringComparer.OrdinalIgnoreCase);
    private string? selectionAnchor;
    private AutoSuggestBox? settingsSearchBox;
    private string? sidebarFocusKey;
    private string? previousSidebarFocusKey;
    private readonly Stack<string> pageHistory = new();
    private bool navigatingBack;
    private static bool KeyDown(VirtualKey key) => (InputKeyboardSource.GetKeyStateForCurrentThread(key) & CoreVirtualKeyStates.Down) != 0;

    private void SelectHost(SshHost host, string? group = null)
    {
        sidebarFocusKey = $"{group ?? preferences.Value.HostGroups.GetValueOrDefault(host.Alias, "Ungrouped")}\0{host.Alias}";
        if (KeyDown(VirtualKey.Shift) && selectionAnchor is not null)
        {
            var aliases = SidebarHosts.Children.OfType<HarborHostSection>().SelectMany(section => section.HostButtons).Select(button => (string)button.Tag).Distinct().ToList();
            var from = aliases.IndexOf(selectionAnchor); var to = aliases.IndexOf(host.Alias);
            if (from >= 0 && to >= 0)
            {
                if (!KeyDown(VirtualKey.Control)) selectedHosts.Clear();
                foreach (var alias in aliases.Skip(Math.Min(from, to)).Take(Math.Abs(to - from) + 1)) selectedHosts.Add(alias);
            }
        }
        else if (KeyDown(VirtualKey.Control))
        {
            if (!selectedHosts.Remove(host.Alias)) selectedHosts.Add(host.Alias);
            selectionAnchor = host.Alias;
        }
        else { selectedHosts.Clear(); selectedHosts.Add(host.Alias); selectionAnchor = host.Alias; }
        selectedAlias = host.Alias; ShowPage("servers"); UpdateHostSelection();
    }

    private void SelectContextHost(SshHost host, string? group = null)
    {
        if (!selectedHosts.Contains(host.Alias)) { selectedHosts.Clear(); selectedHosts.Add(host.Alias); selectionAnchor = host.Alias; }
        selectedAlias = host.Alias; UpdateHostSelection();
        if (group is not null) { sidebarFocusKey = $"{group}\0{host.Alias}"; UpdateHostSelection(); }
    }

    private IEnumerable<string> HostScope(SshHost host) => selectedHosts.Contains(host.Alias) ? selectedHosts.ToArray() : [host.Alias];
    private void UpdateHostSelection()
    {
        foreach (var section in SidebarHosts.Children.OfType<HarborHostSection>())
        {
            var group = section.HeaderButton.Tag as string ?? "";
            var active = section.HostButtons.FirstOrDefault(button => selectedHosts.Count == 1 && sidebarFocusKey == $"{group}\0{button.Tag}");
            foreach (var button in section.HostButtons)
                button.Background = selectedHosts.Count > 1 && selectedHosts.Contains((string)button.Tag) ? ThemeBrush("HarborSelectionBrush") : new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent);
            section.SelectRow(active, ThemeBrush("HarborSelectionBrush"), MotionEnabled && previousSidebarFocusKey != sidebarFocusKey, previousSidebarFocusKey?.Split('\0')[0] == group);
        }
        previousSidebarFocusKey = sidebarFocusKey;
    }

    private void ConfigureKeyboard()
    {
        Root.KeyboardAcceleratorPlacementMode = KeyboardAcceleratorPlacementMode.Hidden;
        Root.AddHandler(UIElement.KeyDownEvent, new KeyEventHandler((_, args) =>
        {
            if (args.Key == VirtualKey.Escape && (!args.Handled || FocusedSearch() is not null)) args.Handled = HandleEscape();
        }), true);
        void Shortcut(VirtualKey key, VirtualKeyModifiers modifiers, Func<Task> action)
        {
            var accelerator = new KeyboardAccelerator { Key = key, Modifiers = modifiers };
            accelerator.Invoked += async (_, args) =>
            {
                if (key == VirtualKey.A)
                    for (var current = FocusManager.GetFocusedElement(Root.XamlRoot) as DependencyObject; current is not null; current = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(current))
                        if (current is TextBox or NumberBox or AutoSuggestBox) return;
                args.Handled = true; await RunAsync(action);
            };
            Root.KeyboardAccelerators.Add(accelerator);
        }
        Shortcut(VirtualKey.K, VirtualKeyModifiers.Control, QuickConnectAsync);
        Shortcut(VirtualKey.N, VirtualKeyModifiers.Control, () => EditHostAsync(null));
        Shortcut(VirtualKey.F, VirtualKeyModifiers.Control, () =>
        {
            if (page == "settings") settingsSearchBox?.Focus(FocusState.Programmatic); else OpenSidebarSearch();
            return Task.CompletedTask;
        });
        Shortcut((VirtualKey)188, VirtualKeyModifiers.Control, () => { ShowPage("settings"); return Task.CompletedTask; });
        Shortcut(VirtualKey.S, VirtualKeyModifiers.Control, async () => { if (page == "servers" && saveCurrentHost is not null) await saveCurrentHost(); });
        Shortcut(VirtualKey.F2, VirtualKeyModifiers.None, async () =>
        {
            if (page != "servers") return;
            var host = config.Document.Hosts.FirstOrDefault(host => host.Alias == selectedAlias);
            if (host?.CanEdit == true) await RenameHostAsync(host);
        });
        Shortcut(VirtualKey.A, VirtualKeyModifiers.Control, () =>
        {
            // Preserve native Select All while editing text.
            var focused = FocusManager.GetFocusedElement(Root.XamlRoot) as DependencyObject;
            for (var current = focused; current is not null; current = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(current))
                if (current is TextBox or NumberBox or AutoSuggestBox) return Task.CompletedTask;
            if (page == "forwards") { selectedMappings.UnionWith(preferences.Value.Forwards.Where(rule => (mappingTag == "All tags" || rule.Tags.Contains(mappingTag)) && $"{rule.HostAlias} {rule.Group} {rule.Label} {string.Join(' ', rule.Tags)}".Contains(mappingSearch, StringComparison.OrdinalIgnoreCase)).Select(rule => rule.Id)); RenderForwards(); }
            else { selectedHosts.UnionWith(config.Document.Hosts.Where(host => $"{host.Alias} {host.Subtitle}".Contains(search, StringComparison.OrdinalIgnoreCase)).Select(host => host.Alias)); UpdateHostSelection(); }
            return Task.CompletedTask;
        });
    }

    private AutoSuggestBox? FocusedSearch()
    {
        for (var current = FocusManager.GetFocusedElement(Root.XamlRoot) as DependencyObject; current is not null; current = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(current))
            if (current is AutoSuggestBox searchBox) return searchBox;
        return null;
    }

    private bool HandleEscape()
    {
        if (rowDragActive) return false; // Let the sidebar drag handler cancel first.
        if (quickConnectCompletion is not null) { quickConnectCompletion.TrySetResult(null); return true; }
        if (dismissSheet is not null) { dismissSheet(); return true; }
        AutoSuggestBox? focusedSearch = null;
        for (var current = FocusManager.GetFocusedElement(Root.XamlRoot) as DependencyObject; current is not null; current = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(current))
        {
            if (current is ContentDialog) return false;
            if (current is AutoSuggestBox searchBox) focusedSearch = searchBox;
        }
        if (focusedSearch is not null)
        {
            focusedSearch.Text = "";
            if (focusedSearch == SidebarSearch) CloseSidebarSearch();
            else NewConnectionButton.Focus(FocusState.Programmatic);
            return true;
        }
        if (sidebarSearchVisible) { CloseSidebarSearch(); return true; }
        var previous = pageHistory.Count > 0 ? pageHistory.Pop() : "workbench";
        if (page == previous) return false;
        navigatingBack = true;
        try { ShowPage(previous); }
        finally { navigatingBack = false; }
        NewConnectionButton.Focus(FocusState.Programmatic);
        return true;
    }
}
