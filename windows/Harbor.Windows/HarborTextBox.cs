using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Harbor.Desktop;

internal sealed class HarborTextBox : TextBox
{
    public HarborTextBox()
    {
        Style = (Style)Application.Current.Resources["HarborTextBoxStyle"];
        TextChanged += (_, _) => UpdatePlaceholder();
    }
    protected override void OnApplyTemplate()
    {
        base.OnApplyTemplate(); UpdatePlaceholder();
        if (GetTemplateChild("HarborFieldHeader") is FrameworkElement header) header.Visibility = Header is null ? Visibility.Collapsed : Visibility.Visible;
    }
    private void UpdatePlaceholder()
    {
        if (GetTemplateChild("HarborFieldPlaceholder") is FrameworkElement placeholder) placeholder.Visibility = Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
    }
}
