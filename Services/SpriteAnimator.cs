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
        private string[] _frames = IdleFrames;
        private int _frameIndex;
        private bool _loopFrames = true;
        private bool _returnToIdleWhenFinished;

        private static readonly string[] IdleFrames =
        {
            "idle-v2-01.png",
            "idle-v2-02.png",
            "idle-v2-03.png",
            "idle-v2-04.png",
            "idle-v2-05.png",
            "idle-v2-06.png",
            "idle-v2-07.png",
            "idle-v2-08.png"
        };

        private static readonly string[] WaveFrames =
        {
            "wave-v2-01.png",
            "wave-v2-02.png",
            "wave-v2-03.png",
            "wave-v2-04.png",
            "wave-v2-05.png",
            "wave-v2-06.png",
            "wave-v2-07.png",
            "wave-v2-08.png"
        };

        public PetState CurrentState { get; private set; } = PetState.Idle;

        public SpriteAnimator(Image image)
        {
            _image = image;
            _frameTimer = new DispatcherTimer();
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
            _frameTimer.Stop();
            _revertTimer.Stop();
            _loopFrames = true;
            _returnToIdleWhenFinished = false;

            switch (state)
            {
                case PetState.Blinking:
                    _frames = new[]
                    {
                        "idle-v2-01.png",
                        "idle-v2-02.png",
                        "blink-v2.png",
                        "blink-v2.png",
                        "blink-v2.png",
                        "blink-v2.png",
                        "idle-v2-02.png",
                        "idle-v2-01.png",
                        "idle-v2-01.png"
                    };
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(145);
                    _loopFrames = false;
                    _returnToIdleWhenFinished = true;
                    revertAfter = null;
                    break;
                case PetState.Happy:
                    _frames = new[] { "happy.png" };
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(150);
                    break;
                case PetState.Working:
                    _frames = new[] { "working.png" };
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(150);
                    break;
                case PetState.Question:
                    _frames = new[] { "question.png" };
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(150);
                    break;
                case PetState.Success:
                    _frames = new[] { "success.png" };
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(150);
                    break;
                case PetState.Error:
                    _frames = new[] { "error.png" };
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(150);
                    break;
                case PetState.Sleeping:
                    _frames = new[] { "sleeping.png" };
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(150);
                    break;
                case PetState.Reminder:
                    _frames = new[] { "reminder.png" };
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(150);
                    break;
                case PetState.Waving:
                    _frames = WaveFrames;
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(105);
                    break;
                case PetState.HeartPulse:
                    _frames = new[] { "heart.png" };
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(150);
                    break;
                default:
                    _frames = IdleFrames;
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(190);
                    break;
            }

            ShowFrame(_frames[0]);
            if (_frames.Length > 1)
                _frameTimer.Start();
            if (revertAfter.HasValue)
            {
                _revertTimer.Interval = revertAfter.Value;
                _revertTimer.Start();
            }
        }

        private void ShowNextFrame()
        {
            if (_frames.Length == 0) return;
            _frameIndex++;
            if (_frameIndex >= _frames.Length)
            {
                if (_loopFrames)
                {
                    _frameIndex = 0;
                }
                else
                {
                    _frameTimer.Stop();
                    if (_returnToIdleWhenFinished)
                        SetState(PetState.Idle);
                    return;
                }
            }
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
