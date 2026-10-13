using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Media.Imaging;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private void AnimateReveal(FrameworkElement element, int milliseconds = 280, bool zoom = false)
    {
        if (!MotionEnabled) return;
        var story = new Storyboard();
        void Add(DependencyObject target, string property, double from, double to)
        {
            var animation = new DoubleAnimation { From = from, To = to, Duration = TimeSpan.FromMilliseconds(milliseconds), EnableDependentAnimation = true, EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } };
            Storyboard.SetTarget(animation, target); Storyboard.SetTargetProperty(animation, property); story.Children.Add(animation);
        }
        Add(element, "Opacity", 0, 1);
        if (zoom)
        {
            var scale = new ScaleTransform(); element.RenderTransformOrigin = new Windows.Foundation.Point(.5, .5); element.RenderTransform = scale;
            Add(scale, "ScaleX", 1.08, 1); Add(scale, "ScaleY", 1.08, 1);
        }
        story.Begin();
    }
    private async Task PlayLaunchAsync()
    {
        var blur = HarborFocusReveal.PlayAsync(Root, 1000, 14, .5f);
        var logo = new Border { Width = 96, Height = 96, CornerRadius = new CornerRadius(22), Background = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 23, 42, 66)), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            Child = new HarborMarkView { Width = 84, Height = 84 } };
        var layer = new Grid { IsHitTestVisible = false }; Grid.SetRowSpan(layer, Root.RowDefinitions.Count); layer.Children.Add(logo); Root.Children.Add(layer);
        try
        {
            await Task.Delay(500);
            var fade = new Storyboard(); var opacity = new DoubleAnimation { From = 1, To = 0, Duration = TimeSpan.FromMilliseconds(500), EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } };
            Storyboard.SetTarget(opacity, layer); Storyboard.SetTargetProperty(opacity, "Opacity"); fade.Children.Add(opacity); fade.Begin(); await blur;
        }
        finally { Root.Children.Remove(layer); }
    }
}
