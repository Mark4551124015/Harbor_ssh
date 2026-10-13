using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;

namespace Harbor.Desktop;

public sealed class HarborMarkView : Grid
{
    public HarborMarkView()
    {
        var terminal = new Border { Background = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 23, 42, 66)) };
        var inset = new Canvas(); inset.Children.Add(terminal); Children.Add(inset);
        Children.Add(new Image { Source = new BitmapImage(new Uri("ms-appx:///Assets/harbor-mark.png")), Stretch = Stretch.Uniform });
        SizeChanged += (_, args) =>
        {
            var size = Math.Min(args.NewSize.Width, args.NewSize.Height);
            terminal.Width = size * .33; terminal.Height = size * .34; terminal.CornerRadius = new CornerRadius(size * .12);
            Canvas.SetLeft(terminal, (args.NewSize.Width - size) / 2 + size * .335); Canvas.SetTop(terminal, (args.NewSize.Height - size) / 2 + size * .41);
        };
    }
}
