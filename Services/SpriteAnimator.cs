using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using DesktopPet.Models;

namespace DesktopPet.Services
{
    public sealed class SpriteAnimator : IDisposable
    {
        private readonly Image _image;
        private readonly FrameworkElement _sleepZzzLayer;
        private readonly Image[] _sleepZzzImages;
        private readonly ScaleTransform[] _sleepZzzScales;
        private readonly TranslateTransform[] _sleepZzzTranslations;
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

        private static readonly string[] BlinkFrames =
        {
            "blink-v2-01.png",
            "blink-v2-02.png",
            "blink-v2-03.png",
            "blink-v2-04.png",
            "blink-v2-05.png",
            "blink-v2-06.png",
            "blink-v2-07.png",
            "blink-v2-08.png"
        };

        private static readonly string[] HeartFrames =
        {
            "heart-lift-v3-01.png",
            "heart-lift-v3-02.png",
            "heart-lift-v3-03.png",
            "heart-lift-v3-04.png",
            "heart-lift-v3-05.png",
            "heart-lift-v3-06.png",
            "heart-lift-v3-07.png",
            "heart-lift-v3-08.png",
            "heart-lift-v3-07.png",
            "heart-lift-v3-06.png",
            "heart-lift-v3-05.png",
            "heart-lift-v3-04.png",
            "heart-lift-v3-03.png",
            "heart-lift-v3-02.png",
            "heart-lift-v3-01.png"
        };

        public PetState CurrentState { get; private set; } = PetState.Idle;

        public SpriteAnimator(
            Image image,
            FrameworkElement sleepZzzLayer,
            Image[] sleepZzzImages,
            ScaleTransform[] sleepZzzScales,
            TranslateTransform[] sleepZzzTranslations)
        {
            _image = image;
            _sleepZzzLayer = sleepZzzLayer;
            _sleepZzzImages = sleepZzzImages;
            _sleepZzzScales = sleepZzzScales;
            _sleepZzzTranslations = sleepZzzTranslations;
            _sleepZzzImages[0].Source = LoadImage("sleeping-z-small.png");
            _sleepZzzImages[1].Source = LoadImage("sleeping-z-medium.png");
            _sleepZzzImages[2].Source = LoadImage("sleeping-z-large.png");
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
            StopSleepZzzAnimation();

            switch (state)
            {
                case PetState.Blinking:
                    _frames = BlinkFrames;
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(165);
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
                    _frames = new[] { "sleeping-base.png" };
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
                    _frames = HeartFrames;
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(115);
                    _loopFrames = false;
                    _returnToIdleWhenFinished = true;
                    revertAfter = null;
                    break;
                default:
                    _frames = IdleFrames;
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(190);
                    break;
            }

            ShowFrame(_frames[0]);
            if (state == PetState.Sleeping)
                StartSleepZzzAnimation();
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
            _image.Source = LoadImage(filename);
        }

        private BitmapImage LoadImage(string filename)
        {
            BitmapImage bitmap;
            if (_cache.TryGetValue(filename, out bitmap))
                return bitmap;

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
            return bitmap;
        }

        private void StartSleepZzzAnimation()
        {
            _sleepZzzLayer.Visibility = Visibility.Visible;
            StartSleepZAnimation(
                2, 0, 0.064, 0.36, 0.36, 0.396,
                0.43, 1, -51, 56.5, 0, 0);
            StartSleepZAnimation(
                1, 0.18, 0.244, 0.54, 0.54, 0.576,
                0.54, 1.23, -22, 16, 29, -40.5);
            StartSleepZAnimation(
                0, 0.36, 0.424, 0.72, 0.72,
                0.8,
                1, 2.29, 0, 0, 51, -56.5);
        }

        private void StartSleepZAnimation(
            int index,
            double appearAt,
            double fullyVisibleAt,
            double arriveAt,
            double fadeAt,
            double goneAt,
            double startScale,
            double endScale,
            double startX,
            double startY,
            double endX,
            double endY)
        {
            var duration = TimeSpan.FromSeconds(10);
            var opacity = new DoubleAnimationUsingKeyFrames
            {
                Duration = duration,
                RepeatBehavior = RepeatBehavior.Forever
            };
            opacity.KeyFrames.Add(new LinearDoubleKeyFrame(
                0,
                KeyTime.FromPercent(0)));
            if (appearAt > 0)
            {
                opacity.KeyFrames.Add(new LinearDoubleKeyFrame(
                    0,
                    KeyTime.FromPercent(appearAt)));
            }
            opacity.KeyFrames.Add(new LinearDoubleKeyFrame(
                1,
                KeyTime.FromPercent(fullyVisibleAt)));
            opacity.KeyFrames.Add(new LinearDoubleKeyFrame(
                1,
                KeyTime.FromPercent(fadeAt)));
            opacity.KeyFrames.Add(new LinearDoubleKeyFrame(
                0,
                KeyTime.FromPercent(goneAt)));
            opacity.KeyFrames.Add(new DiscreteDoubleKeyFrame(
                0,
                KeyTime.FromPercent(1)));

            var scale = new DoubleAnimationUsingKeyFrames
            {
                Duration = duration,
                RepeatBehavior = RepeatBehavior.Forever
            };
            scale.KeyFrames.Add(new LinearDoubleKeyFrame(
                startScale,
                KeyTime.FromPercent(0)));
            if (appearAt > 0)
            {
                scale.KeyFrames.Add(new LinearDoubleKeyFrame(
                    startScale,
                    KeyTime.FromPercent(appearAt)));
            }
            scale.KeyFrames.Add(new LinearDoubleKeyFrame(
                endScale,
                KeyTime.FromPercent(arriveAt)));

            var horizontalMotion = new DoubleAnimationUsingKeyFrames
            {
                Duration = duration,
                RepeatBehavior = RepeatBehavior.Forever
            };
            horizontalMotion.KeyFrames.Add(new LinearDoubleKeyFrame(
                startX,
                KeyTime.FromPercent(0)));
            if (appearAt > 0)
            {
                horizontalMotion.KeyFrames.Add(new LinearDoubleKeyFrame(
                    startX,
                    KeyTime.FromPercent(appearAt)));
            }
            horizontalMotion.KeyFrames.Add(new LinearDoubleKeyFrame(
                endX,
                KeyTime.FromPercent(arriveAt)));

            var verticalMotion = new DoubleAnimationUsingKeyFrames
            {
                Duration = duration,
                RepeatBehavior = RepeatBehavior.Forever
            };
            verticalMotion.KeyFrames.Add(new LinearDoubleKeyFrame(
                startY,
                KeyTime.FromPercent(0)));
            if (appearAt > 0)
            {
                verticalMotion.KeyFrames.Add(new LinearDoubleKeyFrame(
                    startY,
                    KeyTime.FromPercent(appearAt)));
            }
            verticalMotion.KeyFrames.Add(new LinearDoubleKeyFrame(
                endY,
                KeyTime.FromPercent(arriveAt)));

            _sleepZzzImages[index].BeginAnimation(
                UIElement.OpacityProperty,
                opacity);
            _sleepZzzScales[index].BeginAnimation(
                ScaleTransform.ScaleXProperty,
                scale);
            _sleepZzzScales[index].BeginAnimation(
                ScaleTransform.ScaleYProperty,
                scale.Clone());
            _sleepZzzTranslations[index].BeginAnimation(
                TranslateTransform.XProperty,
                horizontalMotion);
            _sleepZzzTranslations[index].BeginAnimation(
                TranslateTransform.YProperty,
                verticalMotion);
        }

        private void StopSleepZzzAnimation()
        {
            for (var index = 0; index < _sleepZzzImages.Length; index++)
            {
                _sleepZzzImages[index].BeginAnimation(
                    UIElement.OpacityProperty,
                    null);
                _sleepZzzScales[index].BeginAnimation(
                    ScaleTransform.ScaleXProperty,
                    null);
                _sleepZzzScales[index].BeginAnimation(
                    ScaleTransform.ScaleYProperty,
                    null);
                _sleepZzzTranslations[index].BeginAnimation(
                    TranslateTransform.XProperty,
                    null);
                _sleepZzzTranslations[index].BeginAnimation(
                    TranslateTransform.YProperty,
                    null);
                _sleepZzzImages[index].Opacity = 0;
                _sleepZzzScales[index].ScaleX = 1;
                _sleepZzzScales[index].ScaleY = 1;
                _sleepZzzTranslations[index].X = 0;
                _sleepZzzTranslations[index].Y = 0;
            }
            _sleepZzzLayer.Visibility = Visibility.Collapsed;
        }

        public void Dispose()
        {
            _frameTimer.Stop();
            _revertTimer.Stop();
            StopSleepZzzAnimation();
        }
    }
}
