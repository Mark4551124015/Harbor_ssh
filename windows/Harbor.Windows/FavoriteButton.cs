using Harbor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private Button FavoriteButton(SshHost host, double size = 16)
    {
        var pinned = preferences.Value.Favorites.Contains(host.Alias);
        var button = ActionButton("", async () =>
        {
            if (!preferences.Value.Favorites.Remove(host.Alias)) preferences.Value.Favorites.Add(host.Alias);
            await SavePreferencesAsync(); PopulateHosts();
        });
        button.Style = (Style)Application.Current.Resources["HarborIconButtonStyle"];
        button.Content = HarborIcon(pinned ? Symbol.SolidStar : Symbol.Favorite, size);
        button.Foreground = ThemeBrush(pinned ? "HarborAccentBrush" : "HarborMutedBrush");
        button.Width = 30; button.Height = 30; button.Padding = new Thickness(0);
        button.VerticalAlignment = VerticalAlignment.Center;
        button.Tapped += (_, args) => args.Handled = true;
        ToolTipService.SetToolTip(button, pinned ? "Unpin connection" : "Pin connection");
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(button, pinned ? "Unpin connection" : "Pin connection");
        return button;
    }
}
