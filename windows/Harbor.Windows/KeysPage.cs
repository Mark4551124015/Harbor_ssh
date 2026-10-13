using System.Text.RegularExpressions;
using Harbor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private async Task RenderKeysAsync()
    {
        if (page != "keys") return;
        PageContent.Children.Clear();
        var panel = Stack(16);
        var toolbar = new WrapPanel();
        toolbar.Children.Add(ActionButton("Generate key", GenerateKeyAsync, Symbol.Add, accent: true));
        HeaderActions.Children.Clear(); HeaderActions.Children.Add(toolbar);
        panel.Children.Add(Muted("Private keys stay in your SSH folder. Harbor only reads public key files. To import an existing key, copy it into this folder and refresh."));
        var libraryHeading = new Grid();
        libraryHeading.Children.Add(Muted("Manage keys used by your SSH connections."));
        var refresh = ActionButton("Refresh", RenderKeysAsync);
        refresh.HorizontalAlignment = HorizontalAlignment.Right;
        libraryHeading.Children.Add(refresh); panel.Children.Add(libraryHeading);
        var container = Scroll(panel);
        PageContent.Children.Add(container);
        var keys = await KeyCatalog.ReadAsync(sshDirectory, WindowsIntegration.FindOpenSsh("ssh-keygen.exe"));
        if (page != "keys" || !PageContent.Children.Contains(container)) return;
        if (keys.Count == 0)
        {
            var empty = Stack();
            empty.Children.Add(Text("Your next connection starts with a key", 24));
            empty.Children.Add(Muted("Generate an Ed25519 or RSA 4096 key in your terminal, where you can enter a passphrase privately."));
            panel.Children.Add(Card(empty));
        }
        foreach (var key in keys)
        {
            var info = Stack(10);
            info.Children.Add(Text(key.Name, 18));
            info.Children.Add(Text(key.Fingerprint));
            info.Children.Add(Muted(key.Path));
            var copy = ActionButton("Copy public key", () => { Copy(key.PublicKey); ShowNotice("Public key copied.", InfoBarSeverity.Success); return Task.CompletedTask; }, Symbol.Copy);
            copy.IsEnabled = key.PublicKey.Length > 0;
            var row = new Grid { ColumnSpacing = 16 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.Children.Add(info); copy.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(copy, 1); row.Children.Add(copy);
            panel.Children.Add(Card(row));
        }
    }

    private async Task GenerateKeyAsync()
    {
        var form = Stack();
        var algorithm = new ComboBox { Header = "Algorithm", ItemsSource = new[] { "Ed25519", "RSA 4096" }, SelectedIndex = 0, MinWidth = 360, HorizontalAlignment = HorizontalAlignment.Stretch };
        var name = new HarborTextBox { Header = "File name", Text = "id_ed25519_harbor" };
        var comment = new HarborTextBox { Header = "Comment (optional)", Text = "Harbor Windows" };
        form.Children.Add(algorithm);
        form.Children.Add(name);
        form.Children.Add(comment);
        form.Children.Add(Muted("A terminal will ask for a passphrase. Return here and refresh when generation finishes."));
        var error = Text("");
        error.Style = (Style)Application.Current.Resources["HarborErrorTextStyle"];
        form.Children.Add(error);
        var dialog = Dialog("Generate SSH key", form, "Open terminal");
        dialog.PrimaryButtonClick += (_, args) =>
        {
            try
            {
                var fileName = name.Text.Trim();
                if (!Regex.IsMatch(fileName, @"\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z") || fileName.EndsWith('.') || fileName.EndsWith(".pub", StringComparison.OrdinalIgnoreCase))
                    throw new ArgumentException("Enter a simple key file name without a path or .pub suffix.");
                if (comment.Text.Any(char.IsControl)) throw new ArgumentException("The comment cannot contain control characters.");
                var path = Path.Combine(sshDirectory, fileName);
                if (File.Exists(path) || File.Exists(path + ".pub")) throw new IOException("A key with this name already exists. Choose another name.");
                Directory.CreateDirectory(sshDirectory);
                var arguments = new List<string> { "-t", algorithm.SelectedIndex == 0 ? "ed25519" : "rsa" };
                if (algorithm.SelectedIndex == 1) arguments.AddRange(["-b", "4096"]);
                arguments.AddRange(["-f", path, "-C", comment.Text]);
                WindowsIntegration.LaunchTerminal(WindowsIntegration.FindOpenSsh("ssh-keygen.exe"), arguments, preferences.Value.PreferWindowsTerminal);
            }
            catch (Exception exception) { args.Cancel = true; error.Text = exception.Message; }
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            ShowNotice("Finish key generation in your terminal, then refresh this page.");
    }
}
