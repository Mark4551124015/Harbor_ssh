using Microsoft.UI.Xaml;

namespace Harbor.Desktop;

public partial class App : Application
{
    private Window? window;
    public App() => InitializeComponent();

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        var arguments = Environment.GetCommandLineArgs();
        if (arguments.Length > 1 && arguments[1] == "--ssh-proxy")
        {
            try
            {
                if (arguments.Length != 7) throw new ArgumentException("Invalid proxy arguments.");
                await Harbor.Core.ProxyRelay.RunAsync(arguments[2], arguments[3], int.Parse(arguments[4]), arguments[5], int.Parse(arguments[6]), Console.OpenStandardInput(), Console.OpenStandardOutput());
                Environment.Exit(0);
            }
            catch (Exception exception) { Console.Error.WriteLine(exception.Message); Environment.Exit(1); }
            return;
        }
        var smokeIndex = Array.IndexOf(arguments, "--smoke-test");
        var smokeReport = smokeIndex >= 0 && smokeIndex + 1 < arguments.Length ? arguments[smokeIndex + 1] : null;
        if (smokeReport is not null)
            UnhandledException += (_, exception) =>
            {
                File.WriteAllText(smokeReport, exception.Exception.ToString());
                Environment.Exit(1);
            };
        window = new MainWindow(smokeReport);
        window.Activate();
    }
}
