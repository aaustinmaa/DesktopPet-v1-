using System;
using System.Collections.Generic;
using System.IO;
using System.Media;

namespace DesktopPet.Services
{
    public sealed class SoundOption
    {
        public SoundOption(string id, string displayName)
        {
            Id = id;
            DisplayName = displayName;
        }

        public string Id { get; private set; }
        public string DisplayName { get; private set; }
    }

    public sealed class SoundService : IDisposable
    {
        private const int SampleRate = 44100;
        private static readonly IReadOnlyList<SoundOption> OptionsValue =
            new List<SoundOption>
            {
                new SoundOption("gentle", "柔和木琴"),
                new SoundOption("bell", "清亮钟声"),
                new SoundOption("pixel", "像素提示"),
                new SoundOption("classic", "经典铃铃"),
                new SoundOption("silent", "静音")
            }.AsReadOnly();

        private SoundPlayer _player;
        private MemoryStream _stream;

        public static IReadOnlyList<SoundOption> Options
        {
            get { return OptionsValue; }
        }

        public static bool IsValidSoundId(string soundId)
        {
            foreach (var option in OptionsValue)
            {
                if (string.Equals(option.Id, soundId, StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }

        public void PlayFocusStart(string soundId)
        {
            Play(soundId, false);
        }

        public void PlayFocusComplete(string soundId)
        {
            Play(soundId, true);
        }

        private void Play(string soundId, bool isComplete)
        {
            if (string.Equals(soundId, "silent", StringComparison.OrdinalIgnoreCase))
            {
                Stop();
                return;
            }

            if (!IsValidSoundId(soundId))
                soundId = isComplete ? "bell" : "gentle";

            try
            {
                Stop();
                var wave = BuildWave(soundId, isComplete);
                _stream = new MemoryStream(wave, false);
                _player = new SoundPlayer(_stream);
                _player.Load();
                _player.Play();
            }
            catch
            {
                Stop();
                try { SystemSounds.Asterisk.Play(); } catch { }
            }
        }

        private static byte[] BuildWave(string soundId, bool isComplete)
        {
            var tones = CreateTones(soundId, isComplete);
            var sampleCount = 0;
            foreach (var tone in tones)
                sampleCount += MillisecondsToSamples(tone.DurationMs + tone.GapMs);

            using (var output = new MemoryStream())
            using (var writer = new BinaryWriter(output))
            {
                const short channels = 1;
                const short bitsPerSample = 16;
                var dataLength = sampleCount * channels * (bitsPerSample / 8);

                writer.Write(new[] { 'R', 'I', 'F', 'F' });
                writer.Write(36 + dataLength);
                writer.Write(new[] { 'W', 'A', 'V', 'E' });
                writer.Write(new[] { 'f', 'm', 't', ' ' });
                writer.Write(16);
                writer.Write((short)1);
                writer.Write(channels);
                writer.Write(SampleRate);
                writer.Write(SampleRate * channels * (bitsPerSample / 8));
                writer.Write((short)(channels * (bitsPerSample / 8)));
                writer.Write(bitsPerSample);
                writer.Write(new[] { 'd', 'a', 't', 'a' });
                writer.Write(dataLength);

                foreach (var tone in tones)
                    WriteTone(writer, tone);

                writer.Flush();
                return output.ToArray();
            }
        }

        private static List<Tone> CreateTones(string soundId, bool isComplete)
        {
            switch (soundId)
            {
                case "bell":
                    return isComplete
                        ? BellSequence(new[] { 659.25, 880.00, 1046.50 }, 360, 70)
                        : BellSequence(new[] { 659.25, 880.00 }, 300, 55);
                case "pixel":
                    return isComplete
                        ? PixelSequence(new[] { 523.25, 659.25, 783.99, 1046.50 }, 105, 28)
                        : PixelSequence(new[] { 659.25, 880.00 }, 105, 30);
                case "classic":
                    return isComplete
                        ? BellSequence(new[] { 783.99, 783.99, 1046.50, 783.99 }, 240, 75)
                        : BellSequence(new[] { 783.99, 1046.50 }, 220, 85);
                default:
                    return isComplete
                        ? GentleSequence(new[] { 523.25, 659.25, 783.99, 1046.50 }, 230, 50)
                        : GentleSequence(new[] { 523.25, 659.25, 783.99 }, 200, 45);
            }
        }

        private static List<Tone> GentleSequence(double[] notes, int duration, int gap)
        {
            var result = new List<Tone>();
            foreach (var note in notes)
                result.Add(new Tone(note, duration, gap, 0.36, WaveShape.Soft));
            return result;
        }

        private static List<Tone> BellSequence(double[] notes, int duration, int gap)
        {
            var result = new List<Tone>();
            foreach (var note in notes)
                result.Add(new Tone(note, duration, gap, 0.43, WaveShape.Bell));
            return result;
        }

        private static List<Tone> PixelSequence(double[] notes, int duration, int gap)
        {
            var result = new List<Tone>();
            foreach (var note in notes)
                result.Add(new Tone(note, duration, gap, 0.25, WaveShape.Pixel));
            return result;
        }

        private static void WriteTone(BinaryWriter writer, Tone tone)
        {
            var toneSamples = MillisecondsToSamples(tone.DurationMs);
            var gapSamples = MillisecondsToSamples(tone.GapMs);
            var attackSamples = Math.Max(1, MillisecondsToSamples(
                tone.Shape == WaveShape.Pixel ? 3 : 9));

            for (var i = 0; i < toneSamples; i++)
            {
                var time = (double)i / SampleRate;
                var phase = 2.0 * Math.PI * tone.Frequency * time;
                var attack = Math.Min(1.0, (double)i / attackSamples);
                var progress = (double)i / Math.Max(1, toneSamples - 1);
                var release = Math.Pow(1.0 - progress, tone.Shape == WaveShape.Bell ? 1.8 : 0.75);
                var sample = CreateSample(phase, tone.Shape) * attack * release * tone.Volume;
                writer.Write((short)(Math.Max(-1.0, Math.Min(1.0, sample)) * short.MaxValue));
            }

            for (var i = 0; i < gapSamples; i++)
                writer.Write((short)0);
        }

        private static double CreateSample(double phase, WaveShape shape)
        {
            if (shape == WaveShape.Pixel)
                return Math.Sin(phase) >= 0 ? 0.78 : -0.78;
            if (shape == WaveShape.Bell)
                return Math.Sin(phase) * 0.72 +
                       Math.Sin(phase * 2.01) * 0.19 +
                       Math.Sin(phase * 3.98) * 0.09;
            return Math.Sin(phase) * 0.82 + Math.Sin(phase * 2.0) * 0.12;
        }

        private static int MillisecondsToSamples(int milliseconds)
        {
            return (int)Math.Round(SampleRate * milliseconds / 1000.0);
        }

        private void Stop()
        {
            if (_player != null)
            {
                try { _player.Stop(); } catch { }
                _player.Dispose();
                _player = null;
            }
            if (_stream != null)
            {
                _stream.Dispose();
                _stream = null;
            }
        }

        public void Dispose()
        {
            Stop();
        }

        private enum WaveShape
        {
            Soft,
            Bell,
            Pixel
        }

        private sealed class Tone
        {
            public Tone(double frequency, int durationMs, int gapMs, double volume, WaveShape shape)
            {
                Frequency = frequency;
                DurationMs = durationMs;
                GapMs = gapMs;
                Volume = volume;
                Shape = shape;
            }

            public double Frequency { get; private set; }
            public int DurationMs { get; private set; }
            public int GapMs { get; private set; }
            public double Volume { get; private set; }
            public WaveShape Shape { get; private set; }
        }
    }
}
