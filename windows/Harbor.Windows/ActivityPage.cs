using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private string activityFilter = "All";
    private static string ActivityStatus(ObservedSshProcess entry) => entry.Endpoints.Length > 0 ? "TCP connected" : entry.Listeners.Length > 0 ? "Listening" : "No TCP observed";
    private string ActivitySource(ObservedSshProcess entry) => processes?.Sessions.Any(session => session.Active && session.ProcessId == entry.ProcessId) == true ? "Harbor" : "External";
    private static string ActivityElapsed(ObservedSshProcess entry)
    {
        if (entry.StartedAt is not { } started) return "Unknown";
        var elapsed = DateTimeOffset.Now - started;
        return elapsed.TotalDays >= 1 ? $"{(int)elapsed.TotalDays}d {elapsed:hh\\:mm\\:ss}" : elapsed.ToString(@"hh\:mm\:ss");
    }

    private Button ActivityRow(ObservedSshProcess entry)
    {
        var content = new Grid { ColumnSpacing = 12 };
        foreach (var width in new[] { new GridLength(6), new GridLength(1, GridUnitType.Star), new GridLength(78), new GridLength(70), new GridLength(12) })
            content.ColumnDefinitions.Add(new ColumnDefinition { Width = width });
        content.Children.Add(new Border { Width = 6, Height = 6, CornerRadius = new CornerRadius(3), VerticalAlignment = VerticalAlignment.Center,
            Background = entry.Endpoints.Length > 0 ? new SolidColorBrush(Windows.UI.Color.FromArgb(255, 105, 189, 176)) : ThemeBrush("HarborMutedBrush") });
        var labels = Stack(4); labels.VerticalAlignment = VerticalAlignment.Center;
        var target = Text(entry.Endpoints.Length > 0 ? entry.Endpoints.Split('\n')[0] : "SSH process", 12);
        target.TextWrapping = TextWrapping.NoWrap; target.TextTrimming = TextTrimming.CharacterEllipsis;
        labels.Children.Add(target);
        var listeners = entry.Listeners.Length > 0 ? $" · {entry.Listeners.Split('\n').Length} listeners" : "";
        var status = Muted(ActivityStatus(entry) + listeners, 10); status.TextWrapping = TextWrapping.NoWrap; status.TextTrimming = TextTrimming.CharacterEllipsis;
        labels.Children.Add(status);
        Grid.SetColumn(labels, 1); content.Children.Add(labels);
        var source = Muted(ActivitySource(entry), 11); source.VerticalAlignment = VerticalAlignment.Center; Grid.SetColumn(source, 2); content.Children.Add(source);
        var elapsed = Muted(ActivityElapsed(entry), 11); elapsed.VerticalAlignment = VerticalAlignment.Center; elapsed.TextAlignment = TextAlignment.Right; Grid.SetColumn(elapsed, 3); content.Children.Add(elapsed);
        var elapsedTimer = DispatcherQueue.CreateTimer(); elapsedTimer.Interval = TimeSpan.FromSeconds(1);
        elapsedTimer.Tick += (_, _) => elapsed.Text = ActivityElapsed(entry);
        elapsed.Loaded += (_, _) => elapsedTimer.Start(); elapsed.Unloaded += (_, _) => elapsedTimer.Stop();
        var chevron = HarborIcon(Symbol.Forward, 12); chevron.VerticalAlignment = VerticalAlignment.Center; Grid.SetColumn(chevron, 4); content.Children.Add(chevron);
        var button = ActionButton("", () => ShowActivityDetailAsync(entry), hover: false);
        button.Style = (Style)Application.Current.Resources["HarborQuietButtonStyle"];
        button.Height = 56; button.Padding = new Thickness(0); button.HorizontalAlignment = HorizontalAlignment.Stretch;
        button.HorizontalContentAlignment = HorizontalAlignment.Stretch; button.Content = content;
        return button;
    }

    private void RenderActivity()
    {
        if (page != "activity") return;
        PageContent.Children.Clear();
        var entries = localSshMonitor?.Current ?? [];
        PageDescription.Text = $"{entries.Count} local processes · updates every 2 seconds";
        HeaderActions.Children.Clear();
        HeaderActions.Children.Add(ActionButton("Refresh", () => { localSshMonitor?.RefreshNow(); RenderActivity(); return Task.CompletedTask; }, Symbol.Refresh));
        var layout = new Grid { RowSpacing = 12 };
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var filters = Segments(["All", "Connected", "With listeners"], activityFilter, value => { activityFilter = value; RenderActivity(); return Task.CompletedTask; });
        filters.Width = 340; filters.HorizontalAlignment = HorizontalAlignment.Left; layout.Children.Add(filters);
        var rows = Stack(0);
        if (localSshMonitor?.Error is { } error) rows.Children.Add(Muted(error));
        var visible = entries.Where(entry => activityFilter switch { "Connected" => entry.Endpoints.Length > 0, "With listeners" => entry.Listeners.Length > 0, _ => true }).ToArray();
        if (visible.Length == 0) rows.Children.Add(Muted(activityFilter == "All" ? "No local SSH processes running." : "No matching SSH processes."));
        foreach (var entry in visible) rows.Children.Add(ActivityRow(entry));
        var scroll = Scroll(rows); Grid.SetRow(scroll, 1); layout.Children.Add(scroll); PageContent.Children.Add(layout);
    }

    private async Task ShowActivityDetailAsync(ObservedSshProcess snapshot)
    {
        var content = Stack(12);
        var detail = Text("", 12); detail.IsTextSelectionEnabled = true; content.Children.Add(detail);
        content.Children.Add(Text("Network diagnostics", 13));
        content.Children.Add(Muted("Opens 3 TCP connections to the first observed remote endpoint. Measures port connection time, not SSH session latency or bandwidth.", 11));
        var probeLabel = Text("Test port latency", 12);
        var probe = new Button { Content = probeLabel, Style = (Style)Application.Current.Resources["HarborActionButtonStyle"], HorizontalAlignment = HorizontalAlignment.Left };
        AddButtonHover(probe); content.Children.Add(probe);
        var result = Text("", 12); result.MinHeight = 40; content.Children.Add(result);
        using var cancellation = new CancellationTokenSource();
        var closed = false; var testing = false;
        ObservedSshProcess? Current() => localSshMonitor?.Current.FirstOrDefault(entry => entry.ProcessId == snapshot.ProcessId && entry.StartedAt == snapshot.StartedAt);
        void Update()
        {
            if (closed) return;
            var current = Current(); var entry = current ?? snapshot;
            detail.Text = $"PID {entry.ProcessId} · {ActivitySource(entry)}\n{(current is null ? "Process exited · last observed" : "Running")} {ActivityElapsed(entry)} · {ActivityStatus(entry)}\n\nRemote endpoints\n{(entry.Endpoints.Length > 0 ? entry.Endpoints : "None observed")}\n\nListening ports\n{(entry.Listeners.Length > 0 ? entry.Listeners : "None observed")}";
            probe.IsEnabled = !testing && current is not null && current.Endpoints.Length > 0;
            probeLabel.Text = testing ? "Testing…" : "Test port latency";
        }
        probe.Click += async (_, _) =>
        {
            var entry = Current(); if (testing || entry is null || entry.Endpoints.Length == 0) return;
            testing = true; result.Text = ""; Update();
            try
            {
                var samples = await SshPortProbe.MeasureAsync(entry.Endpoints.Split('\n')[0], cancellation.Token);
                if (!closed) result.Text = $"{Math.Round(samples.Average())} ms average · {string.Join(" / ", samples)} ms";
            }
            catch (Exception exception) when (exception is System.Net.Sockets.SocketException or OperationCanceledException or FormatException)
            {
                if (!closed) result.Text = "Port unreachable or timed out.";
            }
            finally { testing = false; Update(); }
        };
        void Changed() => DispatcherQueue.TryEnqueue(Update);
        if (localSshMonitor is not null) localSshMonitor.Changed += Changed;
        var timer = DispatcherQueue.CreateTimer(); timer.Interval = TimeSpan.FromSeconds(1); timer.Tick += (_, _) => Update(); timer.Start();
        Update();
        try { await ShowSheetAsync<string>("SSH process", Scroll(content), "Done", () => "", 520, 500, bindSelection: _ => { }, dismissLabel: "Done"); }
        finally
        {
            closed = true; cancellation.Cancel();
            timer.Stop();
            if (localSshMonitor is not null) localSshMonitor.Changed -= Changed;
        }
    }
}
