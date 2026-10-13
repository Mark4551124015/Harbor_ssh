using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Animation;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private void AddSidebarHover(Button button)
    {
        var content = button.Content as UIElement;
        var layer = new Grid();
        var padding = button.Padding;
        button.HorizontalContentAlignment = HorizontalAlignment.Stretch;
        button.VerticalContentAlignment = VerticalAlignment.Stretch;
        if (content is FrameworkElement element) element.VerticalAlignment = VerticalAlignment.Center;
        var preview = new Border
        {
            CornerRadius = button.CornerRadius, IsHitTestVisible = false, Opacity = 0,
            Margin = new Thickness(-padding.Left, -padding.Top, -padding.Right, -padding.Bottom)
        };
        button.Content = null;
        layer.Children.Add(preview);
        if (content is not null) layer.Children.Add(content);
        button.Content = layer;
        Storyboard? running = null;
        var hovered = false;
        void Fade(double target)
        {
            preview.Background = ThemeBrush("HarborTextBrush");
            var from = preview.Opacity;
            running?.Stop(); preview.Opacity = from;
            if (!MotionEnabled) { preview.Opacity = target; return; }
            var storyboard = new Storyboard(); running = storyboard;
            var fade = new DoubleAnimation { From = from, To = target, Duration = TimeSpan.FromMilliseconds(200), EnableDependentAnimation = true, EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } };
            Storyboard.SetTarget(fade, preview); Storyboard.SetTargetProperty(fade, "Opacity"); storyboard.Children.Add(fade);
            storyboard.Completed += (_, _) =>
            {
                if (running != storyboard) return;
                storyboard.Stop(); preview.Opacity = target; running = null;
            };
            storyboard.Begin();
        }
        void SetHovered(bool value)
        {
            if (hovered == value) return;
            hovered = value; Fade(value ? 0.045 : 0);
        }
        button.PointerEntered += (_, _) => SetHovered(true);
        button.PointerMoved += (_, _) => SetHovered(true);
        button.PointerExited += (_, args) =>
        {
            // Pointer capture may report an exit during a click while still inside the button.
            var point = args.GetCurrentPoint(button).Position;
            if (point.X >= 0 && point.Y >= 0 && point.X < button.ActualWidth && point.Y < button.ActualHeight) return;
            SetHovered(false);
        };
        button.Unloaded += (_, _) => { running?.Stop(); running = null; hovered = false; preview.Opacity = 0; };
    }
}
