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
        private readonly Func<PetState> _baseStateResolver;
        private readonly DispatcherTimer _frameTimer;
        private readonly DispatcherTimer _revertTimer;
        private readonly Dictionary<string, BitmapImage> _cache = new Dictionary<string, BitmapImage>();
        private string[] _frames = IdleFrames;
        private int _frameIndex;
        private bool _loopFrames = true;
        private bool _returnToBaseWhenFinished;
        private bool _returnToBaseAtLoopEnd;

        private static readonly string[] IdleFrames =
        {
            "idle-open-close-v5-01.png",
            "idle-open-close-v5-02.png",
            "idle-open-close-v5-03.png",
            "idle-open-close-v5-04.png",
            "idle-open-close-v5-05.png",
            "idle-open-close-v5-06.png",
            "idle-open-close-v5-07.png",
            "idle-open-close-v5-08.png",
            "idle-open-close-v5-09.png",
            "idle-open-close-v5-10.png",
            "idle-open-close-v5-11.png",
            "idle-open-close-v5-12.png",
            "idle-open-close-v5-13.png",
            "idle-open-close-v5-14.png",
            "idle-open-close-v5-15.png",
            "idle-open-close-v5-16.png"
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

        private static readonly string[] WorkingFrames =
        {
            "working-float-v3-01.png",
            "working-float-v3-02.png",
            "working-float-v3-03.png",
            "working-float-v3-04.png",
            "working-float-v3-05.png",
            "working-float-v3-06.png",
            "working-float-v3-07.png",
            "working-float-v3-08.png",
            "working-float-v3-09.png",
            "working-float-v3-10.png",
            "working-float-v3-11.png",
            "working-float-v3-12.png",
            "working-float-v3-13.png",
            "working-float-v3-14.png",
            "working-float-v3-15.png",
            "working-float-v3-16.png",
            "working-float-v3-15.png",
            "working-float-v3-14.png",
            "working-float-v3-13.png",
            "working-float-v3-12.png",
            "working-float-v3-11.png",
            "working-float-v3-10.png",
            "working-float-v3-09.png",
            "working-float-v3-08.png",
            "working-float-v3-07.png",
            "working-float-v3-06.png",
            "working-float-v3-05.png",
            "working-float-v3-04.png",
            "working-float-v3-03.png",
            "working-float-v3-02.png"
        };

        private static readonly string[] SuccessFrames =
        {
            "success-v2-01.png",
            "success-v2-02.png",
            "success-v2-03.png",
            "success-v2-04.png",
            "success-v2-05.png",
            "success-v2-06.png",
            "success-v2-07.png",
            "success-v2-08.png",
            "success-v2-09.png",
            "success-v2-10.png",
            "success-v2-11.png",
            "success-v2-12.png",
            "success-v2-13.png",
            "success-v2-14.png",
            "success-v2-15.png",
            "success-v2-16.png"
        };

        private static readonly string[] ErrorFrames =
        {
            "error-v2-01.png",
            "error-v2-02.png",
            "error-v2-03.png",
            "error-v2-04.png",
            "error-v2-05.png",
            "error-v2-06.png",
            "error-v2-07.png",
            "error-v2-08.png",
            "error-v2-09.png",
            "error-v2-10.png",
            "error-v2-11.png",
            "error-v2-12.png",
            "error-v2-13.png",
            "error-v2-14.png",
            "error-v2-15.png",
            "error-v2-16.png"
        };

        private static readonly string[] ReminderFrames =
        {
            "reminder-v2-01.png",
            "reminder-v2-02.png",
            "reminder-v2-03.png",
            "reminder-v2-04.png",
            "reminder-v2-05.png",
            "reminder-v2-06.png",
            "reminder-v2-07.png",
            "reminder-v2-08.png",
            "reminder-v2-09.png",
            "reminder-v2-10.png",
            "reminder-v2-11.png",
            "reminder-v2-12.png",
            "reminder-v2-13.png",
            "reminder-v2-14.png",
            "reminder-v2-15.png",
            "reminder-v2-16.png"
        };

        private static readonly string[] HitFrames =
        {
            "idle-hit-v1-01.png",
            "idle-hit-v1-02.png",
            "idle-hit-v1-03.png",
            "idle-hit-v1-04.png",
            "idle-hit-v1-05.png",
            "idle-hit-v1-06.png",
            "idle-hit-v1-07.png",
            "idle-hit-v1-08.png",
            "idle-hit-v1-09.png",
            "idle-hit-v1-10.png",
            "idle-hit-v1-11.png",
            "idle-hit-v1-12.png",
            "idle-hit-v1-13.png",
            "idle-hit-v1-14.png",
            "idle-hit-v1-15.png",
            "idle-hit-v1-16.png"
        };

        public PetState CurrentState { get; private set; } = PetState.Idle;

        public SpriteAnimator(
            Image image,
            FrameworkElement sleepZzzLayer,
            Image[] sleepZzzImages,
            ScaleTransform[] sleepZzzScales,
            TranslateTransform[] sleepZzzTranslations,
            Func<PetState> baseStateResolver)
        {
            _image = image;
            _sleepZzzLayer = sleepZzzLayer;
            _sleepZzzImages = sleepZzzImages;
            _sleepZzzScales = sleepZzzScales;
            _sleepZzzTranslations = sleepZzzTranslations;
            _baseStateResolver = baseStateResolver;
            _sleepZzzImages[0].Source = LoadImage("sleeping-z-small.png");
            _sleepZzzImages[1].Source = LoadImage("sleeping-z-medium.png");
            _sleepZzzImages[2].Source = LoadImage("sleeping-z-large.png");
            _frameTimer = new DispatcherTimer();
            _frameTimer.Tick += (s, e) => ShowNextFrame();
            _revertTimer = new DispatcherTimer();
            _revertTimer.Tick += (s, e) =>
            {
                _revertTimer.Stop();
                if (_loopFrames && _frames.Length > 1)
                {
                    _returnToBaseAtLoopEnd = true;
                    return;
                }
                RestoreBaseState();
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
            _returnToBaseWhenFinished = false;
            _returnToBaseAtLoopEnd = false;
            StopSleepZzzAnimation();

            switch (state)
            {
                case PetState.Blinking:
                    _frames = BlinkFrames;
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(165);
                    _loopFrames = false;
                    _returnToBaseWhenFinished = true;
                    revertAfter = null;
                    break;
                case PetState.Happy:
                    _frames = new[] { "happy.png" };
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(150);
                    break;
                case PetState.Working:
                    _frames = WorkingFrames;
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(50);
                    break;
                case PetState.Question:
                    _frames = new[] { "question.png" };
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(150);
                    break;
                case PetState.Success:
                    _frames = SuccessFrames;
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(95);
                    break;
                case PetState.Error:
                    _frames = ErrorFrames;
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(125);
                    break;
                case PetState.Sleeping:
                    _frames = new[] { "sleeping-base.png" };
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(150);
                    break;
                case PetState.Reminder:
                    _frames = ReminderFrames;
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(90);
                    break;
                case PetState.Waving:
                    _frames = WaveFrames;
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(105);
                    break;
                case PetState.HeartPulse:
                    _frames = HeartFrames;
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(115);
                    _loopFrames = false;
                    _returnToBaseWhenFinished = true;
                    revertAfter = null;
                    break;
                case PetState.Hit:
                    _frames = HitFrames;
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(75);
                    _loopFrames = false;
                    _returnToBaseWhenFinished = true;
                    revertAfter = null;
                    break;
                default:
                    _frames = IdleFrames;
                    _frameTimer.Interval = TimeSpan.FromMilliseconds(170);
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
                    if (_returnToBaseAtLoopEnd)
                    {
                        _frameTimer.Stop();
                        RestoreBaseState();
                        return;
                    }
                    _frameIndex = 0;
                }
                else
                {
                    _frameTimer.Stop();
                    if (_returnToBaseWhenFinished)
                        RestoreBaseState();
                    return;
                }
            }
            ShowFrame(_frames[_frameIndex]);
        }

        private void RestoreBaseState()
        {
            SetState(_baseStateResolver == null
                ? PetState.Idle
                : _baseStateResolver());
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
