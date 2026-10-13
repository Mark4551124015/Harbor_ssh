using Harbor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.System;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private TaskCompletionSource<string?>? quickConnectCompletion;
    private async Task QuickConnectAsync()
    {
        if (quickConnectCompletion is not null) { quickConnectCompletion.TrySetResult(null); return; }
        var completion = quickConnectCompletion = new TaskCompletionSource<string?>();
        var overlay = new Grid { Background = new SolidColorBrush(Windows.UI.Color.FromArgb(80, 0, 0, 0)) };
        Grid.SetRowSpan(overlay, Root.RowDefinitions.Count);
        var form = new Grid { RowSpacing = 12 };
        form.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); form.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        form.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) }); form.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var title = new Grid(); title.Children.Add(Text("Quick connect", 20));
        var close = ActionButton("", () => { completion.TrySetResult(null); return Task.CompletedTask; });
        close.Style = (Style)Application.Current.Resources["HarborIconButtonStyle"]; close.Padding = new Thickness(0); close.Content = HarborIcon(Symbol.Cancel, 14); close.HorizontalAlignment = HorizontalAlignment.Right; title.Children.Add(close); form.Children.Add(title);
        var search = new HarborTextBox { PlaceholderText = "Search hosts, addresses or groups…", HorizontalAlignment = HorizontalAlignment.Stretch };
        search.Loaded += (_, _) => search.Focus(FocusState.Programmatic);
        Grid.SetRow(search, 1); form.Children.Add(search);
        var rows = Stack(0); var scroll = Scroll(rows); Grid.SetRow(scroll, 2); form.Children.Add(scroll);
        var hint = Muted("↑ ↓  Navigate        Enter  Connect        Esc  Close", 10); Grid.SetRow(hint, 3); form.Children.Add(hint);
        var frame = new Border { Width = 520, Height = 430, MaxWidth = Math.Max(280, Root.ActualWidth - 48), MaxHeight = Math.Max(260, Root.ActualHeight - 48), Padding = new Thickness(20), CornerRadius = new CornerRadius(12), Background = ThemeBrush("HarborSurfaceBrush"), BorderBrush = ThemeBrush("HarborBorderBrush"), BorderThickness = new Thickness(1), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Child = form };
        overlay.Children.Add(frame);
        var matches = new List<SshHost>(); var selected = 0;
        void Paint()
        {
            rows.Children.Clear();
            if (matches.Count == 0) { rows.Children.Add(Muted("No matching hosts")); return; }
            for (var i = 0; i < matches.Count; i++)
            {
                var index = i; var host = matches[i];
                var row = new Grid { ColumnSpacing = 12, Padding = new Thickness(12, 0, 12, 0) };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(20) }); row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                var pinned = preferences.Value.Favorites.Contains(host.Alias);
                var icon = HarborIcon(pinned ? Symbol.SolidStar : Symbol.AllApps, 16); if (!pinned) icon.Glyph = "\uE7F4"; icon.Foreground = pinned ? ThemeBrush("HarborAccentBrush") : ThemeBrush("HarborMutedBrush"); row.Children.Add(icon);
                var labels = Stack(4); labels.VerticalAlignment = VerticalAlignment.Center; labels.Children.Add(Text(host.Alias, 13)); labels.Children.Add(Muted($"{host.Subtitle} · {preferences.Value.HostGroups.GetValueOrDefault(host.Alias, "Ungrouped")}", 11));
                Grid.SetColumn(labels, 1); row.Children.Add(labels);
                var button = ActionButton("", () => { completion.TrySetResult(host.Alias); return Task.CompletedTask; });
                button.Style = (Style)Application.Current.Resources["HarborQuietButtonStyle"]; button.Content = row; button.Padding = new Thickness(0); button.Height = 56; button.HorizontalAlignment = HorizontalAlignment.Stretch; button.HorizontalContentAlignment = HorizontalAlignment.Stretch;
                button.Background = i == selected ? new SolidColorBrush(Windows.UI.Color.FromArgb(38, 0, 122, 255)) : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
                rows.Children.Add(button);
            }
        }
        void Filter()
        {
            matches = config.Document.Hosts.Where(host => $"{host.Alias} {host.Subtitle} {preferences.Value.HostGroups.GetValueOrDefault(host.Alias, "")} {string.Join(' ', preferences.Value.HostTags.GetValueOrDefault(host.Alias, []))}".Contains(search.Text.Trim(), StringComparison.OrdinalIgnoreCase)).OrderByDescending(host => preferences.Value.Favorites.Contains(host.Alias)).ThenBy(host => host.Alias, StringComparer.OrdinalIgnoreCase).ToList();
            selected = 0; Paint(); scroll.ChangeView(null, 0, null, true);
        }
        search.TextChanged += (_, _) => Filter();
        overlay.AddHandler(UIElement.KeyDownEvent, new KeyEventHandler((_, args) =>
        {
            if (args.Key == VirtualKey.Escape) { completion.TrySetResult(null); args.Handled = true; }
            else if (args.Key == VirtualKey.Enter && matches.Count > 0) { completion.TrySetResult(matches[selected].Alias); args.Handled = true; }
            else if (args.Key is VirtualKey.Up or VirtualKey.Down && matches.Count > 0)
            {
                selected = (selected + (args.Key == VirtualKey.Down ? 1 : -1) + matches.Count) % matches.Count; Paint(); scroll.ChangeView(null, Math.Clamp(selected * 56, 0, scroll.ScrollableHeight), null, true); args.Handled = true;
            }
        }), true);
        overlay.Tapped += (_, args) => { if (ReferenceEquals(args.OriginalSource, overlay)) completion.TrySetResult(null); };
        Root.Children.Add(overlay); Filter();
        try
        {
            search.Focus(FocusState.Programmatic);
            AnimateReveal(frame, 320, true);
            var alias = await completion.Task;
            if (MotionEnabled)
            {
                var exit = new Microsoft.UI.Xaml.Media.Animation.Storyboard();
                var fade = new Microsoft.UI.Xaml.Media.Animation.DoubleAnimation { From = 1, To = 0, Duration = TimeSpan.FromMilliseconds(200) };
                Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTarget(fade, overlay); Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTargetProperty(fade, "Opacity"); exit.Children.Add(fade);
                if (frame.RenderTransform is ScaleTransform scale)
                    foreach (var axis in new[] { "ScaleX", "ScaleY" })
                    {
                        var shrink = new Microsoft.UI.Xaml.Media.Animation.DoubleAnimation { From = 1, To = 1.04, Duration = TimeSpan.FromMilliseconds(200), EnableDependentAnimation = true };
                        Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTarget(shrink, scale); Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTargetProperty(shrink, axis); exit.Children.Add(shrink);
                    }
                overlay.IsHitTestVisible = false; exit.Begin(); await Task.Delay(210);
            }
            Root.Children.Remove(overlay);
            if (alias is not null) await LaunchConnectionAsync(alias);
        }
        finally { Root.Children.Remove(overlay); quickConnectCompletion = null; SidebarSearch.Focus(FocusState.Programmatic); }
    }
}
