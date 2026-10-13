using Harbor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private sealed class AdvancedDraft(string name, string value)
    {
        public string Name { get; } = name;
        public string Value { get; set; } = value;
    }
    private readonly Dictionary<string, List<AdvancedDraft>> advancedDrafts = [];
    private bool AdvancedIsDirty(SshHost host)
    {
        if (!advancedDrafts.TryGetValue(host.Alias, out var draft)) return false;
        var before = config.Document.HostOptions(host).Where(option => !PrimaryOption(option.Key)).Select(option => $"{option.Key.ToLowerInvariant()} {option.Value.Trim()}");
        var after = draft.Where(option => option.Value.Trim().Length > 0).Select(option => $"{option.Name.ToLowerInvariant()} {option.Value.Trim()}");
        return !before.SequenceEqual(after);
    }
    private IReadOnlyDictionary<string, List<string>>? AdvancedReplacements(SshHost host)
    {
        if (!advancedDrafts.TryGetValue(host.Alias, out var draft)) return null;
        var values = config.Document.HostOptions(host).Where(option => !PrimaryOption(option.Key)).Select(option => option.Key).Distinct().ToDictionary(key => key, _ => new List<string>(), StringComparer.OrdinalIgnoreCase);
        foreach (var option in draft.Where(option => option.Value.Trim().Length > 0))
        {
            if (!values.TryGetValue(option.Name, out var list)) values[option.Name] = list = [];
            list.Add(option.Value.Trim());
        }
        return values;
    }
    private void RenderAdvancedDetails(SshHost host, StackPanel body)
    {
        if (!advancedDrafts.TryGetValue(host.Alias, out var draft))
            advancedDrafts[host.Alias] = draft = config.Document.HostOptions(host).Where(option => !PrimaryOption(option.Key)).Select(option => new AdvancedDraft(AdvancedOptions.FirstOrDefault(item => item.Name.Equals(option.Key, StringComparison.OrdinalIgnoreCase))?.Name ?? option.Key, option.Value)).ToList();
        DraftSaveButton(host, body);
        var rows = Stack(12);
        var heading = new Grid { ColumnSpacing = 16 };
        var labels = Stack(6); labels.Children.Add(Text("SSH options", 18)); labels.Children.Add(Muted("Add only the options you want to customize.")); heading.Children.Add(labels);
        var add = ActionButton("Add option", async () =>
        {
            var selected = await PickAdvancedOptionAsync(draft.Select(option => option.Name).ToHashSet(StringComparer.OrdinalIgnoreCase));
            if (selected is null) return;
            draft.Add(new AdvancedDraft(selected.Name, "")); Populate(selected.Name);
        }, Symbol.Add, accent: true);
        add.HorizontalAlignment = HorizontalAlignment.Right; add.VerticalAlignment = VerticalAlignment.Center; add.IsEnabled = host.CanEdit; heading.Children.Add(add); body.Children.Add(heading);
        body.Children.Add(rows);
        void Populate(string? focus = null)
        {
            rows.Children.Clear();
            if (draft.Count == 0)
            {
                var empty = Stack(12); empty.HorizontalAlignment = HorizontalAlignment.Stretch;
                var symbol = HarborIcon(Symbol.Setting, 26); symbol.HorizontalAlignment = HorizontalAlignment.Center; empty.Children.Add(symbol);
                var title = Text("No custom options", 14); title.HorizontalAlignment = HorizontalAlignment.Center; empty.Children.Add(title);
                var description = Muted("SSH uses its existing configuration and defaults."); description.HorizontalAlignment = HorizontalAlignment.Center; empty.Children.Add(description); rows.Children.Add(Card(empty));
            }
            foreach (var option in draft)
            {
                var definition = AdvancedOptions.FirstOrDefault(item => item.Name.Equals(option.Name, StringComparison.OrdinalIgnoreCase));
                var panel = Stack(12); var top = new Grid { ColumnSpacing = 12 };
                top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }); top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                var text = Stack(5); text.Children.Add(Text(definition?.Name ?? option.Name, 13)); text.Children.Add(Muted(definition?.Description ?? "Imported SSH option. Kept as configured.", 11)); top.Children.Add(text);
                var remove = ActionButton("", () => { draft.Remove(option); Populate(); UpdateHostSaveState(); return Task.CompletedTask; });
                remove.Style = (Style)Application.Current.Resources["HarborIconButtonStyle"]; remove.Padding = new Thickness(0); remove.Content = HarborIcon(Symbol.Delete, 14); AddButtonHover(remove); remove.IsEnabled = host.CanEdit; ToolTipService.SetToolTip(remove, $"Remove {option.Name}"); Grid.SetColumn(remove, 1); top.Children.Add(remove); panel.Children.Add(top);
                var input = new HarborTextBox { Text = option.Value, PlaceholderText = definition?.Example ?? "Value", IsEnabled = host.CanEdit };
                input.TextChanged += (_, _) => { option.Value = input.Text; UpdateHostSaveState(); };
                if (focus == option.Name) input.Loaded += (_, _) => { input.StartBringIntoView(); input.Focus(FocusState.Programmatic); };
                panel.Children.Add(input); rows.Children.Add(Card(panel));
            }
        }
        Populate();
    }
    private async Task<AdvancedOption?> PickAdvancedOptionAsync(HashSet<string> excluded)
    {
        var layout = new Grid { RowSpacing = 12 };
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var search = new HarborTextBox { PlaceholderText = "Search options or descriptions…" }; layout.Children.Add(search); search.Loaded += (_, _) => search.Focus(FocusState.Programmatic);
        var rows = Stack(4); var scroll = Scroll(rows); Grid.SetRow(scroll, 1); layout.Children.Add(scroll);
        Action<AdvancedOption?>? choose = null;
        void Populate()
        {
            rows.Children.Clear(); var terms = search.Text.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            foreach (var option in AdvancedOptions.Where(option => !excluded.Contains(option.Name) && terms.All(term => $"{option.Name} {option.Description}".Contains(term, StringComparison.OrdinalIgnoreCase))))
            {
                var content = new Grid { ColumnSpacing = 12 };
                content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }); content.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                var labels = Stack(5); labels.Children.Add(Text(option.Name, 13)); labels.Children.Add(Muted(option.Description, 11)); content.Children.Add(labels);
                var plus = HarborIcon(Symbol.Add, 15); plus.Foreground = ThemeBrush("HarborAccentBrush"); Grid.SetColumn(plus, 1); content.Children.Add(plus);
                var button = ActionButton("", () => { choose?.Invoke(option); return Task.CompletedTask; }); button.Style = (Style)Application.Current.Resources["HarborQuietButtonStyle"]; button.Content = content; button.Padding = new Thickness(12); button.HorizontalAlignment = HorizontalAlignment.Stretch; button.HorizontalContentAlignment = HorizontalAlignment.Stretch; AddButtonHover(button); rows.Children.Add(button);
            }
            if (rows.Children.Count == 0) rows.Children.Add(Muted("No matching options"));
        }
        search.TextChanged += (_, _) => Populate(); Populate();
        return await ShowSheetAsync("Add SSH option", layout, "Add option", () => AdvancedOptions[0], 560, 540, bindSelection: callback => choose = callback);
    }
}
