using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;

namespace Harbor.Desktop;

/// <summary>Animated tabs with a matching, translucent hover preview.</summary>
internal sealed class HarborTabStrip : Grid
{
    private readonly List<(string Value, Button Button, TextBlock Text)> tabs = [];
    private readonly Border underline;
    private readonly Dictionary<Border, Storyboard> hoverAnimations = [];
    private readonly Dictionary<string, Border> previews = [];
    private readonly bool capsule;
    private readonly TranslateTransform offset = new();
    private readonly Brush foreground;
    private readonly Brush muted;
    private readonly Brush selectedTint;
    private readonly Func<bool> motion;
    private Storyboard? animation;
    private string selected;
    private bool positioned;

    internal HarborTabStrip(IEnumerable<string> values, string selected, Brush foreground, Brush muted, Brush accent, Func<bool> motion, Action<string> changed, bool capsule = false, Brush? selectedTint = null)
    {
        this.selected = selected; this.foreground = foreground; this.muted = muted; this.motion = motion; this.capsule = capsule; this.selectedTint = selectedTint ?? accent;
        var row = new WrapPanel();
        underline = new Border { Height = 2, Width = 12, Background = capsule ? this.selectedTint : accent, Opacity = capsule ? 0.13 : 1, CornerRadius = new CornerRadius(capsule ? 6 : 0), HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top, RenderTransform = offset, IsHitTestVisible = false };
        Children.Add(underline);
        Children.Add(row);
        foreach (var value in values)
        {
            // Reserve the widest font weight so selection never changes the tab's layout.
            var font = (FontFamily)Application.Current.Resources["HarborUIFont"];
            var label = new TextBlock { Text = value, FontFamily = font, FontSize = 12, TextAlignment = TextAlignment.Center, IsTextSelectionEnabled = false };
            var labelLayout = new Grid();
            foreach (var weight in new[] { Microsoft.UI.Text.FontWeights.Normal, Microsoft.UI.Text.FontWeights.SemiBold })
            {
                var measure = new TextBlock { Text = value, FontFamily = font, FontSize = 12, FontWeight = weight, Opacity = 0, IsHitTestVisible = false, IsTextSelectionEnabled = false };
                Microsoft.UI.Xaml.Automation.AutomationProperties.SetAccessibilityView(measure, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
                labelLayout.Children.Add(measure);
            }
            labelLayout.Children.Add(label);
            var button = new Button { Content = labelLayout, Style = (Style)Application.Current.Resources["HarborTabButtonStyle"], Padding = new Thickness(10, 7, 10, 9), BorderThickness = new Thickness(0), Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent) };
            var previewOffset = new TranslateTransform();
            var preview = new Border { Background = capsule ? foreground : accent, Opacity = 0, CornerRadius = underline.CornerRadius, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top, RenderTransform = previewOffset, IsHitTestVisible = false };
            previews[value] = preview; Children.Insert(1, preview);
            button.Click += (_, _) =>
            {
                if (this.selected == value) return;
                this.selected = value; Update(true); changed(value);
            };
            button.PointerEntered += (_, _) =>
            {
                var bounds = IndicatorBounds(button, label);
                previewOffset.X = bounds.X; previewOffset.Y = bounds.Y;
                preview.Width = bounds.Width; preview.Height = bounds.Height;
                FadePreview(preview, capsule ? 0.06 : 0.3);
            };
            button.PointerExited += (_, args) =>
            {
                var point = args.GetCurrentPoint(button).Position;
                if (point.X >= 0 && point.Y >= 0 && point.X < button.ActualWidth && point.Y < button.ActualHeight) return;
                FadePreview(preview, 0);
            };
            tabs.Add((value, button, label)); row.Children.Add(button);
        }
        Loaded += (_, _) => Update(false);
        SizeChanged += (_, _) => Update(false);
        Unloaded += (_, _) =>
        {
            foreach (var storyboard in hoverAnimations.Values) storyboard.Stop();
            hoverAnimations.Clear();
        };
    }
    private void FadePreview(Border preview, double opacity)
    {
        var current = preview.Opacity;
        if (hoverAnimations.Remove(preview, out var previous)) previous.Stop();
        preview.Opacity = current;
        if (!motion()) { preview.Opacity = opacity; return; }
        var storyboard = new Storyboard();
        var fade = new DoubleAnimation { From = current, To = opacity, Duration = TimeSpan.FromMilliseconds(200), EnableDependentAnimation = true, EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } };
        Storyboard.SetTarget(fade, preview); Storyboard.SetTargetProperty(fade, "Opacity"); storyboard.Children.Add(fade);
        hoverAnimations[preview] = storyboard;
        storyboard.Completed += (_, _) =>
        {
            if (!hoverAnimations.TryGetValue(preview, out var active) || active != storyboard) return;
            storyboard.Stop(); preview.Opacity = opacity; hoverAnimations.Remove(preview);
        };
        storyboard.Begin();
    }
    private Windows.Foundation.Rect IndicatorBounds(Button button, TextBlock label)
    {
        var point = (capsule ? (UIElement)button : label).TransformToVisual(this).TransformPoint(new Windows.Foundation.Point());
        return capsule ? new(point.X, point.Y, button.ActualWidth, button.ActualHeight) :
            new(point.X, button.TransformToVisual(this).TransformPoint(new Windows.Foundation.Point()).Y + button.ActualHeight - 2, Math.Max(12, label.ActualWidth), 2);
    }
    private void Update(bool animate)
    {
        foreach (var tab in tabs)
        {
            tab.Text.Foreground = tab.Value == selected ? (capsule ? selectedTint : foreground) : muted;
            tab.Text.FontWeight = tab.Value == selected ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal;
        }
        UpdateLayout();
        foreach (var tab in tabs)
        {
            var preview = previews[tab.Value];
            var previewBounds = IndicatorBounds(tab.Button, tab.Text);
            var transform = (TranslateTransform)preview.RenderTransform;
            transform.X = previewBounds.X; transform.Y = previewBounds.Y;
            preview.Width = previewBounds.Width; preview.Height = previewBounds.Height;
        }
        var active = tabs.First(tab => tab.Value == selected);
        var bounds = IndicatorBounds(active.Button, active.Text);
        var point = new Windows.Foundation.Point(bounds.X, bounds.Y);
        var targetWidth = bounds.Width;
        var targetY = bounds.Y;
        underline.Height = bounds.Height;
        var startX = offset.X; var startWidth = underline.ActualWidth;
        animation?.Stop(); offset.X = startX; underline.Width = startWidth; offset.Y = targetY;
        if (!positioned || !animate || !motion()) { offset.X = point.X; underline.Width = targetWidth; positioned = true; return; }
        animation = new Storyboard();
        void Add(DependencyObject target, string property, double from, double to)
        {
            var change = new DoubleAnimation { From = from, To = to, Duration = TimeSpan.FromMilliseconds(190), EnableDependentAnimation = true, EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } };
            Storyboard.SetTarget(change, target); Storyboard.SetTargetProperty(change, property); animation.Children.Add(change);
        }
        Add(offset, "X", startX, point.X); Add(underline, "Width", startWidth, targetWidth); animation.Begin();
    }
}
