using System;
using System.Windows;
using DesktopPet.Services;

namespace DesktopPet
{
    public partial class LauncherWindow : Window
    {
        private readonly MainWindow _pet;

        public LauncherWindow(MainWindow pet)
        {
            InitializeComponent();
            _pet = pet ?? throw new ArgumentNullException(nameof(pet));
        }

        private void Wake_Click(object sender, RoutedEventArgs e) => _pet.ShowFromLauncher();

        private void Chat_Click(object sender, RoutedEventArgs e) => _pet.OpenChatFromLauncher();

        private void Settings_Click(object sender, RoutedEventArgs e) =>
            _pet.OpenSettingsFromLauncher(this);

        private void Help_Click(object sender, RoutedEventArgs e) => _pet.OpenHelpFromLauncher();

        private void TuckAway_Click(object sender, RoutedEventArgs e) => _pet.TuckAwayFromLauncher();

        private void DesktopShortcut_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                ApplicationIntegrationService.CreateDesktopShortcut();
                MessageBox.Show(this,
                    "桌面快捷方式已经创建好了。以后双击“苏无度”就可以启动或叫醒她。",
                    "苏无度",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
            }
            catch (Exception exception)
            {
                MessageBox.Show(this,
                    "暂时无法创建桌面快捷方式：\n" + exception.Message,
                    "苏无度",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
            }
        }

        private void Exit_Click(object sender, RoutedEventArgs e) => _pet.ExitFromLauncher();
    }
}
