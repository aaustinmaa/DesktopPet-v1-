using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Windows;
using System.Windows.Threading;

namespace DesktopPet.Services
{
    internal sealed class WanderController : IDisposable
    {
        private const double BottomBandStart = 0.70;
        private const double RightBandStart = 0.76;
        private const double MinimumMoveSeconds = 3.0;
        private const double MaximumMoveSeconds = 10.0;

        private readonly Window _window;
        private readonly Func<bool> _canMove;
        private readonly Random _random;
        private readonly DispatcherTimer _decisionTimer;
        private readonly DispatcherTimer _movementTimer;
        private readonly Stopwatch _movementClock = new Stopwatch();
        private readonly Queue<RouteTarget> _pendingTargets =
            new Queue<RouteTarget>();
        private readonly List<Point> _routeNodes = new List<Point>();

        private Rect _lockedWorkingArea;
        private Point _segmentStart;
        private Point _segmentControl;
        private Point _segmentEnd;
        private double _segmentDurationSeconds;
        private int _currentRouteIndex = -1;
        private int _activeTargetIndex = -1;
        private bool _enabled;
        private bool _interactionPaused;
        private bool _disposed;

        public WanderController(Window window, Func<bool> canMove, Random random)
        {
            _window = window ?? throw new ArgumentNullException(nameof(window));
            _canMove = canMove ?? throw new ArgumentNullException(nameof(canMove));
            _random = random ?? throw new ArgumentNullException(nameof(random));

            _decisionTimer = new DispatcherTimer(DispatcherPriority.Background);
            _decisionTimer.Tick += DecisionTimer_Tick;

            _movementTimer = new DispatcherTimer(
                TimeSpan.FromMilliseconds(33),
                DispatcherPriority.Render,
                MovementTimer_Tick,
                window.Dispatcher);
            _movementTimer.Stop();
        }

        public void SetEnabled(bool enabled)
        {
            if (_disposed || _enabled == enabled) return;

            _enabled = enabled;
            if (!enabled)
            {
                _decisionTimer.Stop();
                CancelMovement();
                return;
            }

            LockToCurrentMonitor();
            if (!_interactionPaused)
                ScheduleQuietIdle();
        }

        public void PauseForUserInteraction()
        {
            if (_disposed) return;
            _interactionPaused = true;
            _decisionTimer.Stop();
            CancelMovement();
        }

        public void ResumeAfterUserInteraction(bool lockToCurrentMonitor)
        {
            if (_disposed) return;

            if (lockToCurrentMonitor || _routeNodes.Count == 0)
                LockToCurrentMonitor();
            else
                _currentRouteIndex = FindClosestRouteIndex(CurrentPosition);

            _interactionPaused = false;
            if (_enabled)
                Schedule(TimeSpan.FromSeconds(_random.Next(10, 21)));
        }

        public void RefreshWindowBounds()
        {
            if (_disposed || _lockedWorkingArea.IsEmpty) return;
            BuildRoute();
            _currentRouteIndex = FindClosestRouteIndex(CurrentPosition);
        }

        private Point CurrentPosition => new Point(_window.Left, _window.Top);

        private void LockToCurrentMonitor()
        {
            _lockedWorkingArea = DisplayService.GetWorkingAreaForWindow(_window);
            BuildRoute();
            _currentRouteIndex = FindClosestRouteIndex(CurrentPosition);
        }

        private void BuildRoute()
        {
            _routeNodes.Clear();
            if (_lockedWorkingArea.IsEmpty) return;

            var minimumLeft = _lockedWorkingArea.Left;
            var maximumLeft = Math.Max(
                minimumLeft,
                _lockedWorkingArea.Right - _window.Width);
            var maximumTop = Math.Max(
                _lockedWorkingArea.Top,
                _lockedWorkingArea.Bottom - _window.Height);
            var preferredMinimumTop = _lockedWorkingArea.Top + 90;
            var minimumTop = Math.Min(preferredMinimumTop, maximumTop);
            var usableWidth = Math.Max(1, maximumLeft - minimumLeft);
            var usableHeight = Math.Max(1, maximumTop - minimumTop);

            var bottomX = new[] { 0.08, 0.24, 0.40, 0.56, 0.72, 0.88 };
            var bottomY = new[] { 0.86, 0.89, 0.85, 0.89, 0.86, 0.90 };
            for (var index = 0; index < bottomX.Length; index++)
            {
                _routeNodes.Add(new Point(
                    minimumLeft + usableWidth * bottomX[index],
                    minimumTop + usableHeight * bottomY[index]));
            }

            var rightX = new[] { 0.89, 0.86, 0.90, 0.87 };
            var rightY = new[] { 0.72, 0.54, 0.36, 0.18 };
            for (var index = 0; index < rightX.Length; index++)
            {
                _routeNodes.Add(new Point(
                    minimumLeft + usableWidth * rightX[index],
                    minimumTop + usableHeight * rightY[index]));
            }
        }

        private void DecisionTimer_Tick(object sender, EventArgs e)
        {
            _decisionTimer.Stop();
            if (!_enabled || _interactionPaused || _disposed) return;

            if (!_canMove())
            {
                ScheduleQuietIdle();
                return;
            }

            if (_routeNodes.Count == 0)
                LockToCurrentMonitor();
            if (_routeNodes.Count == 0)
            {
                ScheduleQuietIdle();
                return;
            }

            var current = CurrentPosition;
            if (!IsInsideWanderBands(current))
            {
                var entry = CreateRouteEntry(current);
                StartMovement(new[]
                {
                    new RouteTarget(entry, FindClosestRouteIndex(entry))
                });
                return;
            }

            var decision = _random.NextDouble();
            if (decision < 0.45)
            {
                ScheduleQuietIdle();
                return;
            }

            _currentRouteIndex = FindClosestRouteIndex(current);
            var stepCount = decision < 0.85 ? 1 : 2;
            var direction = ChooseDirection(_currentRouteIndex);
            var targets = new List<RouteTarget>();
            var index = _currentRouteIndex;

            for (var step = 0; step < stepCount; step++)
            {
                var next = index + direction;
                if (next < 0 || next >= _routeNodes.Count)
                {
                    direction = -direction;
                    next = index + direction;
                }
                if (next < 0 || next >= _routeNodes.Count) break;

                index = next;
                targets.Add(new RouteTarget(
                    AddNodeJitter(_routeNodes[index], index),
                    index));
            }

            if (targets.Count == 0)
            {
                ScheduleQuietIdle();
                return;
            }

            StartMovement(targets);
        }

        private int ChooseDirection(int index)
        {
            if (index <= 0) return 1;
            if (index >= _routeNodes.Count - 1) return -1;
            return _random.NextDouble() < 0.5 ? -1 : 1;
        }

        private bool IsInsideWanderBands(Point point)
        {
            var maximumLeft = Math.Max(
                _lockedWorkingArea.Left,
                _lockedWorkingArea.Right - _window.Width);
            var maximumTop = Math.Max(
                _lockedWorkingArea.Top,
                _lockedWorkingArea.Bottom - _window.Height);
            var width = Math.Max(1, maximumLeft - _lockedWorkingArea.Left);
            var height = Math.Max(1, maximumTop - _lockedWorkingArea.Top);
            var bottomThreshold =
                _lockedWorkingArea.Top + height * BottomBandStart;
            var rightThreshold =
                _lockedWorkingArea.Left + width * RightBandStart;

            return point.Y >= bottomThreshold || point.X >= rightThreshold;
        }

        private Point CreateRouteEntry(Point current)
        {
            var maximumLeft = Math.Max(
                _lockedWorkingArea.Left,
                _lockedWorkingArea.Right - _window.Width);
            var maximumTop = Math.Max(
                _lockedWorkingArea.Top,
                _lockedWorkingArea.Bottom - _window.Height);
            var minimumTop = Math.Min(
                _lockedWorkingArea.Top + 90,
                maximumTop);
            var usableWidth = Math.Max(
                1,
                maximumLeft - _lockedWorkingArea.Left);
            var usableHeight = Math.Max(1, maximumTop - minimumTop);
            var bottomY = minimumTop + usableHeight * 0.87;
            var rightX = _lockedWorkingArea.Left + usableWidth * 0.88;
            var distanceToBottom = Math.Abs(bottomY - current.Y);
            var distanceToRight = Math.Abs(rightX - current.X);

            if (distanceToBottom <= distanceToRight)
                return ClampToLockedArea(new Point(current.X, bottomY));

            return ClampToLockedArea(new Point(rightX, current.Y));
        }

        private Point AddNodeJitter(Point node, int routeIndex)
        {
            var isBottomNode = routeIndex <= 5;
            var xJitter = isBottomNode
                ? _random.Next(-18, 19)
                : _random.Next(-12, 13);
            var yJitter = isBottomNode
                ? _random.Next(-12, 13)
                : _random.Next(-18, 19);
            return ClampToLockedArea(
                new Point(node.X + xJitter, node.Y + yJitter));
        }

        private void StartMovement(IEnumerable<RouteTarget> targets)
        {
            _pendingTargets.Clear();
            foreach (var target in targets)
                _pendingTargets.Enqueue(target);
            StartNextSegment();
        }

        private void StartNextSegment()
        {
            if (!_enabled || _interactionPaused || !_canMove())
            {
                CancelMovement();
                if (_enabled && !_interactionPaused)
                    ScheduleQuietIdle();
                return;
            }

            if (_pendingTargets.Count == 0)
            {
                _movementTimer.Stop();
                _movementClock.Reset();
                ScheduleQuietIdle();
                return;
            }

            var target = _pendingTargets.Dequeue();
            _activeTargetIndex = target.RouteIndex;
            _segmentStart = CurrentPosition;
            _segmentEnd = ClampToLockedArea(target.Position);
            _segmentControl = CreateControlPoint(_segmentStart, _segmentEnd);

            var distance = Distance(_segmentStart, _segmentEnd);
            var speed = 35 + _random.NextDouble() * 20;
            _segmentDurationSeconds = Math.Max(
                MinimumMoveSeconds,
                Math.Min(MaximumMoveSeconds, distance / speed));

            _movementClock.Restart();
            _movementTimer.Start();
        }

        private Point CreateControlPoint(Point start, Point end)
        {
            var midpoint = new Point(
                (start.X + end.X) / 2,
                (start.Y + end.Y) / 2);
            var offset = _random.Next(15, 31) *
                         (_random.NextDouble() < 0.5 ? -1 : 1);

            if (Math.Abs(end.X - start.X) >= Math.Abs(end.Y - start.Y))
                midpoint.Y += offset;
            else
                midpoint.X += offset;

            return ClampToLockedArea(midpoint);
        }

        private void MovementTimer_Tick(object sender, EventArgs e)
        {
            if (!_enabled || _interactionPaused || !_canMove())
            {
                CancelMovement();
                if (_enabled && !_interactionPaused)
                    ScheduleQuietIdle();
                return;
            }

            var progress = _segmentDurationSeconds <= 0
                ? 1
                : _movementClock.Elapsed.TotalSeconds / _segmentDurationSeconds;
            if (progress >= 1)
            {
                _window.Left = _segmentEnd.X;
                _window.Top = _segmentEnd.Y;
                _currentRouteIndex = _activeTargetIndex;
                _movementTimer.Stop();
                _movementClock.Reset();
                StartNextSegment();
                return;
            }

            var eased = SmootherStep(progress);
            var position = GetBezierPoint(
                _segmentStart,
                _segmentControl,
                _segmentEnd,
                eased);
            position = ClampToLockedArea(position);
            _window.Left = position.X;
            _window.Top = position.Y;
        }

        private Point ClampToLockedArea(Point point)
        {
            var maximumLeft = Math.Max(
                _lockedWorkingArea.Left,
                _lockedWorkingArea.Right - _window.Width);
            var maximumTop = Math.Max(
                _lockedWorkingArea.Top,
                _lockedWorkingArea.Bottom - _window.Height);
            var preferredMinimumTop = _lockedWorkingArea.Top + 90;
            var minimumTop = Math.Min(preferredMinimumTop, maximumTop);

            return new Point(
                Math.Max(
                    _lockedWorkingArea.Left,
                    Math.Min(point.X, maximumLeft)),
                Math.Max(minimumTop, Math.Min(point.Y, maximumTop)));
        }

        private int FindClosestRouteIndex(Point point)
        {
            if (_routeNodes.Count == 0) return -1;

            var bestIndex = 0;
            var bestDistance = double.MaxValue;
            for (var index = 0; index < _routeNodes.Count; index++)
            {
                var distance = Distance(point, _routeNodes[index]);
                if (distance >= bestDistance) continue;
                bestDistance = distance;
                bestIndex = index;
            }
            return bestIndex;
        }

        private void ScheduleQuietIdle()
        {
            var roll = _random.NextDouble();
            int seconds;
            if (roll < 0.70)
                seconds = _random.Next(35, 91);
            else if (roll < 0.95)
                seconds = _random.Next(90, 151);
            else
                seconds = _random.Next(150, 241);
            Schedule(TimeSpan.FromSeconds(seconds));
        }

        private void Schedule(TimeSpan delay)
        {
            if (!_enabled || _interactionPaused || _disposed) return;
            _decisionTimer.Stop();
            _decisionTimer.Interval = delay;
            _decisionTimer.Start();
        }

        private void CancelMovement()
        {
            _movementTimer.Stop();
            _movementClock.Reset();
            _pendingTargets.Clear();
            _activeTargetIndex = -1;
        }

        private static Point GetBezierPoint(
            Point start,
            Point control,
            Point end,
            double progress)
        {
            var inverse = 1 - progress;
            return new Point(
                inverse * inverse * start.X +
                2 * inverse * progress * control.X +
                progress * progress * end.X,
                inverse * inverse * start.Y +
                2 * inverse * progress * control.Y +
                progress * progress * end.Y);
        }

        private static double SmootherStep(double progress)
        {
            return progress * progress * progress *
                   (progress * (progress * 6 - 15) + 10);
        }

        private static double Distance(Point first, Point second)
        {
            var deltaX = second.X - first.X;
            var deltaY = second.Y - first.Y;
            return Math.Sqrt(deltaX * deltaX + deltaY * deltaY);
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _decisionTimer.Stop();
            _decisionTimer.Tick -= DecisionTimer_Tick;
            _movementTimer.Stop();
            _movementTimer.Tick -= MovementTimer_Tick;
            _movementClock.Stop();
            _pendingTargets.Clear();
            _routeNodes.Clear();
        }

        private sealed class RouteTarget
        {
            public RouteTarget(Point position, int routeIndex)
            {
                Position = position;
                RouteIndex = routeIndex;
            }

            public Point Position { get; }
            public int RouteIndex { get; }
        }
    }
}
