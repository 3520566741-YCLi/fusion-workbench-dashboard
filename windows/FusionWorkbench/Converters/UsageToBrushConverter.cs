using System.Globalization;
using System.Windows.Data;
using System.Windows.Media;

namespace FusionWorkbench.Converters;

/// <summary>
/// Shared brushes for the "glass card" palette. Kept in code so view models can assign them to
/// bindable Brush properties without reaching into the XAML resource dictionary.
/// Colors intentionally match the resources declared in Styles/Theme.xaml.
/// </summary>
public static class Palette
{
    public static readonly Brush Mint = Frozen(Color.FromRgb(0x34, 0xD3, 0x99));
    public static readonly Brush Amber = Frozen(Color.FromRgb(0xF5, 0xB0, 0x41));
    public static readonly Brush Gray = Frozen(Color.FromRgb(0x8A, 0x93, 0xA3));

    private static SolidColorBrush Frozen(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}

/// <summary>
/// Maps a usage value (0..1, or 0..100 when ConverterParameter == "percent") to a brush whose hue
/// walks from green (low usage) through yellow to red (high usage), mirroring the macOS original's
/// usageColor(...) helper (hue 120° -> 0°). A null value yields a neutral gray.
/// </summary>
public sealed class UsageToBrushConverter : IValueConverter
{
    private static readonly SolidColorBrush UnavailableBrush = Frozen(Color.FromRgb(0x6B, 0x72, 0x80));

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        double usage = 0.0;
        bool hasValue = false;

        if (value is double d)
        {
            hasValue = true;
            usage = d;
            if (string.Equals(parameter as string, "percent", StringComparison.OrdinalIgnoreCase))
            {
                usage /= 100.0;
            }
        }
        else if (value is float f)
        {
            hasValue = true;
            usage = f;
            if (string.Equals(parameter as string, "percent", StringComparison.OrdinalIgnoreCase))
            {
                usage /= 100.0f;
            }
        }
        else if (value is int i && string.Equals(parameter as string, "percent", StringComparison.OrdinalIgnoreCase))
        {
            hasValue = true;
            usage = i / 100.0;
        }

        if (!hasValue)
        {
            return UnavailableBrush;
        }

        usage = Math.Clamp(usage, 0.0, 1.0);
        double hue = 120.0 * (1.0 - usage); // 120° green -> 0° red
        return Frozen(HslToRgb(hue, 0.85, 0.55));
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotSupportedException("UsageToBrushConverter is one-way only.");

    private static SolidColorBrush Frozen(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private static Color HslToRgb(double h, double s, double l)
    {
        h = ((h % 360.0) + 360.0) % 360.0 / 360.0;
        double c = (1.0 - Math.Abs(2.0 * l - 1.0)) * s;
        double x = c * (1.0 - Math.Abs((h * 6.0) % 2.0 - 1.0));
        double m = l - c / 2.0;

        double r, g, b;
        if (h < 1.0 / 6.0) { r = c; g = x; b = 0.0; }
        else if (h < 2.0 / 6.0) { r = x; g = c; b = 0.0; }
        else if (h < 3.0 / 6.0) { r = 0.0; g = c; b = x; }
        else if (h < 4.0 / 6.0) { r = 0.0; g = x; b = c; }
        else if (h < 5.0 / 6.0) { r = x; g = 0.0; b = c; }
        else { r = c; g = 0.0; b = x; }

        return Color.FromRgb(
            (byte)Math.Round((r + m) * 255.0),
            (byte)Math.Round((g + m) * 255.0),
            (byte)Math.Round((b + m) * 255.0));
    }
}
