using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;

namespace Harbor.Desktop;

/// <summary>Matches the macOS 190 ms overlay fade, including interrupted navigation.</summary>
internal sealed class HarborPageTransition(Grid host)
{
    private Storyboard? current;
    private Grid? incoming;
    private int generation;

    public void Show(Grid next, bool animate)
    {
        var version = ++generation;
        if (incoming is not null && current is not null)
        {
            // Freeze its current opacity before stopping the timer. Keep all backing layers.
            var opacity = incoming.Opacity;
            current.Stop();
            incoming.Opacity = opacity;
        }
        foreach (var child in host.Children.OfType<Grid>()) BlockInput(child, true);
        incoming = next;
        if (!animate || host.Children.Count == 0)
        {
            host.Children.Clear();
            next.Opacity = 1;
            host.Children.Add(next);
            current = null;
            return;
        }
        next.Opacity = 0;
        next.IsHitTestVisible = false;
        next.GettingFocus += (_, args) => { if (!next.IsHitTestVisible) args.Cancel = true; };
        host.Children.Add(next);
        current = new Storyboard();
        var fade = new DoubleAnimation
        {
            From = 0, To = 1, Duration = TimeSpan.FromMilliseconds(190),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
        };
        Storyboard.SetTarget(fade, next);
        Storyboard.SetTargetProperty(fade, "Opacity");
        current.Children.Add(fade);
        current.Completed += (_, _) =>
        {
            if (version != generation) return;
            next.Opacity = 1;
            foreach (var child in host.Children.ToList()) if (child != next) host.Children.Remove(child);
            next.IsHitTestVisible = true;
            current = null;
        };
        current.Begin();
    }

    public void Finish()
    {
        generation++;
        current?.Stop(); current = null;
        if (incoming is null) return;
        incoming.Opacity = 1; incoming.IsHitTestVisible = true;
        foreach (var child in host.Children.ToList()) if (child != incoming) host.Children.Remove(child);
    }

    private static void BlockInput(DependencyObject parent, bool block)
    {
        if (parent is UIElement element) element.IsHitTestVisible = !block;
        if (parent is Control control) control.IsTabStop = !block;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
            BlockInput(VisualTreeHelper.GetChild(parent, i), block);
    }
}
