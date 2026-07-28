using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Forms = System.Windows.Forms;

namespace DesktopPet.Services
{
    internal static class DisplayService
    {
        public static Rect GetWorkingAreaForWindow(Window window)
        {
            var handle = window == null ? IntPtr.Zero : new WindowInteropHelper(window).Handle;
            var screen = handle == IntPtr.Zero
                ? Forms.Screen.PrimaryScreen
                : Forms.Screen.FromHandle(handle);
            return ToDeviceIndependentRect(window, screen.WorkingArea);
        }

        public static Rect GetPrimaryWorkingArea(Window window)
        {
            return ToDeviceIndependentRect(window, Forms.Screen.PrimaryScreen.WorkingArea);
        }

        public static bool IsPositionVisible(
            Window window,
            double left,
            double top,
            double width,
            double height)
        {
            if (double.IsNaN(left) || double.IsNaN(top) ||
                double.IsInfinity(left) || double.IsInfinity(top))
                return false;

            var requiredWidth = Math.Min(40, Math.Max(1, width));
            var requiredHeight = Math.Min(40, Math.Max(1, height));
            var candidate = new Rect(left, top, Math.Max(1, width), Math.Max(1, height));

            foreach (var area in GetAllMonitorBounds(window))
            {
                var intersection = Rect.Intersect(candidate, area);
                if (!intersection.IsEmpty &&
                    intersection.Width >= requiredWidth &&
                    intersection.Height >= requiredHeight)
                    return true;
            }
            return false;
        }

        private static IEnumerable<Rect> GetAllMonitorBounds(Window window)
        {
            foreach (var screen in Forms.Screen.AllScreens)
                yield return ToDeviceIndependentRect(window, screen.Bounds);
        }

        private static Rect ToDeviceIndependentRect(Window window, Rectangle rectangle)
        {
            var transform = GetTransformFromDevice(window);
            var topLeft = transform.Transform(
                new System.Windows.Point(rectangle.Left, rectangle.Top));
            var bottomRight = transform.Transform(
                new System.Windows.Point(rectangle.Right, rectangle.Bottom));
            return new Rect(topLeft, bottomRight);
        }

        private static Matrix GetTransformFromDevice(Window window)
        {
            var source = window == null
                ? null
                : PresentationSource.FromVisual(window) as HwndSource;
            if (source != null && source.CompositionTarget != null)
                return source.CompositionTarget.TransformFromDevice;

            var primary = Forms.Screen.PrimaryScreen;
            var scaleX = primary.Bounds.Width <= 0
                ? 1.0
                : SystemParameters.PrimaryScreenWidth / primary.Bounds.Width;
            var scaleY = primary.Bounds.Height <= 0
                ? 1.0
                : SystemParameters.PrimaryScreenHeight / primary.Bounds.Height;
            return new Matrix(scaleX, 0, 0, scaleY, 0, 0);
        }
    }
}
