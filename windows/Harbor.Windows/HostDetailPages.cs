using Harbor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private string? detailAlias;
    private string detailTab = "Overview";
    private Func<Task>? saveCurrentHost;
    private readonly Dictionary<string, HostDraft> hostDrafts = [];
    private Button? hostSaveButton;
    private void UpdateHostSaveState()
    {
        if (hostSaveButton is null) return;
        var host = config.Document.Hosts.FirstOrDefault(value => value.Alias == selectedAlias);
        var dirty = host is not null && (AdvancedIsDirty(host) || hostDrafts.TryGetValue(host.Alias, out var draft) && draft != new HostDraft(host.Alias, host.HostName, host.User, host.Port, host.IdentityFile, host.ProxyJump));
        hostSaveButton.IsEnabled = host?.CanEdit == true && dirty;
        var content = Row(8); content.Children.Add(HarborIcon(dirty ? Symbol.Edit : Symbol.Accept));
        content.Children.Add(new TextBlock { Text = dirty ? "Save" : "Saved", FontFamily = (FontFamily)Application.Current.Resources["HarborUIFont"], FontSize = 12, VerticalAlignment = VerticalAlignment.Center });
        hostSaveButton.Content = content;
    }

    private TextBox DetailField(StackPanel panel, string label, string value, Action<string> changed, bool enabled)
    {
        var field = new HarborTextBox { Header = label, Text = value, IsEnabled = enabled, HorizontalAlignment = HorizontalAlignment.Stretch };
        field.TextChanged += (_, _) => { changed(field.Text); UpdateHostSaveState(); }; panel.Children.Add(field); return field;
    }
    private void DraftSaveButton(SshHost host, StackPanel form)
    {
        saveCurrentHost = async () =>
        {
            var draft = hostDrafts.GetValueOrDefault(host.Alias) ?? new HostDraft(host.Alias, host.HostName, host.User, host.Port, host.IdentityFile, host.ProxyJump);
            if (draft.Alias != host.Alias)
            {
                if (processes?.Sessions.Any(session => session.Active && session.Rule.HostAlias == host.Alias) == true) throw new InvalidOperationException("Stop this connection's mappings before renaming it.");
            }
            await config.SaveHostAndOptionsAsync(draft, host, AdvancedReplacements(host));
            if (draft.Alias != host.Alias)
            {
                MigrateHostMetadata(host.Alias, draft.Alias);
                if (preferences.Value.HostGroups.Remove(host.Alias, out var group)) preferences.Value.HostGroups[draft.Alias] = group;
                if (preferences.Value.Favorites.Remove(host.Alias)) preferences.Value.Favorites.Add(draft.Alias);
                preferences.Value.Forwards = preferences.Value.Forwards.Select(rule => rule.HostAlias == host.Alias ? rule with { HostAlias = draft.Alias } : rule).ToList();
                await SavePreferencesAsync();
            }
            advancedDrafts.Remove(host.Alias); hostDrafts.Remove(host.Alias); selectedAlias = draft.Alias; PopulateHosts(); ShowNotice("SSH configuration saved.", InfoBarSeverity.Success);
        };
    }
    private HostDraft DraftFor(SshHost host)
    {
        if (!hostDrafts.TryGetValue(host.Alias, out var draft)) hostDrafts[host.Alias] = draft = new HostDraft(host.Alias, host.HostName, host.User, host.Port, host.IdentityFile, host.ProxyJump);
        return draft;
    }
    private void RenderGeneralDetails(SshHost host, StackPanel body)
    {
        var metadata = Stack(16);
        metadata.Children.Add(SettingRow("Group", preferences.Value.HostGroups.GetValueOrDefault(host.Alias, "Ungrouped"), ActionButton("Change group…", () => ChangeHostGroupAsync(host))));
        metadata.Children.Add(SettingRow("Tags", string.Join("  ", preferences.Value.HostTags.GetValueOrDefault(host.Alias, []).Select(tag => $"#{tag}")), ActionButton("Edit tags…", () => EditTagsAsync(host))));
        var iconRow = Row(12);
        iconRow.Children.Add(HostMark(host, 36));
        iconRow.Children.Add(ActionButton("Choose icon", () => ChooseHostIconAsync(host)));
        metadata.Children.Add(iconRow); body.Children.Add(Card(metadata));
        var form = Stack(18); var draft = DraftFor(host);
        DetailField(form, "Host Alias (Display Name)", draft.Alias, value => hostDrafts[host.Alias] = DraftFor(host) with { Alias = value.Trim() }, host.CanEdit);
        DetailField(form, "HostName (IP Address or Domain)", draft.HostName, value => hostDrafts[host.Alias] = DraftFor(host) with { HostName = value.Trim() }, host.CanEdit);
        DraftSaveButton(host, form); body.Children.Add(Card(form));
    }
    private void RenderConnectionDetails(SshHost host, StackPanel body)
    {
        var form = Stack(18); var draft = DraftFor(host);
        DetailField(form, "Username", draft.User, value => hostDrafts[host.Alias] = DraftFor(host) with { User = value.Trim() }, host.CanEdit);
        DetailField(form, "Port", draft.Port, value => hostDrafts[host.Alias] = DraftFor(host) with { Port = value.Trim() }, host.CanEdit);
        var keyRow = new Grid { ColumnSpacing = 8 };
        keyRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }); keyRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var keyField = new HarborTextBox { Text = draft.IdentityFile, IsReadOnly = true, PlaceholderText = "Default (~/.ssh/id_rsa)", VerticalAlignment = VerticalAlignment.Center };
        keyRow.Children.Add(keyField);
        var keyActions = new WrapPanel { VerticalAlignment = VerticalAlignment.Center };
        keyActions.Children.Add(ActionButton("Select…", () => SelectIdentityAsync(host), Symbol.OpenFile));
        keyActions.Children.Add(ActionButton("Create New", GenerateKeyAsync)); Grid.SetColumn(keyActions, 1); keyRow.Children.Add(keyActions);
        form.Children.Add(Muted("Identity file")); form.Children.Add(keyRow);
        DetailField(form, "Jump host (ProxyJump)", draft.ProxyJump, value => hostDrafts[host.Alias] = DraftFor(host) with { ProxyJump = value.Trim() }, host.CanEdit);
        DraftSaveButton(host, form); body.Children.Add(Card(form)); body.Children.Add(ConnectionProxySettings(host));
    }
    private async Task SelectIdentityAsync(SshHost host)
    {
        var picker = new Windows.Storage.Pickers.FileOpenPicker();
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
        picker.FileTypeFilter.Add("*");
        var file = await picker.PickSingleFileAsync();
        if (file is null) return;
        hostDrafts[host.Alias] = DraftFor(host) with { IdentityFile = file.Path };
        RenderServers();
    }
    private static bool PrimaryOption(string key) => key is "hostname" or "user" or "port" or "identityfile" or "proxyjump" or "localforward" or "remoteforward" or "dynamicforward" or "include";
    private void RenderConfigMappings(SshHost host, StackPanel body)
    {
        var form = Stack(16); form.Children.Add(Text("Port mapping", 18));
        form.Children.Add(Muted("These rules start with your SSH connection. Changes apply to the next connection."));
        form.Children.Add(ActionButton("Add mapping", () => EditConfigMappingAsync(host, null), Symbol.Add));
        foreach (var option in config.Document.HostOptions(host).Where(option => option.Key is "localforward" or "remoteforward" or "dynamicforward"))
        {
            var row = Stack(8); row.Children.Add(Text($"{option.Key} · {option.Value}"));
            var actions = new WrapPanel();
            actions.Children.Add(ActionButton("Edit…", () => EditConfigMappingAsync(host, option), Symbol.Edit));
            actions.Children.Add(ActionButton("Remove", async () =>
            {
                var values = config.Document.HostOptions(host).Where(value => value.Key == option.Key).Select(value => value.Value).ToList(); values.Remove(option.Value);
                await config.SaveOptionsAsync(host, new Dictionary<string, List<string>> { [option.Key] = values }); PopulateHosts();
            }, Symbol.Delete)); row.Children.Add(actions); form.Children.Add(Card(row));
        }
        body.Children.Add(Card(form));
    }
    private async Task EditConfigMappingAsync(SshHost host, (string Key, string Value)? original)
    {
        var form = Stack();
        var type = new ComboBox { Header = "Type", ItemsSource = new[] { "localforward", "remoteforward", "dynamicforward" }, SelectedItem = original?.Key ?? "localforward", MinWidth = 320 };
        var input = new HarborTextBox { Header = "OpenSSH mapping value", Text = original?.Value ?? "", PlaceholderText = "8080 localhost:80" };
        form.Children.Add(type); form.Children.Add(input); form.Children.Add(Muted("Local / Remote: listen-address:port destination:port. SOCKS: listen-address:port."));
        var error = Muted(""); form.Children.Add(error);
        var dialog = Dialog(original is null ? "Add mapping" : "Edit mapping", form, "Save mapping");
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            var deferral = args.GetDeferral();
            try
            {
                if (input.Text.Trim().Length == 0) throw new ArgumentException("Enter a mapping value.");
                var key = (string)type.SelectedItem;
                var replacements = new Dictionary<string, List<string>>();
                if (original is { } old) { var values = config.Document.HostOptions(host).Where(value => value.Key == old.Key).Select(value => value.Value).ToList(); values.Remove(old.Value); replacements[old.Key] = values; }
                if (!replacements.TryGetValue(key, out var next)) replacements[key] = next = config.Document.HostOptions(host).Where(value => value.Key == key).Select(value => value.Value).ToList();
                next.Add(input.Text.Trim()); await config.SaveOptionsAsync(host, replacements);
            }
            catch (Exception exception) { args.Cancel = true; error.Text = exception.Message; }
            finally { deferral.Complete(); }
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary) PopulateHosts();
    }
}
