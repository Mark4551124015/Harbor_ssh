using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private void AddButtonHover(Button button, bool fillBounds = false)
    {
        var content = button.Content as UIElement;
        button.Content = null;
        var layer = new Grid();
        var padding = button.Padding;
        var preview = new Border
        {
            Background = ThemeBrush("HarborTextBrush"),
            CornerRadius = button.CornerRadius,
            Margin = new Thickness(-padding.Left, -padding.Top, -padding.Right, -padding.Bottom),
            Opacity = 0,
            IsHitTestVisible = false
        };
        layer.Children.Add(preview);
        if (content is not null) layer.Children.Add(content);
        button.Content = layer;
        // The presenter may size itself to the label. Reserve the whole button
        // interior so the preview reaches the same bounds as the selected row.
        void SizeLayer()
        {
            var inset = button.Padding;
            var border = button.BorderThickness;
            layer.Width = Math.Max(0, button.ActualWidth - inset.Left - inset.Right - border.Left - border.Right);
            layer.Height = Math.Max(0, button.ActualHeight - inset.Top - inset.Bottom - border.Top - border.Bottom);
            preview.Margin = new Thickness(-inset.Left, -inset.Top, -inset.Right, -inset.Bottom);
        }
        // Auto-sized rows must keep measuring their content. Feeding their
        // previous ActualHeight back into measure can collapse a new row to zero.
        if (fillBounds)
        {
            button.SizeChanged += (_, _) => SizeLayer();
            button.Loaded += (_, _) => SizeLayer();
        }
        Storyboard? running = null;
        var hovered = false;
        void SetHovered(bool value)
        {
            if (hovered == value) return;
            hovered = value;
            var from = preview.Opacity;
            running?.Stop();
            preview.Opacity = from;
            if (!MotionEnabled) { preview.Opacity = value ? 0.055 : 0; return; }
            var storyboard = new Storyboard();
            running = storyboard;
            var fade = new DoubleAnimation { From = from, To = value ? 0.055 : 0, Duration = TimeSpan.FromMilliseconds(160), EnableDependentAnimation = true, EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } };
            Storyboard.SetTarget(fade, preview);
            Storyboard.SetTargetProperty(fade, "Opacity");
            storyboard.Children.Add(fade);
            storyboard.Completed += (_, _) =>
            {
                if (running != storyboard) return;
                storyboard.Stop();
                preview.Opacity = value ? 0.055 : 0;
                running = null;
            };
            storyboard.Begin();
        }
        button.PointerEntered += (_, _) => SetHovered(true);
        button.PointerMoved += (_, _) => SetHovered(true);
        button.PointerExited += (_, args) =>
        {
            var point = args.GetCurrentPoint(button).Position;
            if (point.X >= 0 && point.Y >= 0 && point.X < button.ActualWidth && point.Y < button.ActualHeight) return;
            SetHovered(false);
        };
        button.Unloaded += (_, _) => { running?.Stop(); running = null; hovered = false; preview.Opacity = 0; };
    }

    private void AddSidebarHover(Button button) => AddButtonHover(button);

    private void AddCardHover(Border card)
    {
        var content = card.Child;
        card.Child = null;
        var layer = new Grid();
        var preview = new Border
        {
            Background = ThemeBrush("HarborSelectionBrush"),
            CornerRadius = card.CornerRadius,
            Margin = new Thickness(-card.Padding.Left, -card.Padding.Top, -card.Padding.Right, -card.Padding.Bottom),
            Opacity = 0,
            IsHitTestVisible = false
        };
        layer.Children.Add(preview);
        if (content is not null) layer.Children.Add(content);
        card.Child = layer;

        Storyboard? running = null;
        var hovered = false;
        void Fade(double target)
        {
            var from = preview.Opacity;
            running?.Stop();
            preview.Opacity = from;
            if (!MotionEnabled) { preview.Opacity = target; return; }
            var storyboard = new Storyboard();
            running = storyboard;
            var fade = new DoubleAnimation
            {
                From = from,
                To = target,
                Duration = TimeSpan.FromMilliseconds(180),
                EnableDependentAnimation = true,
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
            };
            Storyboard.SetTarget(fade, preview);
            Storyboard.SetTargetProperty(fade, "Opacity");
            storyboard.Children.Add(fade);
            storyboard.Completed += (_, _) =>
            {
                if (running != storyboard) return;
                storyboard.Stop();
                preview.Opacity = target;
                running = null;
            };
            storyboard.Begin();
        }
        void SetHovered(bool value)
        {
            if (hovered == value) return;
            hovered = value;
            Fade(value ? 0.16 : 0);
        }
        card.PointerEntered += (_, _) => SetHovered(true);
        card.PointerMoved += (_, _) => SetHovered(true);
        card.PointerExited += (_, args) =>
        {
            var point = args.GetCurrentPoint(card).Position;
            if (point.X >= 0 && point.Y >= 0 && point.X < card.ActualWidth && point.Y < card.ActualHeight) return;
            SetHovered(false);
        };
        card.Unloaded += (_, _) => { running?.Stop(); running = null; hovered = false; preview.Opacity = 0; };
    }

}
