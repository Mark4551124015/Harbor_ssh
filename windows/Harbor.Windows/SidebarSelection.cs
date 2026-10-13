using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Windows.Foundation;
using Windows.System;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private Point? sidebarPress;
    private Point sidebarPointer;
    private double sidebarAnchorY;
    private bool sidebarDragging;
    private bool suppressSidebarClick;
    private HashSet<string> sidebarInitialSelection = [];
    private bool sidebarAdditiveSelection;

    private void ConfigureSidebarSelection()
    {
        var scroll = DispatcherQueue.CreateTimer(); scroll.Interval = TimeSpan.FromMilliseconds(16);
        scroll.Tick += (_, _) =>
        {
            if (!sidebarDragging) return;
            var delta = sidebarPointer.Y < 24 ? -10 : sidebarPointer.Y > LibraryScrollViewer.ActualHeight - 24 ? 10 : 0;
            if (delta != 0) { LibraryScrollViewer.ChangeView(null, Math.Clamp(LibraryScrollViewer.VerticalOffset + delta, 0, LibraryScrollViewer.ScrollableHeight), null, true); UpdateSidebarRectangle(); }
        };
        LibraryScrollViewer.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler((_, args) =>
        {
            var point = args.GetCurrentPoint(LibraryScrollViewer);
            if (!point.Properties.IsLeftButtonPressed) return;
            for (var source = args.OriginalSource as DependencyObject; source is not null && source != LibraryScrollViewer; source = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(source))
                if (source is ScrollBar or Button) return;
            sidebarPress = point.Position; sidebarPointer = point.Position;
            sidebarAnchorY = point.Position.Y + LibraryScrollViewer.VerticalOffset;
            sidebarInitialSelection = new HashSet<string>(selectedHosts, StringComparer.OrdinalIgnoreCase);
            sidebarAdditiveSelection = KeyDown(VirtualKey.Control) || KeyDown(VirtualKey.Shift);
        }), true);
        LibraryScrollViewer.AddHandler(UIElement.PointerMovedEvent, new PointerEventHandler((_, args) =>
        {
            if (sidebarPress is not Point start) return;
            var point = args.GetCurrentPoint(LibraryScrollViewer);
            if (!point.Properties.IsLeftButtonPressed) return;
            sidebarPointer = point.Position;
            if (!sidebarDragging && (Math.Abs(point.Position.X - start.X) > 5 || Math.Abs(point.Position.Y - start.Y) > 5))
            {
                sidebarDragging = true; suppressSidebarClick = true;
                LibraryScrollViewer.CapturePointer(args.Pointer);
                SidebarSelectionRectangle.Visibility = Visibility.Visible; scroll.Start();
            }
            if (!sidebarDragging) return;
            UpdateSidebarRectangle(); args.Handled = true;
        }), true);
        void Finish(bool cancel)
        {
            scroll.Stop(); SidebarSelectionRectangle.Visibility = Visibility.Collapsed;
            if (cancel && sidebarDragging) { selectedHosts.Clear(); selectedHosts.UnionWith(sidebarInitialSelection); UpdateHostSelection(); }
            var dragged = sidebarDragging;
            sidebarPress = null; sidebarDragging = false;
            if (dragged) LibraryScrollViewer.ReleasePointerCaptures();
            if (dragged) DispatcherQueue.TryEnqueue(() => suppressSidebarClick = false);
        }
        LibraryScrollViewer.AddHandler(UIElement.PointerReleasedEvent, new PointerEventHandler((_, args) =>
        {
            if (sidebarDragging) args.Handled = true;
            Finish(false);
        }), true);
        LibraryScrollViewer.AddHandler(UIElement.PointerCanceledEvent, new PointerEventHandler((_, _) => Finish(true)), true);
        LibraryScrollViewer.PointerCaptureLost += (_, _) => { if (sidebarDragging) Finish(false); };
        Root.KeyDown += (_, args) => { if (args.Key == VirtualKey.Escape && sidebarDragging) { Finish(true); args.Handled = true; } };
        ConfigureSidebarDrop(LibraryScrollViewer, "Ungrouped", null);
    }

    private void UpdateSidebarRectangle()
    {
        if (sidebarPress is not Point start) return;
        var anchor = sidebarAnchorY - LibraryScrollViewer.VerticalOffset;
        var left = Math.Clamp(Math.Min(start.X, sidebarPointer.X), 0, LibraryScrollViewer.ActualWidth);
        var right = Math.Clamp(Math.Max(start.X, sidebarPointer.X), 0, LibraryScrollViewer.ActualWidth);
        var top = Math.Clamp(Math.Min(anchor, sidebarPointer.Y), 0, LibraryScrollViewer.ActualHeight);
        var bottom = Math.Clamp(Math.Max(anchor, sidebarPointer.Y), 0, LibraryScrollViewer.ActualHeight);
        var band = new Rect(left, top, Math.Max(1, right - left), Math.Max(1, bottom - top));
        SidebarSelectionOffset.X = band.X; SidebarSelectionOffset.Y = band.Y;
        SidebarSelectionRectangle.Width = band.Width; SidebarSelectionRectangle.Height = band.Height;
        selectedHosts.Clear();
        if (sidebarAdditiveSelection) selectedHosts.UnionWith(sidebarInitialSelection);
        foreach (var section in SidebarHosts.Children.OfType<HarborHostSection>().Where(section => section.ContentHeight > 0))
            foreach (var button in section.HostButtons)
            {
                var position = button.TransformToVisual(LibraryScrollViewer).TransformPoint(new Point());
                var bounds = new Rect(position.X, position.Y, button.ActualWidth, button.ActualHeight);
                bounds.Intersect(band);
                if (!bounds.IsEmpty && bounds.Width > 0 && bounds.Height > 0 && button.Tag is string alias) selectedHosts.Add(alias);
            }
        UpdateHostSelection();
    }
}
