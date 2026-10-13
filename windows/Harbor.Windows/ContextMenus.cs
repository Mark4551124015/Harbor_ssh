using Harbor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    internal static FontIcon HarborIcon(Symbol symbol, double size = 16) => new()
    {
        FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"),
        FontSize = size, Glyph = symbol switch
        {
            Symbol.AllApps => "\uE80F", Symbol.Clock => "\uE9D9", Symbol.Switch => "\uE8AB",
            Symbol.Permissions => "\uE8D7", Symbol.Go => "\uE8A7", Symbol.Play => "\uE768",
            Symbol.Favorite => "\uE734", Symbol.SolidStar => "\uE735",
            Symbol.Forward => "\uE76C", Symbol.More => "\uE70D",
            _ => char.ConvertFromUtf32((int)symbol)
        },
        Width = size + 4, Height = size + 4,
        VerticalAlignment = VerticalAlignment.Center,
        HorizontalAlignment = HorizontalAlignment.Center, IsHitTestVisible = false
    };

    private MenuFlyout ConnectionMenu(SshHost? host, string? group = null)
    {
        var menu = HarborMenu();
        MenuFlyoutItem Item(string title, Symbol icon, Func<Task> action, bool enabled = true)
        {
            var item = new MenuFlyoutItem { Text = title, Icon = HarborIcon(icon), IsEnabled = enabled };
            item.Click += async (_, _) => await RunAsync(action);
            menu.Items.Add(item);
            return item;
        }
        if (host is not null)
        {
            Item("Open in terminal", Symbol.Go, () => LaunchConnectionAsync(host.Alias));
            Item("Rename…", Symbol.Edit, () => RenameHostAsync(host), host.CanEdit).KeyboardAcceleratorTextOverride = "F2";
            Item("Copy SSH command", Symbol.Copy, async () =>
            {
                Copy(SshCommands.DisplayCommand("ssh.exe", await ConnectionArgumentsAsync(host.Alias)));
            });
            menu.Items.Add(new MenuFlyoutSeparator());
            Item(preferences.Value.Favorites.Contains(host.Alias) ? "Unpin connection" : "Pin connection", Symbol.Favorite, async () =>
            {
                if (!preferences.Value.Favorites.Remove(host.Alias)) preferences.Value.Favorites.Add(host.Alias);
                await SavePreferencesAsync(); PopulateHosts();
            });
            Item("Edit tags…", Symbol.Tag, () => EditTagsAsync(host));
            Item("Choose icon…", Symbol.AllApps, () => ChooseHostIconAsync(host));
            var move = new MenuFlyoutSubItem { Text = "Move to group", Icon = HarborIcon(Symbol.Folder) };
            menu.Opening += (_, _) => move.Text = HostScope(host).Count() > 1 ? $"Move {HostScope(host).Count()} connections to group" : "Move to group";
            foreach (var name in ConnectionGroups().Append("Ungrouped"))
            {
                var destination = name;
                var item = new ToggleMenuFlyoutItem { Text = name, IsChecked = preferences.Value.HostGroups.GetValueOrDefault(host.Alias, "Ungrouped") == name };
                item.Click += async (_, _) => await RunAsync(async () =>
                {
                    foreach (var alias in HostScope(host))
                    {
                        preferences.Value.HostGroups.Remove(alias);
                        if (destination != "Ungrouped") preferences.Value.HostGroups[alias] = destination;
                    }
                    await SavePreferencesAsync(); PopulateHosts();
                });
                move.Items.Add(item);
            }
            var newGroup = new MenuFlyoutItem { Text = "New group…", Icon = HarborIcon(Symbol.Add) };
            newGroup.Click += async (_, _) => await RunAsync(() => ChangeGroupAsync(null, host));
            move.Items.Add(new MenuFlyoutSeparator()); move.Items.Add(newGroup);
            menu.Items.Add(move);
            menu.Items.Add(new MenuFlyoutSeparator());
        }
        Item("New connection", Symbol.Add, () => EditHostAsync(null, group ?? (host is null ? null : preferences.Value.HostGroups.GetValueOrDefault(host.Alias)))).KeyboardAcceleratorTextOverride = "Ctrl+N";
        Item("New group…", Symbol.Folder, () => ChangeGroupAsync(null, host));
        if (group is not null && group is not "Favorites" and not "Ungrouped")
        {
            menu.Items.Add(new MenuFlyoutSeparator());
            Item("Group appearance…", Symbol.Highlight, () => GroupAppearanceAsync(group));
            Item("Rename group…", Symbol.Edit, () => ChangeGroupAsync(group, null));
            Item("Remove group…", Symbol.Delete, async () =>
            {
                var confirm = Dialog("Remove group?", Text("Connections will be moved to Ungrouped. Their SSH configuration will be preserved."), "Remove");
                confirm.DefaultButton = ContentDialogButton.Close;
                if (await confirm.ShowAsync() != ContentDialogResult.Primary) return;
                foreach (var alias in preferences.Value.HostGroups.Where(x => x.Value == group).Select(x => x.Key).ToList()) preferences.Value.HostGroups.Remove(alias);
                preferences.Value.CollapsedGroups.Remove(group);
                preferences.Value.ExplicitGroups.Remove(group);
                preferences.Value.GroupIcons.Remove(group);
                preferences.Value.GroupColors.Remove(group);
                preferences.Value.HostOrder.Remove(group);
                preferences.Value.SectionOrder.Remove(group);
                await SavePreferencesAsync(); PopulateHosts();
            });
        }
        if (host is not null)
        {
            menu.Items.Add(new MenuFlyoutSeparator());
            Item("Delete connection…", Symbol.Delete, () => DeleteHostAsync(host), host.CanEdit);
        }
        return menu;
    }

    private async Task ChangeGroupAsync(string? previous, SshHost? host)
    {
        var name = new HarborTextBox { Header = "Group name", Text = previous ?? "", MinWidth = 300 };
        var error = Muted("");
        var form = Stack(12); form.Children.Add(name); form.Children.Add(error);
        var dialog = Dialog(previous is null ? "New group" : "Rename group", form, "Save");
        dialog.PrimaryButtonClick += (_, args) =>
        {
            var value = name.Text.Trim();
            if (value.Length is 0 or > 80 || value.Any(char.IsControl) || value.Equals("Favorites", StringComparison.OrdinalIgnoreCase) || value.Equals("Ungrouped", StringComparison.OrdinalIgnoreCase))
            { args.Cancel = true; error.Text = "Enter a group name up to 80 characters. Favorites and Ungrouped are reserved."; }
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        if (previous == name.Text.Trim()) return;
        if (host is not null) preferences.Value.HostGroups[host.Alias] = name.Text.Trim();
        preferences.Value.ExplicitGroups.Add(name.Text.Trim());
        if (previous is not null)
        {
            preferences.Value.ExplicitGroups.Remove(previous);
            if (preferences.Value.HostOrder.Remove(previous, out var order)) preferences.Value.HostOrder[name.Text.Trim()] = order;
            for (var i = 0; i < preferences.Value.SectionOrder.Count; i++)
                if (preferences.Value.SectionOrder[i] == previous) preferences.Value.SectionOrder[i] = name.Text.Trim();
            if (preferences.Value.GroupIcons.Remove(previous, out var icon)) preferences.Value.GroupIcons[name.Text.Trim()] = icon;
            if (preferences.Value.GroupColors.Remove(previous, out var color)) preferences.Value.GroupColors[name.Text.Trim()] = color;
            foreach (var alias in preferences.Value.HostGroups.Where(x => x.Value == previous).Select(x => x.Key).ToList()) preferences.Value.HostGroups[alias] = name.Text.Trim();
            if (preferences.Value.CollapsedGroups.Remove(previous)) preferences.Value.CollapsedGroups.Add(name.Text.Trim());
        }
        await SavePreferencesAsync(); PopulateHosts();
    }
}
