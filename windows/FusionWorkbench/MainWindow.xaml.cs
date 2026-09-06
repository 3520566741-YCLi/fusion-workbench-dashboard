using System.Windows;
using System.Windows.Controls;
using FusionWorkbench.ViewModels;

namespace FusionWorkbench;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        Loaded -= OnLoaded;
        SelectLanguageRadio();
    }

    private MainViewModel? ViewModel => DataContext as MainViewModel;

    private void SelectLanguageRadio()
    {
        string code = App.LanguageCode;
        foreach (object child in LanguageButtons.Children)
        {
            if (child is RadioButton radio && radio.Tag is string tag)
            {
                radio.IsChecked = string.Equals(tag, code, System.StringComparison.OrdinalIgnoreCase);
            }
        }
    }

    private void OnLanguageChecked(object sender, RoutedEventArgs e)
    {
        if (sender is RadioButton { IsChecked: true } radio && radio.Tag is string code)
        {
            ViewModel?.SwitchLanguage(code);
        }
    }

    private void OnRefreshClick(object sender, RoutedEventArgs e)
    {
        ViewModel?.RefreshNow();
    }

    private void OnSettingsClick(object sender, RoutedEventArgs e)
    {
        var dialog = new SettingsWindow { Owner = this };
        bool? result = dialog.ShowDialog();
        if (result == true)
        {
            // Settings may have changed the MakerWorld user id -> refresh immediately.
            ViewModel?.RefreshNow();
        }
    }
}
