using Harbor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.ApplicationModel.DataTransfer;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private string[]? draggingHosts;
    private string? draggingSection;

    private void ConfigureHostDrag(Button button, SshHost host)
    {
        button.CanDrag = false;
        ConfigureManualSidebarDrag(button, () => { SelectContextHost(host, button.DataContext as string); return HostScope(host).ToArray(); }, null);
        button.DragStarting += (_, args) =>
        {
            SelectContextHost(host);
            draggingHosts = HostScope(host).ToArray(); draggingSection = null;
            args.Data.SetData("Harbor.Hosts", string.Join('\n', draggingHosts)); args.Data.RequestedOperation = DataPackageOperation.Move;
        };
        button.DropCompleted += (_, _) => draggingHosts = null;
    }
    private void ConfigureGroupDrag(Button button, string name)
    {
        if (name == "Ungrouped") return;
        button.CanDrag = false;
        ConfigureManualSidebarDrag(button, () => [], name);
        button.DragStarting += (_, args) =>
        {
            draggingSection = name; draggingHosts = null;
            args.Data.SetData("Harbor.Section", name); args.Data.RequestedOperation = DataPackageOperation.Move;
        };
        button.DropCompleted += (_, _) => draggingSection = null;
    }
    private void ConfigureSidebarDrop(FrameworkElement target, string group, string? beforeAlias)
    {
        target.AllowDrop = true;
        target.DragOver += (_, args) =>
        {
            if (draggingHosts is null && draggingSection is null) return;
            args.AcceptedOperation = DataPackageOperation.Move; args.Handled = true;
            args.DragUIOverride.Caption = draggingSection is not null ? "Reorder group" : group == "Favorites" ? "Pin connections" : $"Move to {group}";
        };
        target.Drop += async (_, args) =>
        {
            if (draggingHosts is null && draggingSection is null) return;
            var aliases = draggingHosts; var sourceGroup = draggingSection;
            var after = args.GetPosition(target).Y > target.ActualHeight / 2;
            args.Handled = true; args.AcceptedOperation = DataPackageOperation.Move;
            var deferral = args.GetDeferral();
            try
            {
                await RunAsync(async () =>
                {
                    var prefs = preferences.Value;
                    if (sourceGroup is not null)
                    {
                        if (sourceGroup == group) return;
                        var names = SidebarHosts.Children.OfType<HarborHostSection>().Select(section => section.HeaderButton.Tag as string).Where(name => name is not null && name != "Ungrouped").Cast<string>().ToList();
                        names.Remove(sourceGroup);
                        var index = group == "Ungrouped" ? names.Count : Math.Max(0, names.IndexOf(group) + (after ? 1 : 0));
                        names.Insert(Math.Min(index, names.Count), sourceGroup); prefs.SectionOrder = names;
                    }
                    else if (aliases is not null)
                    {
                        if (beforeAlias is not null && aliases.Contains(beforeAlias)) return;
                        foreach (var alias in aliases)
                        {
                            if (group == "Favorites") prefs.Favorites.Add(alias);
                            else if (group == "Ungrouped") prefs.HostGroups.Remove(alias);
                            else prefs.HostGroups[alias] = group;
                        }
                        var members = config.Document.Hosts.Where(host => group == "Favorites" ? prefs.Favorites.Contains(host.Alias) : prefs.HostGroups.GetValueOrDefault(host.Alias, "Ungrouped") == group).Select(host => host.Alias).ToList();
                        var order = prefs.HostOrder.GetValueOrDefault(group, []).Where(members.Contains).Concat(members).Distinct().Where(alias => !aliases.Contains(alias)).ToList();
                        var index = beforeAlias is null ? order.Count : order.IndexOf(beforeAlias);
                        if (index < 0) index = order.Count; else if (after) index++;
                        order.InsertRange(Math.Min(index, order.Count), aliases); prefs.HostOrder[group] = order;
                    }
                    await SavePreferencesAsync(); PopulateHosts();
                });
            }
            finally { deferral.Complete(); }
        };
    }
}
