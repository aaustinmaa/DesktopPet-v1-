using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace DesktopPet.Services
{
    public sealed class HammerAnimator : IDisposable
    {
        private static readonly string[] Frames =
        {
            "hammer-v2-01.png",
            "hammer-v2-02.png",
            "hammer-v2-03.png",
            "hammer-v2-04.png",
            "hammer-v2-05.png",
            "hammer-v2-06.png",
            "hammer-v2-07.png",
            "hammer-v2-08.png",
            "hammer-v2-09.png"
        };

        private readonly Image _image;
        private readonly DispatcherTimer _frameTimer;
        private readonly Dictionary<string, BitmapImage> _cache =
            new Dictionary<string, BitmapImage>();
        private int _frameIndex;

        public event EventHandler Completed;

        public HammerAnimator(Image image)
        {
            _image = image;
            _frameTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromMilliseconds(62)
            };
            _frameTimer.Tick += FrameTimer_Tick;
        }

        public void Play()
        {
            _frameTimer.Stop();
            _frameIndex = 0;
            ShowFrame(Frames[_frameIndex]);
            _image.Opacity = 1;
            _image.Visibility = Visibility.Visible;
            _frameTimer.Start();
        }

        private void FrameTimer_Tick(object sender, EventArgs e)
        {
            _frameIndex++;
            if (_frameIndex >= Frames.Length)
            {
                _frameTimer.Stop();
                _image.Visibility = Visibility.Collapsed;
                Completed?.Invoke(this, EventArgs.Empty);
                return;
            }
            ShowFrame(Frames[_frameIndex]);
        }

        private void ShowFrame(string filename)
        {
            BitmapImage bitmap;
            if (!_cache.TryGetValue(filename, out bitmap))
            {
                var path = Path.Combine(
                    AppDomain.CurrentDomain.BaseDirectory,
                    "Assets",
                    "Sprites",
                    filename);
                bitmap = new BitmapImage();
                bitmap.BeginInit();
                bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.UriSource = new Uri(path, UriKind.Absolute);
                bitmap.EndInit();
                bitmap.Freeze();
                _cache[filename] = bitmap;
            }
            _image.Source = bitmap;
        }

        public void Dispose()
        {
            _frameTimer.Stop();
            _image.Visibility = Visibility.Collapsed;
        }
    }
}
