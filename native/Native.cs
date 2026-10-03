using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace CME {
    public static class Native {
        [DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
        static extern int SHLoadIndirectString(string src, StringBuilder buf, int cch, IntPtr reserved);
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        public static extern uint ExtractIconEx(string file, int index, IntPtr[] large, IntPtr[] small, uint count);
        [DllImport("user32.dll")]
        public static extern bool DestroyIcon(IntPtr h);
        [DllImport("dwmapi.dll")]
        static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
        [DllImport("kernel32.dll")]
        public static extern IntPtr GetConsoleWindow();
        [DllImport("kernel32.dll")]
        static extern uint GetConsoleProcessList(uint[] list, uint count);
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr h, int cmd);

        public static string LoadIndirect(string s) {
            var sb = new StringBuilder(1024);
            return SHLoadIndirectString(s, sb, sb.Capacity, IntPtr.Zero) == 0 ? sb.ToString() : null;
        }

        // Own taskbar identity, so the window shows the editor's icon instead of grouping under PowerShell.
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

        public static void DarkTitleBar(IntPtr hwnd, int captionColor) {
            int on = 1;
            if (DwmSetWindowAttribute(hwnd, 20, ref on, 4) != 0) DwmSetWindowAttribute(hwnd, 19, ref on, 4);
            if (captionColor >= 0) DwmSetWindowAttribute(hwnd, 35, ref captionColor, 4);
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct SHFILEINFO {
            public IntPtr hIcon; public int iIcon; public uint dwAttributes;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szDisplayName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] public string szTypeName;
        }
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern IntPtr SHGetFileInfo(string path, uint attrs, ref SHFILEINFO info, uint size, uint flags);

        // Large shell icon for a file, or for an extension when byExtension is set (the file need not exist).
        public static IntPtr FileIcon(string path, bool byExtension) {
            var i = new SHFILEINFO();
            uint flags = 0x100;                    // SHGFI_ICON (large)
            if (byExtension) flags |= 0x10;        // SHGFI_USEFILEATTRIBUTES
            SHGetFileInfo(path, byExtension ? 0x80u : 0u, ref i, (uint)Marshal.SizeOf(i), flags);
            return i.hIcon;
        }

        public static string DisplayName(string path) {
            var i = new SHFILEINFO();
            SHGetFileInfo(path, 0, ref i, (uint)Marshal.SizeOf(i), 0x200); // SHGFI_DISPLAYNAME
            return i.szDisplayName;
        }

        // True when this process is the only one attached to its console (i.e. the console was made for us).
        public static bool OwnsConsole() {
            var list = new uint[4];
            return GetConsoleProcessList(list, 4) == 1;
        }
    }

    public class NavEntry : INotifyPropertyChanged {
        public string Id { get; set; }
        public string Label { get; set; }
        public string Glyph { get; set; }
        public string Margin { get; set; }
        string _count;
        public string Count {
            get { return _count; }
            set { _count = value; var h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs("Count")); }
        }
        public event PropertyChangedEventHandler PropertyChanged;
    }
}
