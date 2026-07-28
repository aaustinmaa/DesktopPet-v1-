using System;
using System.Globalization;
using System.IO;
using System.Text;
using System.Windows;
using DesktopPet.Services;
using Microsoft.Win32;

namespace DesktopPet
{
    public partial class FocusExportWindow : Window
    {
        private readonly FocusJournalService _service;

        public FocusExportWindow(
            FocusJournalService service,
            DateTime selectedDate)
        {
            InitializeComponent();
            _service = service ?? throw new ArgumentNullException(nameof(service));
            var end = selectedDate.Date;
            StartDatePicker.SelectedDate =
                new DateTime(end.Year, end.Month, 1);
            EndDatePicker.SelectedDate = end;
        }

        private void Export_Click(object sender, RoutedEventArgs e)
        {
            if (!StartDatePicker.SelectedDate.HasValue ||
                !EndDatePicker.SelectedDate.HasValue)
            {
                ShowWarning("请选择开始日期和结束日期。");
                return;
            }

            var start = StartDatePicker.SelectedDate.Value.Date;
            var end = EndDatePicker.SelectedDate.Value.Date;
            if (start > end)
            {
                ShowWarning("开始日期不能晚于结束日期。");
                return;
            }

            try
            {
                var dialog = new SaveFileDialog
                {
                    Title = "导出专注记录",
                    Filter = "Markdown 文件 (*.md)|*.md|所有文件 (*.*)|*.*",
                    DefaultExt = ".md",
                    AddExtension = true,
                    FileName = "专注记录_" +
                        start.ToString("yyyyMMdd", CultureInfo.InvariantCulture) +
                        "-" +
                        end.ToString("yyyyMMdd", CultureInfo.InvariantCulture) +
                        ".md"
                };
                if (dialog.ShowDialog(this) != true) return;

                var days = _service.GetRange(start, end);
                var markdown = FocusJournalFormatter.BuildMarkdown(days);
                File.WriteAllText(
                    dialog.FileName,
                    markdown,
                    new UTF8Encoding(false));
                MessageBox.Show(
                    this,
                    "Markdown 已导出到：\n" + dialog.FileName,
                    "导出完成",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
                DialogResult = true;
                Close();
            }
            catch (Exception exception)
            {
                ShowWarning("暂时无法导出：\n" + exception.Message);
            }
        }

        private void ShowWarning(string message)
        {
            MessageBox.Show(
                this,
                message,
                "导出专注记录",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }

        private void Cancel_Click(object sender, RoutedEventArgs e)
        {
            DialogResult = false;
            Close();
        }
    }
}
