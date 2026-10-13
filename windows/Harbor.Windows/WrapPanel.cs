using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;

namespace Harbor.Desktop;

/// <summary>Wraps native action buttons when the window becomes narrow.</summary>
internal sealed class WrapPanel : Panel
{
    private const double Gap = 8;
    protected override Size MeasureOverride(Size availableSize)
    {
        double x = 0, y = 0, rowHeight = 0, width = 0;
        foreach (var child in Children)
        {
            if (child.Visibility == Visibility.Collapsed) continue;
            child.Measure(availableSize);
            if (x > 0 && x + child.DesiredSize.Width > availableSize.Width) { y += rowHeight + Gap; x = 0; rowHeight = 0; }
            x += child.DesiredSize.Width + Gap;
            width = Math.Max(width, x - Gap);
            rowHeight = Math.Max(rowHeight, child.DesiredSize.Height);
        }
        return new Size(width, y + rowHeight);
    }
    protected override Size ArrangeOverride(Size finalSize)
    {
        double x = 0, y = 0, rowHeight = 0;
        var row = new List<UIElement>();
        void ArrangeRow()
        {
            double left = 0;
            foreach (var item in row)
            {
                item.Arrange(new Rect(left, y, item.DesiredSize.Width, rowHeight));
                left += item.DesiredSize.Width + Gap;
            }
            row.Clear();
        }
        foreach (var child in Children)
        {
            if (child.Visibility == Visibility.Collapsed) continue;
            var size = child.DesiredSize;
            if (x > 0 && x + size.Width > finalSize.Width) { ArrangeRow(); y += rowHeight + Gap; x = 0; rowHeight = 0; }
            row.Add(child);
            x += size.Width + Gap;
            rowHeight = Math.Max(rowHeight, size.Height);
        }
        ArrangeRow();
        return finalSize;
    }
}
