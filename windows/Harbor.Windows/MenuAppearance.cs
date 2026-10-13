using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private MenuFlyout HarborMenu()
    {
        var menu = new MenuFlyout();
        menu.Opening += (_, _) =>
        {
            var presenter = new Style(typeof(MenuFlyoutPresenter));
            presenter.Setters.Add(new Setter(FrameworkElement.RequestedThemeProperty, Root.ActualTheme));
            presenter.Setters.Add(new Setter(Control.BackgroundProperty, ThemeBrush("HarborSurfaceBrush")));
            presenter.Setters.Add(new Setter(Control.ForegroundProperty, ThemeBrush("HarborTextBrush")));
            presenter.Setters.Add(new Setter(Control.BorderBrushProperty, ThemeBrush("HarborBorderBrush")));
            presenter.Setters.Add(new Setter(Control.CornerRadiusProperty, new CornerRadius(10)));
            presenter.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(5)));
            menu.MenuFlyoutPresenterStyle = presenter;
            StyleMenuItems(menu.Items);
        };
        return menu;
    }
    private void StyleMenuItems(IList<MenuFlyoutItemBase> items)
    {
        foreach (var item in items)
        {
            item.FontSize = 12;
            item.FontFamily = (FontFamily)Application.Current.Resources["HarborUIFont"];
            item.RequestedTheme = Root.ActualTheme;
            item.Foreground = ThemeBrush("HarborTextBrush");
            if (item is not MenuFlyoutSeparator)
            {
                item.MinHeight = 28;
                item.Padding = new Thickness(10, 5, 10, 5);
                item.CornerRadius = new CornerRadius(5);
                item.Resources["MenuFlyoutItemBackgroundPointerOver"] = ThemeBrush("HarborSelectionBrush");
                item.Resources["MenuFlyoutItemBackgroundPressed"] = ThemeBrush("HarborSelectionBrush");
                item.Resources["MenuFlyoutItemForegroundPointerOver"] = ThemeBrush("HarborTextBrush");
                item.Resources["MenuFlyoutItemForeground"] = ThemeBrush("HarborTextBrush");
                item.Resources["MenuFlyoutItemForegroundPressed"] = ThemeBrush("HarborTextBrush");
                item.Resources["MenuFlyoutSubItemForeground"] = ThemeBrush("HarborTextBrush");
                item.Resources["MenuFlyoutSubItemForegroundPointerOver"] = ThemeBrush("HarborTextBrush");
                item.Resources["MenuFlyoutSubItemBackgroundPointerOver"] = ThemeBrush("HarborSelectionBrush");
            }
            if (item is MenuFlyoutItem action && (action.Text.StartsWith("Delete ") || action.Text.StartsWith("Remove ")))
                action.Foreground = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 211, 80, 80));
            if (item is MenuFlyoutSubItem submenu) StyleMenuItems(submenu.Items);
        }
    }
}
