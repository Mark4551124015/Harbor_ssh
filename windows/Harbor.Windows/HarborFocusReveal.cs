using System.Numerics;
using Microsoft.Graphics.Canvas.Effects;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;

namespace Harbor.Desktop;

internal static class HarborFocusReveal
{
    /// <summary>Native compositor blur, with the macOS launch hold and smooth focus reveal.</summary>
    internal static async Task PlayAsync(Grid host, int milliseconds, float radius, float hold = 0)
    {
        var overlay = new Grid();
        Grid.SetRowSpan(overlay, Math.Max(1, host.RowDefinitions.Count));
        Grid.SetColumnSpan(overlay, Math.Max(1, host.ColumnDefinitions.Count));
        host.Children.Add(overlay);
        try { await AnimateAsync(overlay, milliseconds, radius, hold); }
        finally { host.Children.Remove(overlay); }
    }

    private static async Task AnimateAsync(Grid overlay, int milliseconds, float radius, float hold)
    {
        overlay.UpdateLayout();
        var compositor = ElementCompositionPreview.GetElementVisual(overlay).Compositor;
        using var effect = new GaussianBlurEffect
        {
            Name = "Focus", BlurAmount = radius, BorderMode = EffectBorderMode.Hard,
            Source = new CompositionEffectSourceParameter("Backdrop")
        };
        using var factory = compositor.CreateEffectFactory(effect, ["Focus.BlurAmount"]);
        using var brush = factory.CreateBrush();
        using var backdrop = compositor.CreateBackdropBrush();
        brush.SetSourceParameter("Backdrop", backdrop);
        using var visual = compositor.CreateSpriteVisual();
        visual.Brush = brush;
        visual.Size = new Vector2((float)overlay.ActualWidth, (float)overlay.ActualHeight);
        SizeChangedEventHandler resize = (_, args) => visual.Size = new Vector2((float)args.NewSize.Width, (float)args.NewSize.Height);
        overlay.SizeChanged += resize;
        ElementCompositionPreview.SetElementChildVisual(overlay, visual);
        using var easing = compositor.CreateCubicBezierEasingFunction(new Vector2(0.65f, 0), new Vector2(0.35f, 1));
        using var focus = compositor.CreateScalarKeyFrameAnimation();
        focus.Duration = TimeSpan.FromMilliseconds(milliseconds);
        focus.InsertKeyFrame(0, radius);
        if (hold > 0) focus.InsertKeyFrame(hold, radius);
        focus.InsertKeyFrame(1, 0, easing);
        brush.StartAnimation("Focus.BlurAmount", focus);
        using var opacity = compositor.CreateScalarKeyFrameAnimation();
        opacity.Duration = focus.Duration; opacity.InsertKeyFrame(0, 1);
        if (hold > 0) opacity.InsertKeyFrame(hold, 1);
        opacity.InsertKeyFrame(1, 0, easing); visual.StartAnimation("Opacity", opacity);
        try { await Task.Delay(milliseconds + 50); }
        finally
        {
            overlay.SizeChanged -= resize;
            ElementCompositionPreview.SetElementChildVisual(overlay, null);
        }
    }
}
