using System.Windows;
using System.Windows.Controls;
using FusionWorkbench.Services;
using FusionWorkbench.ViewModels;

namespace FusionWorkbench;

/// <summary>
/// Simple modal settings dialog: MakerWorld user id (persisted to %LOCALAPPDATA%\FusionWorkbench)
/// and a language switch that reuses the same mechanism as the toolbar toggle.
/// </summary>
public partial class SettingsWindow : Window
{
    public SettingsWindow()
    {
        InitializeComponent();
        MakerWorldIdBox.Text = SettingsService.Current.MakerWorldUserId;
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        Loaded -= OnLoaded;
        SelectDialogLanguageRadio();
        MakerWorldIdBox.Focus();
    }

    private void SelectDialogLanguageRadio()
    {
        string code = App.LanguageCode;
        foreach (object child in LanguageGroup.Children)
        {
            if (child is RadioButton radio && radio.Tag is string tag)
            {
                radio.IsChecked = string.Equals(tag, code, System.StringComparison.OrdinalIgnoreCase);
            }
        }
    }

    private void OnDialogLanguageChecked(object sender, RoutedEventArgs e)
    {
        if (sender is RadioButton { IsChecked: true } radio && radio.Tag is string code)
        {
            var viewModel = Application.Current.MainWindow?.DataContext as MainViewModel;
            if (!string.Equals(App.LanguageCode, code, System.StringComparison.OrdinalIgnoreCase))
            {
                viewModel?.SwitchLanguage(code);
            }
        }
    }

    private void OnSaveClick(object sender, RoutedEventArgs e)
    {
        SettingsService.Current.MakerWorldUserId = MakerWorldIdBox.Text.Trim();
        SettingsService.Save();
        DialogResult = true;
    }

    private void OnCancelClick(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
    }
}
