using System;
using System.Collections.Generic;
using System.IO;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using DesktopPet.Models;

namespace DesktopPet.Services
{
    public sealed class SpriteAnimator : IDisposable
    {
        private readonly Image _image;
        private readonly DispatcherTimer _frameTimer;
        private readonly DispatcherTimer _revertTimer;
        private readonly Dictionary<string, BitmapImage> _cache = new Dictionary<string, BitmapImage>();
        private string[] _frames = { "idle-1.png", "idle-2.png" };
        private int _frameIndex;

        public PetState CurrentState { get; private set; } = PetState.Idle;

        public SpriteAnimator(Image image)
        {
            _image = image;
            _frameTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(650) };
            _frameTimer.Tick += (s, e) => ShowNextFrame();
            _revertTimer = new DispatcherTimer();
            _revertTimer.Tick += (s, e) =>
            {
                _revertTimer.Stop();
                SetState(PetState.Idle);
            };
            SetState(PetState.Idle);
            _frameTimer.Start();
        }

        public void SetState(PetState state, TimeSpan? revertAfter = null)
        {
            CurrentState = state;
            _frameIndex = 0;
            _revertTimer.Stop();

            switch (state)
            {
                case PetState.Blinking:
                    _frames = new[] { "blink.png", "idle-1.png" };
                    break;
                case PetState.Happy:
                    _frames = new[] { "happy.png", "idle-2.png", "happy.png" };
                    break;
                case PetState.Working:
                    _frames = new[] { "working.png", "idle-2.png" };
                    break;
                case PetState.Question:
                    _frames = new[] { "question.png", "idle-1.png" };
                    break;
                case PetState.Success:
                    _frames = new[] { "success.png", "happy.png" };
                    break;
                case PetState.Error:
                    _frames = new[] { "error.png", "idle-1.png" };
                    break;
                case PetState.Sleeping:
                    _frames = new[] { "sleeping.png" };
                    break;
                case PetState.Reminder:
                    _frames = new[] { "reminder.png", "wave.png" };
                    break;
                case PetState.Waving:
                    _frames = new[] { "wave.png", "idle-2.png" };
                    break;
                case PetState.HeartPulse:
                    _frames = new[] { "heart.png", "idle-1.png", "heart.png" };
                    break;
                default:
                    _frames = new[] { "idle-1.png", "idle-2.png" };
                    break;
            }

            ShowFrame(_frames[0]);
            if (revertAfter.HasValue)
            {
                _revertTimer.Interval = revertAfter.Value;
                _revertTimer.Start();
            }
        }

        private void ShowNextFrame()
        {
            if (_frames.Length == 0) return;
            _frameIndex = (_frameIndex + 1) % _frames.Length;
            ShowFrame(_frames[_frameIndex]);
        }

        private void ShowFrame(string filename)
        {
            BitmapImage bitmap;
            if (!_cache.TryGetValue(filename, out bitmap))
            {
                var path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Assets", "Sprites", filename);
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
            _revertTimer.Stop();
        }
    }
}
