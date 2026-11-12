using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class LaunchCady3D
{
    [STAThread]
    private static void Main()
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string engine = Path.Combine(root, "Tools", "Godot", "Godot_v4.7.2-stable_win64.exe");
        string project = Path.Combine(root, "GodotRebuild");
        if (!File.Exists(engine) || !Directory.Exists(project))
        {
            MessageBox.Show("Не найдены файлы Godot или папка проекта. Проверьте, что игра находится в G:\\Cady.",
                "Кади · запуск", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        try
        {
            var start = new ProcessStartInfo
            {
                FileName = engine,
                Arguments = "--path \"" + project + "\"",
                WorkingDirectory = project,
                UseShellExecute = false
            };
            Process.Start(start);
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Кади · ошибка запуска", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
