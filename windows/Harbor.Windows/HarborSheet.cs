using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private Action? dismissSheet;
    private async Task<T?> ShowSheetAsync<T>(string title, UIElement content, string primary, Func<T> accept, double width, double height, Func<bool>? validate = null, Action<Action<T?>>? bindSelection = null, string dismissLabel = "Cancel") where T : class
    {
        var completion = new TaskCompletionSource<T?>();
        dismissSheet = () => completion.TrySetResult(null);
        bindSelection?.Invoke(value => completion.TrySetResult(value));
        var overlay = new Grid { Background = new SolidColorBrush(Windows.UI.Color.FromArgb(80, 0, 0, 0)) }; Grid.SetRowSpan(overlay, Root.RowDefinitions.Count);
        var layout = new Grid { RowSpacing = 16 };
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) }); layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var heading = new Grid(); heading.Children.Add(Text(title, 20));
        if (bindSelection is not null)
        {
            var cancel = ActionButton(dismissLabel, () => { completion.TrySetResult(null); return Task.CompletedTask; }); cancel.HorizontalAlignment = HorizontalAlignment.Right; heading.Children.Add(cancel);
        }
        layout.Children.Add(heading); Grid.SetRow((FrameworkElement)content, 1); layout.Children.Add(content);
        var actions = Row(8); actions.HorizontalAlignment = HorizontalAlignment.Right;
        actions.Children.Add(ActionButton("Cancel", () => { completion.TrySetResult(null); return Task.CompletedTask; }));
        actions.Children.Add(ActionButton(primary, () => { if (validate?.Invoke() != false) completion.TrySetResult(accept()); return Task.CompletedTask; }, accent: true));
        Grid.SetRow(actions, 2); layout.Children.Add(actions);
        if (bindSelection is not null) actions.Visibility = Visibility.Collapsed;
        var frame = new Border { Width = width, Height = height, MaxWidth = Math.Max(280, Root.ActualWidth - 48), MaxHeight = Math.Max(260, Root.ActualHeight - 48), Padding = new Thickness(24), CornerRadius = new CornerRadius(12), Background = ThemeBrush("HarborSurfaceBrush"), BorderBrush = ThemeBrush("HarborBorderBrush"), BorderThickness = new Thickness(1), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Child = layout };
        overlay.Children.Add(frame);
        overlay.KeyDown += (_, args) => { if (args.Key == Windows.System.VirtualKey.Escape) { completion.TrySetResult(null); args.Handled = true; } };
        overlay.Tapped += (_, args) => { if (ReferenceEquals(args.OriginalSource, overlay)) completion.TrySetResult(null); };
        Root.Children.Add(overlay); AnimateReveal(frame, 320, true);
        try
        {
            var result = await completion.Task;
            if (MotionEnabled)
            {
                var storyboard = new Storyboard(); var fade = new DoubleAnimation { From = 1, To = 0, Duration = TimeSpan.FromMilliseconds(200) };
                Storyboard.SetTarget(fade, overlay); Storyboard.SetTargetProperty(fade, "Opacity"); storyboard.Children.Add(fade); overlay.IsHitTestVisible = false; storyboard.Begin(); await Task.Delay(210);
            }
            return result;
        }
        finally { Root.Children.Remove(overlay); dismissSheet = null; }
    }
}
