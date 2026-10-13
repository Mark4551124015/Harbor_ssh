using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Input;
using Windows.Foundation;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private HarborHostSection? stickySection;
    private bool updatingStickyHeader;
    private double stickyButtonHeight = double.NaN;
    private const double StickyHeaderGap = 6;

    private void ConfigureStickyHeaders()
    {
        LibraryScrollViewer.ViewChanged += (_, _) => UpdateStickyHeader();
        SidebarLibraryViewport.SizeChanged += (_, args) =>
        {
            SidebarLibraryViewport.Clip = new RectangleGeometry { Rect = new Rect(0, 0, args.NewSize.Width, args.NewSize.Height) };
            UpdateStickyHeader();
        };
        SidebarHosts.LayoutUpdated += (_, _) => UpdateStickyHeader();
        StickyGroupHeader.AddHandler(UIElement.PointerWheelChangedEvent, new PointerEventHandler((_, args) =>
        {
            var properties = args.GetCurrentPoint(StickyGroupHeader).Properties;
            if (properties.IsHorizontalMouseWheel) return;
            LibraryScrollViewer.ChangeView(null, Math.Clamp(LibraryScrollViewer.VerticalOffset - properties.MouseWheelDelta / 120.0 * 48, 0, LibraryScrollViewer.ScrollableHeight), null, true);
            args.Handled = true;
        }), true);
    }

    private void RestoreStickyHeader()
    {
        if (stickySection is { } section)
        {
            StickyGroupHeader.Child = null;
            section.HeaderButton.Height = stickyButtonHeight;
            section.HeaderSlot.Children.Add(section.HeaderButton);
            section.HeaderSlot.Height = double.NaN;
            stickySection = null;
        }
        StickyGroupHeader.Visibility = Visibility.Collapsed;
    }

    private void UpdateStickyHeader()
    {
        if (updatingStickyHeader) return;
        updatingStickyHeader = true;
        try
        {
            var sections = SidebarHosts.Children.OfType<HarborHostSection>().ToArray();
            // ViewChanged can precede the compositor's viewport transform update.
            // Use stable content coordinates and the current scroll offset so a
            // new pin is not immediately undone by a stale viewport transform.
            var positions = sections.Select(section => section.HeaderSlot.TransformToVisual(SidebarHosts).TransformPoint(new Point()).Y - LibraryScrollViewer.VerticalOffset).ToArray();
            var index = -1;
            for (var i = 0; i < positions.Length; i++)
                if (positions[i] <= 0.5) index = i;
            // Prepare the fixed layer as soon as a header reaches the top,
            // before the next wheel input lets the scroll compositor move it.
            // This is the same button at the same position, never a duplicate.
            var candidate = index >= 0 ? sections[index] : null;
            if (candidate != stickySection)
            {
                RestoreStickyHeader();
                if (candidate is not null)
                {
                    // Reuse the original button, including its menu and drag handlers.
                    var height = candidate.HeaderSlot.ActualHeight;
                    if (height <= 0) return;
                    stickyButtonHeight = candidate.HeaderButton.Height;
                    candidate.HeaderSlot.Height = height;
                    StickyGroupHeader.Width = LibraryScrollViewer.ActualWidth;
                    StickyGroupHeader.Height = height + StickyHeaderGap;
                    candidate.HeaderButton.Height = height;
                    candidate.HeaderSlot.Children.Remove(candidate.HeaderButton);
                    StickyGroupHeader.Child = candidate.HeaderButton;
                    stickySection = candidate;
                    StickyGroupHeader.Visibility = Visibility.Visible;
                }
            }
            if (candidate is not null)
            {
                StickyGroupHeader.Width = LibraryScrollViewer.ActualWidth;
                StickyGroupHeaderOffset.Y = index + 1 < positions.Length ? Math.Min(0, positions[index + 1] - StickyGroupHeader.Height) : 0;
            }
        }
        finally { updatingStickyHeader = false; }
    }
}
