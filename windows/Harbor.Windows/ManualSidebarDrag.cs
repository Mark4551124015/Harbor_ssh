using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.Foundation;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private Point? rowDragStart;
    private Func<string[]>? rowDragSelection;
    private string? rowDragSection;
    private string[] rowDragAliases = [];
    private bool rowDragActive;
    private string rowDropGroup = "Ungrouped";
    private string? rowDropAlias;
    private bool rowDropAfter;
    private bool rowDropValid;

    private void ConfigureManualSidebarDrag(Button button, Func<string[]> selection, string? section)
    {
        button.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler((_, args) =>
        {
            var point = args.GetCurrentPoint(LibraryScrollViewer);
            if (!point.Properties.IsLeftButtonPressed) return;
            for (var element = args.OriginalSource as DependencyObject; element is not null && element != button; element = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(element))
                if (element is Button) return;
            rowDragStart = point.Position; rowDragSelection = selection; rowDragSection = section;
        }), true);
    }

    private void ConfigureManualSidebarDragSurface()
    {
        SidebarLibraryViewport.AddHandler(UIElement.PointerMovedEvent, new PointerEventHandler((_, args) =>
        {
            if (rowDragStart is not Point start) return;
            var point = args.GetCurrentPoint(LibraryScrollViewer);
            if (!point.Properties.IsLeftButtonPressed) return;
            if (!rowDragActive && Math.Abs(point.Position.X - start.X) + Math.Abs(point.Position.Y - start.Y) > 6)
            {
                rowDragAliases = rowDragSelection?.Invoke() ?? [];
                rowDragActive = true; suppressSidebarClick = true;
                LibraryScrollViewer.CapturePointer(args.Pointer);
            }
            if (!rowDragActive) return;
            args.Handled = true;
            var y = point.Position.Y;
            if (y < 24 || y > LibraryScrollViewer.ActualHeight - 24)
                LibraryScrollViewer.ChangeView(null, Math.Clamp(LibraryScrollViewer.VerticalOffset + (y < 24 ? -12 : 12), 0, LibraryScrollViewer.ScrollableHeight), null, true);
            rowDropGroup = "Ungrouped"; rowDropAlias = null; rowDropAfter = true;
            rowDropValid = false;
            foreach (var section in SidebarHosts.Children.OfType<HarborHostSection>().OrderByDescending(section => ReferenceEquals(section, stickySection)))
            {
                var header = section.HeaderButton;
                var headerTop = header.TransformToVisual(LibraryScrollViewer).TransformPoint(new Point());
                if (y >= headerTop.Y && y <= headerTop.Y + header.ActualHeight)
                {
                    rowDropGroup = (string)header.Tag; rowDropAlias = null; rowDropAfter = false;
                    SidebarSelectionOffset.X = headerTop.X; SidebarSelectionOffset.Y = headerTop.Y;
                    SidebarSelectionRectangle.Width = header.ActualWidth; SidebarSelectionRectangle.Height = header.ActualHeight;
                    rowDropValid = true; SidebarSelectionRectangle.Visibility = Visibility.Visible; return;
                }
                var buttons = section.ContentHeight > 0 ? section.HostButtons.ToList() : [];
                if (buttons.Count == 0) continue;
                var bounds = buttons.Select(button => (Button: button, Top: button.TransformToVisual(LibraryScrollViewer).TransformPoint(new Point()))).ToList();
                var first = bounds[0]; var last = bounds[^1];
                if (y < first.Top.Y - 4 || y > last.Top.Y + last.Button.ActualHeight + 4) continue;
                var boundaries = new List<double> { first.Top.Y - 2 };
                for (var i = 1; i < bounds.Count; i++) boundaries.Add((bounds[i - 1].Top.Y + bounds[i - 1].Button.ActualHeight + bounds[i].Top.Y) / 2);
                boundaries.Add(last.Top.Y + last.Button.ActualHeight + 2);
                var slot = Enumerable.Range(0, boundaries.Count).MinBy(index => Math.Abs(boundaries[index] - y));
                rowDropGroup = (string)header.Tag;
                rowDropAlias = slot == buttons.Count ? null : (string)buttons[slot].Tag;
                rowDropAfter = false;
                SidebarSelectionOffset.X = first.Top.X; SidebarSelectionOffset.Y = boundaries[slot] - 1;
                SidebarSelectionRectangle.Width = first.Button.ActualWidth; SidebarSelectionRectangle.Height = 2;
                rowDropValid = true; SidebarSelectionRectangle.Visibility = Visibility.Visible; return;
            }            SidebarSelectionRectangle.Visibility = Visibility.Collapsed;
        }), true);
        SidebarLibraryViewport.AddHandler(UIElement.PointerReleasedEvent, new PointerEventHandler(async (_, args) =>
        {
            var active = rowDragActive;
            rowDragStart = null; rowDragActive = false;
            if (!active) return;
            args.Handled = true; SidebarSelectionRectangle.Visibility = Visibility.Collapsed;
            LibraryScrollViewer.ReleasePointerCaptures();
            var aliases = rowDragAliases; var section = rowDragSection;
            var group = rowDropGroup; var before = rowDropAlias; var after = rowDropAfter;
            if (!rowDropValid) { suppressSidebarClick = false; return; }
            await RunAsync(async () =>
            {
                var prefs = preferences.Value;
                if (section is not null)
                {
                    if (section == group) return;
                    var names = SidebarHosts.Children.OfType<HarborHostSection>().Select(value => (string)value.HeaderButton.Tag).Where(name => name != "Ungrouped").ToList();
                    names.Remove(section); var index = names.IndexOf(group);
                    names.Insert(index < 0 ? names.Count : index + (after ? 1 : 0), section); prefs.SectionOrder = names;
                }
                else
                {
                    if (before is not null && aliases.Contains(before)) return;
                    foreach (var alias in aliases)
                        if (group == "Favorites") prefs.Favorites.Add(alias); else if (group == "Ungrouped") prefs.HostGroups.Remove(alias); else prefs.HostGroups[alias] = group;
                    var members = config.Document.Hosts.Where(host => group == "Favorites" ? prefs.Favorites.Contains(host.Alias) : prefs.HostGroups.GetValueOrDefault(host.Alias, "Ungrouped") == group).Select(host => host.Alias).ToList();
                    var order = prefs.HostOrder.GetValueOrDefault(group, []).Concat(members).Distinct().Where(alias => members.Contains(alias) && !aliases.Contains(alias)).ToList();
                    var index = before is null ? -1 : order.IndexOf(before);
                    order.InsertRange(index < 0 ? order.Count : index + (after ? 1 : 0), aliases); prefs.HostOrder[group] = order;
                }
                await SavePreferencesAsync(); PopulateHosts();
            });
            suppressSidebarClick = false;
        }), true);
        LibraryScrollViewer.PointerCaptureLost += (_, args) => { if (!ReferenceEquals(args.OriginalSource, LibraryScrollViewer)) return; rowDragStart = null; rowDragActive = false; SidebarSelectionRectangle.Visibility = Visibility.Collapsed; };
        Root.KeyDown += (_, args) =>
        {
            if (args.Key != Windows.System.VirtualKey.Escape || !rowDragActive) return;
            rowDragActive = false; rowDragStart = null; suppressSidebarClick = false;
            SidebarSelectionRectangle.Visibility = Visibility.Collapsed; LibraryScrollViewer.ReleasePointerCaptures(); args.Handled = true;
        };
    }
}
