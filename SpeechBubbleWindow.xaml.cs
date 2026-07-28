using System;
using System.Windows;
using System.Windows.Interop;
using DesktopPet.Services;

namespace DesktopPet
{
    public partial class SpeechBubbleWindow : Window
    {
        public SpeechBubbleWindow()
        {
            InitializeComponent();
            SourceInitialized += SpeechBubbleWindow_SourceInitialized;
        }

        public void SetMessage(string message)
        {
            SpeechText.Text = message ?? string.Empty;
        }

        private void SpeechBubbleWindow_SourceInitialized(object sender, EventArgs e)
        {
            var handle = new WindowInteropHelper(this).Handle;
            var style = NativeMethods.GetWindowLong(handle, NativeMethods.GwlExStyle);
            style |= NativeMethods.WsExTransparent |
                     NativeMethods.WsExNoActivate;
            if (!ShowInTaskbar)
                style |= NativeMethods.WsExToolWindow;
            NativeMethods.SetWindowLong(handle, NativeMethods.GwlExStyle, style);
        }
    }
}
