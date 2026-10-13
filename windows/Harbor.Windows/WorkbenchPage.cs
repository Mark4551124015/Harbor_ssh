using Harbor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private HashSet<string> priorFeaturedHosts = [];
    private bool workbenchWasRendered;
    private void RenderWorkbench()
    {
        if (page != "workbench") return;
        PageContent.Children.Clear();
        var panel = Stack(24);
        HeaderActions.Children.Clear();
        HeaderActions.Children.Add(ActionButton("Quick connect", QuickConnectAsync, Symbol.Go, accent: true));
        var favorites = config.Document.Hosts.Where(host => preferences.Value.Favorites.Contains(host.Alias)).ToList();
        var stats = new Grid { ColumnSpacing = 10 };
        for (var i = 0; i < 3; i++) stats.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var values = new[] { config.Document.Hosts.Count, favorites.Count, processes?.Sessions.Count(session => session.Active) ?? 0 };
        var labels = new[] { "CONNECTIONS", "FAVORITES", "ACTIVE FORWARDS" };
        var colors = new[] { ThemeBrush("HarborAccentBrush"), new SolidColorBrush(Windows.UI.Color.FromArgb(255, 170, 155, 220)), new SolidColorBrush(Windows.UI.Color.FromArgb(255, 105, 189, 176)) };
        for (var i = 0; i < 3; i++)
        {
            var content = Stack(5);
            var number = Text(values[i].ToString(), 27); number.Foreground = colors[i];
            content.Children.Add(number); content.Children.Add(Muted(labels[i], 9));
            var card = Card(content);
            card.BorderBrush = colors[i]; card.BorderThickness = new Thickness(0, 0, 0, 3);
            Grid.SetColumn(card, i); stats.Children.Add(card);
        }
        panel.Children.Add(stats);
        var heading = new Grid();
        heading.Children.Add(Text(favorites.Count > 0 ? "Pinned connections" : "Your connections", 18));
        var pinned = Muted(favorites.Count > 0 ? $"{favorites.Count} PINNED" : "STAR A HOST TO PIN IT", 10);
        pinned.HorizontalAlignment = HorizontalAlignment.Right; pinned.VerticalAlignment = VerticalAlignment.Center; heading.Children.Add(pinned);
        panel.Children.Add(heading);
        var featured = favorites.Count > 0 ? favorites.Take(6) : config.Document.Hosts.Take(4);
        var cards = new HarborCardsPanel();
        var nextFeaturedHosts = new HashSet<string>();
        foreach (var host in featured)
        {
            var content = Stack(16);
            var top = new Grid { ColumnSpacing = 12 };
            top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var avatar = HostMark(host, 40);
            top.Children.Add(avatar);
            var name = ActionButton(host.Alias, () => { selectedAlias = host.Alias; ShowPage("servers"); return Task.CompletedTask; });
            name.Style = (Style)Application.Current.Resources["HarborQuietButtonStyle"];
            name.Padding = new Thickness(0); name.Foreground = ThemeBrush("HarborTextBrush");
            name.HorizontalContentAlignment = HorizontalAlignment.Stretch;
            name.Content = new TextBlock { Text = host.Alias, FontFamily = (FontFamily)Application.Current.Resources["HarborUIFont"], FontSize = 13, TextWrapping = TextWrapping.NoWrap, TextTrimming = TextTrimming.CharacterEllipsis };
            var label = Stack(4); label.Children.Add(name);
            label.Children.Add(Muted(preferences.Value.HostGroups.GetValueOrDefault(host.Alias, "Ungrouped"), 11));
            Grid.SetColumn(label, 1); top.Children.Add(label);
            var favorite = ActionButton("", async () =>
            {
                if (!preferences.Value.Favorites.Remove(host.Alias)) preferences.Value.Favorites.Add(host.Alias);
                await SavePreferencesAsync(); PopulateHosts();
            }, preferences.Value.Favorites.Contains(host.Alias) ? Symbol.SolidStar : Symbol.Favorite);
            favorite.Style = (Style)Application.Current.Resources["HarborIconButtonStyle"];
            favorite.Foreground = ThemeBrush("HarborAccentBrush");
            favorite.Width = 32; favorite.Height = 32; favorite.Padding = new Thickness(0);
            Grid.SetColumn(favorite, 2); top.Children.Add(favorite);
            content.Children.Add(top);
            var address = Muted(host.Destination, 12); address.FontFamily = new FontFamily("Consolas"); content.Children.Add(address);
            var footer = new Grid();
            footer.Children.Add(Muted($"SSH / {(host.Port.Length > 0 ? host.Port : "DEFAULT")}", 9));
            var connect = ActionButton("Connect", () => LaunchConnectionAsync(host.Alias), Symbol.Go);
            connect.Style = (Style)Application.Current.Resources["HarborQuietButtonStyle"];
            connect.Foreground = ThemeBrush("HarborAccentBrush"); connect.HorizontalAlignment = HorizontalAlignment.Right; connect.Padding = new Thickness(0);
            footer.Children.Add(connect); content.Children.Add(footer);
            var hostCard = Card(content);
            hostCard.Tapped += (_, args) =>
            {
                var source = args.OriginalSource as DependencyObject;
                while (source is not null && source != hostCard)
                {
                    if (source is Button) return;
                    source = VisualTreeHelper.GetParent(source);
                }
                args.Handled = true;
                selectedAlias = host.Alias;
                ShowPage("servers");
            };
            hostCard.ContextFlyout = ConnectionMenu(host);
            hostCard.RightTapped += (_, _) => SelectContextHost(host);
            cards.Children.Add(hostCard);
            nextFeaturedHosts.Add(host.Alias);
            if (workbenchWasRendered && !priorFeaturedHosts.Contains(host.Alias)) AnimateReveal(hostCard);
        }
        if (cards.Children.Count == 0)
        {
            var empty = Stack(12); empty.Children.Add(Text("Your workspace starts here.", 22));
            empty.Children.Add(Muted("Add a connection using the sidebar.")); panel.Children.Add(Card(empty));
        }
        else panel.Children.Add(cards);
        var activityHeading = new Grid(); activityHeading.Children.Add(Text("Local SSH activity", 18));
        var viewAll = ActionButton("View all", () => { ShowPage("activity"); return Task.CompletedTask; });
        viewAll.HorizontalAlignment = HorizontalAlignment.Right; activityHeading.Children.Add(viewAll); panel.Children.Add(activityHeading);
        var active = processes?.Sessions.Where(session => session.Active).Take(4).ToList() ?? [];
        if (active.Count == 0) panel.Children.Add(Muted("No Harbor forwarding processes running."));
        foreach (var session in active) panel.Children.Add(Card(Text($"{session.Rule.HostAlias}  ·  {session.Rule.Label}\nPID {session.ProcessId}  ·  {session.Status}")));
        panel.Children.Add(Text("Recently opened", 18));
        var recentHosts = preferences.Value.RecentHosts.Select(alias => config.Document.Hosts.FirstOrDefault(host => host.Alias == alias)).Where(host => host is not null).Take(5).ToList();
        if (recentHosts.Count == 0) panel.Children.Add(Muted("No recent connections yet. Hosts appear here after opening Terminal."));
        foreach (var host in recentHosts)
            panel.Children.Add(ActionButton(host!.Alias, () => { selectedAlias = host.Alias; ShowPage("servers"); return Task.CompletedTask; }, Symbol.Clock));
        PageContent.Children.Add(Scroll(panel));
        priorFeaturedHosts = nextFeaturedHosts; workbenchWasRendered = true;
    }

}
