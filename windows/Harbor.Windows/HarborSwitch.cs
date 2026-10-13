using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;

namespace Harbor.Desktop;

internal sealed class HarborSwitch : Button
{
    private readonly Border track;
    private readonly TranslateTransform offset = new();
    private bool isOn;
    private Storyboard? animation;
    public event RoutedEventHandler? Toggled;
    public object? OnContent { get; set; }
    public object? OffContent { get; set; }
    public Brush OnBrush { get; set; } = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 154, 84, 39));
    public Brush OffBrush { get; set; } = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 206, 206, 210));
    public Func<bool>? MotionAllowed { get; set; }
    public bool IsOn
    {
        get => isOn;
        set { if (isOn == value) return; isOn = value; Refresh(); Toggled?.Invoke(this, new RoutedEventArgs()); }
    }
    public HarborSwitch()
    {
        Style = (Style)Application.Current.Resources["HarborQuietButtonStyle"];
        Width = 40; Height = 26; Padding = new Thickness(0);
        var visual = new Grid { Width = 38, Height = 22 };
        track = new Border { Background = OffBrush, CornerRadius = new CornerRadius(11) }; visual.Children.Add(track);
        visual.Children.Add(new Border { Width = 18, Height = 18, CornerRadius = new CornerRadius(9), Background = new SolidColorBrush(Microsoft.UI.Colors.White), HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(2, 0, 0, 0), RenderTransform = offset });
        Content = visual; Click += (_, _) => IsOn = !IsOn;
        Loaded += (_, _) => Refresh();
    }
    public void Refresh()
    {
        track.Background = IsOn ? OnBrush : OffBrush;
        var from = offset.X; animation?.Stop(); offset.X = from;
        if (!IsLoaded || !(MotionAllowed?.Invoke() ?? new Windows.UI.ViewManagement.UISettings().AnimationsEnabled)) { offset.X = IsOn ? 16 : 0; return; }
        animation = new Storyboard();
        var slide = new DoubleAnimation { From = from, To = IsOn ? 16 : 0, Duration = TimeSpan.FromMilliseconds(160), EnableDependentAnimation = true, EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } };
        Storyboard.SetTarget(slide, offset); Storyboard.SetTargetProperty(slide, "X"); animation.Children.Add(slide); animation.Begin();
    }
}
