using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;

namespace Harbor.Desktop;

internal sealed class HarborCardsPanel : Panel
{
    private const double Gap = 12;
    private double rowHeight;
    protected override Size MeasureOverride(Size availableSize)
    {
        var columns = availableSize.Width > 560 ? 2 : 1;
        var width = double.IsInfinity(availableSize.Width) ? 340 : availableSize.Width;
        var cell = Math.Max(0, (width - Gap * (columns - 1)) / columns);
        rowHeight = 0;
        foreach (var child in Children) { child.Measure(new Size(cell, double.PositiveInfinity)); rowHeight = Math.Max(rowHeight, child.DesiredSize.Height); }
        var rows = (Children.Count + columns - 1) / columns;
        return new Size(width, rows * rowHeight + Math.Max(0, rows - 1) * Gap);
    }
    protected override Size ArrangeOverride(Size finalSize)
    {
        var columns = finalSize.Width > 560 ? 2 : 1;
        var cell = Math.Max(0, (finalSize.Width - Gap * (columns - 1)) / columns);
        for (var i = 0; i < Children.Count; i++) Children[i].Arrange(new Rect(i % columns * (cell + Gap), i / columns * (rowHeight + Gap), cell, rowHeight));
        return finalSize;
    }
}
