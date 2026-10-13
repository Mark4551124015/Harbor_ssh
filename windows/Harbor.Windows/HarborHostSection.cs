using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.Foundation;

namespace Harbor.Desktop;

internal sealed class HarborHostSection : StackPanel
{
    public event Action<bool>? Toggled;
    private bool collapsed;
    private Storyboard? animation;
    private readonly Grid body;
    private readonly StackPanel rows;
    private readonly Func<bool> motion;
    private readonly FontIcon chevron;
    internal Button HeaderButton { get; }
    private readonly FontIcon groupIcon;
    private readonly bool plainGroup;
    private readonly Border countBadge;
    private readonly TextBlock countLabel;
    private readonly Border rowHighlight = new() { IsHitTestVisible = false, CornerRadius = new CornerRadius(7), VerticalAlignment = VerticalAlignment.Top, Visibility = Visibility.Collapsed };
    private readonly TranslateTransform rowOffset = new();
    private Storyboard? rowMotion;
    private Button? selectedRow;
    internal void SelectRow(Button? button, Brush brush, bool animate, bool slide)
    {
        if (ReferenceEquals(selectedRow, button) && button is not null && !animate && rowMotion is not null) return;
        var from = rowOffset.Y;
        selectedRow = button; rowMotion?.Stop(); rowOffset.Y = from;
        if (button is null || button.ActualHeight <= 0) { rowHighlight.Visibility = Visibility.Collapsed; return; }
        var y = button.TransformToVisual(body).TransformPoint(new Point()).Y;
        rowHighlight.Background = brush; rowHighlight.Height = button.ActualHeight; rowHighlight.Visibility = Visibility.Visible;
        rowHighlight.Opacity = 1;
        if (!animate) { rowOffset.Y = y; return; }
        rowMotion = new Storyboard();
        var change = new DoubleAnimation { From = slide ? from : 0, To = slide ? y : 1, Duration = TimeSpan.FromMilliseconds(slide ? 280 : 190), EnableDependentAnimation = true, EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } };
        if (!slide) rowOffset.Y = y;
        Storyboard.SetTarget(change, slide ? rowOffset : rowHighlight); Storyboard.SetTargetProperty(change, slide ? "Y" : "Opacity"); rowMotion.Children.Add(change);
        var current = rowMotion;
        current.Completed += (_, _) => { if (rowMotion != current) return; current.Stop(); rowOffset.Y = y; rowHighlight.Opacity = 1; rowMotion = null; };
        rowMotion.Begin();
    }
    internal IEnumerable<Button> HostButtons => rows.Children.OfType<Button>();
    internal void SetAppearance(string? glyph, Brush color)
    {
        if (glyph is not null) groupIcon.Glyph = glyph;
        groupIcon.Foreground = color;
        if (plainGroup)
            HeaderButton.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        else if (color is SolidColorBrush solid)
            HeaderButton.Background = new SolidColorBrush(Windows.UI.Color.FromArgb(24, solid.Color.R, solid.Color.G, solid.Color.B));
        var tint = color is SolidColorBrush groupColor ? groupColor.Color : Microsoft.UI.Colors.Gray;
        countBadge.Background = plainGroup ? new SolidColorBrush(Microsoft.UI.Colors.Transparent) : new SolidColorBrush(Windows.UI.Color.FromArgb(33, tint.R, tint.G, tint.B));
        countBadge.BorderThickness = new Thickness(0);
        countBadge.BorderBrush = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        countBadge.CornerRadius = new CornerRadius(plainGroup ? 0 : 5);
        countLabel.Foreground = plainGroup ? HeaderButton.Foreground : color;
    }

    public HarborHostSection(string title, int count, StackPanel rows, bool collapsed, Func<bool> motion, bool favorites = false)
    {
        this.rows = rows; this.collapsed = collapsed; this.motion = motion; plainGroup = title == "Ungrouped";
        Spacing = 4;
        var header = new Grid { ColumnSpacing = 6 };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        chevron = MainWindow.HarborIcon(collapsed ? Symbol.Forward : Symbol.More, 10);
        var symbols = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        symbols.Children.Add(chevron);
        groupIcon = MainWindow.HarborIcon(favorites ? Symbol.SolidStar : Symbol.Folder, 14);
        if (title != "Ungrouped") symbols.Children.Add(groupIcon);
        header.Children.Add(symbols);
        var name = new TextBlock { Text = title == "Ungrouped" ? title.ToUpperInvariant() : title, FontSize = title == "Ungrouped" ? 10 : 12, FontWeight = title == "Ungrouped" ? Microsoft.UI.Text.FontWeights.Medium : Microsoft.UI.Text.FontWeights.SemiBold, Style = (Style)Application.Current.Resources[title == "Ungrouped" ? "HarborMutedTextStyle" : "HarborTextStyle"] };
        Grid.SetColumn(name, 1); header.Children.Add(name);
        var badgeText = new TextBlock { Text = count.ToString(), FontFamily = (FontFamily)Application.Current.Resources["HarborUIFont"], FontSize = 10, VerticalAlignment = VerticalAlignment.Center };
        countLabel = badgeText;
        countBadge = new Border
        {
            Child = badgeText,
            Padding = new Thickness(6, 2, 6, 2),
            CornerRadius = new CornerRadius(5),
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderBrush = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderThickness = new Thickness(0),
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(countBadge, 2); header.Children.Add(countBadge);
        var button = new Button { Style = (Style)Application.Current.Resources["HarborQuietButtonStyle"], Content = header, HorizontalContentAlignment = HorizontalAlignment.Stretch,
            HorizontalAlignment = HorizontalAlignment.Stretch, CornerRadius = new CornerRadius(8), BorderThickness = new Thickness(0),
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            Padding = new Thickness(10, title == "Ungrouped" ? 4 : 7, 10, title == "Ungrouped" ? 4 : 7) };
        button.Click += (_, _) => Toggle();
        HeaderButton = button;
        Children.Add(button);
        body = new Grid { Visibility = collapsed ? Visibility.Collapsed : Visibility.Visible };
        rowHighlight.RenderTransform = rowOffset; body.Children.Add(rowHighlight);
        body.Children.Add(rows);
        body.Loaded += (_, _) => { if (selectedRow is not null) SelectRow(selectedRow, rowHighlight.Background, false, false); };
        body.SizeChanged += (_, args) => body.Clip = new RectangleGeometry { Rect = new Rect(0, 0, args.NewSize.Width, args.NewSize.Height) };
        Children.Add(body);
    }

    internal UIElement? FirstRow => rows.Children.FirstOrDefault();
    internal double ContentHeight => body.ActualHeight;

    internal void Toggle()
    {
        var start = body.ActualHeight;
        animation?.Stop();
        collapsed = !collapsed;
        chevron.Glyph = collapsed ? "\uE76C" : "\uE70D";
        body.IsHitTestVisible = !collapsed;
        if (!motion()) { body.Height = double.NaN; body.Visibility = collapsed ? Visibility.Collapsed : Visibility.Visible; Toggled?.Invoke(collapsed); return; }
        body.Visibility = Visibility.Visible;
        rows.Measure(new Size(Math.Max(1, ActualWidth), double.PositiveInfinity));
        var target = collapsed ? 0 : rows.DesiredSize.Height;
        body.Height = start;
        body.IsHitTestVisible = !collapsed;
        animation = new Storyboard();
        var height = new DoubleAnimation { From = start, To = target, Duration = TimeSpan.FromMilliseconds(280), EnableDependentAnimation = true,
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } };
        Storyboard.SetTarget(height, body); Storyboard.SetTargetProperty(height, "Height");
        animation.Children.Add(height);
        var captured = animation;
        animation.Completed += (_, _) =>
        {
            if (animation != captured) return;
            captured.Stop(); body.Height = double.NaN;
            body.Visibility = collapsed ? Visibility.Collapsed : Visibility.Visible;
        };
        animation.Begin();
        Toggled?.Invoke(collapsed);
    }
}
