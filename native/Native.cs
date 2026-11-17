using System;
using System.Collections.Generic;
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

        [DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
        static extern int StrCmpLogicalW(string a, string b);
        // Explorer's name order ("File 9" before "File 10").
        public static int CompareLogical(string a, string b) { return StrCmpLogicalW(a ?? "", b ?? ""); }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern void SHChangeNotify(int eventId, uint flags, string item1, IntPtr item2);

        // Tells the shell (this process's and Explorer's caches) that a folder's items changed,
        // e.g. after editing its desktop.ini display names.
        public static void NotifyFolderChanged(string folder) {
            SHChangeNotify(0x00001000, 0x0005 | 0x1000, folder, IntPtr.Zero);                 // SHCNE_UPDATEDIR, SHCNF_PATHW | SHCNF_FLUSH
            SHChangeNotify(0x00002000, 0x0005 | 0x1000, folder + "\\desktop.ini", IntPtr.Zero); // SHCNE_UPDATEITEM
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
    // One item of a real context menu as Explorer builds it (see MenuReader).
    public class MenuNode {
        public string Text { get; set; }
        public string Verb { get; set; }
        public bool Separator { get; set; }
        public bool Disabled { get; set; }
        public bool IsDefault { get; set; }
        public List<MenuNode> Children { get; set; }
        public MenuNode() { Children = new List<MenuNode>(); }
    }

    [ComImport, Guid("000214E4-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IContextMenu {
        [PreserveSig] int QueryContextMenu(IntPtr hmenu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint uFlags);
        [PreserveSig] int InvokeCommand(IntPtr pici);
        [PreserveSig] int GetCommandString(UIntPtr idCmd, uint uType, IntPtr pReserved, IntPtr pszName, uint cchMax);
    }
    [ComImport, Guid("000214F4-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IContextMenu2 {
        [PreserveSig] int QueryContextMenu(IntPtr hmenu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint uFlags);
        [PreserveSig] int InvokeCommand(IntPtr pici);
        [PreserveSig] int GetCommandString(UIntPtr idCmd, uint uType, IntPtr pReserved, IntPtr pszName, uint cchMax);
        [PreserveSig] int HandleMenuMsg(uint uMsg, IntPtr wParam, IntPtr lParam);
    }
    [ComImport, Guid("BCFCE0A0-EC17-11D0-8D10-00A0C90F2719"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IContextMenu3 {
        [PreserveSig] int QueryContextMenu(IntPtr hmenu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint uFlags);
        [PreserveSig] int InvokeCommand(IntPtr pici);
        [PreserveSig] int GetCommandString(UIntPtr idCmd, uint uType, IntPtr pReserved, IntPtr pszName, uint cchMax);
        [PreserveSig] int HandleMenuMsg(uint uMsg, IntPtr wParam, IntPtr lParam);
        [PreserveSig] int HandleMenuMsg2(uint uMsg, IntPtr wParam, IntPtr lParam, out IntPtr result);
    }
    [ComImport, Guid("000214E8-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellExtInit {
        [PreserveSig] int Initialize(IntPtr pidlFolder, IntPtr pdtobj, IntPtr hkeyProgID);
    }
    [ComImport, Guid("000214E6-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellFolder {
        [PreserveSig] int ParseDisplayName(IntPtr hwnd, IntPtr pbc, [MarshalAs(UnmanagedType.LPWStr)] string name, IntPtr eaten, out IntPtr ppidl, IntPtr attrs);
        [PreserveSig] int EnumObjects(IntPtr hwnd, int flags, out IntPtr ppenum);
        [PreserveSig] int BindToObject(IntPtr pidl, IntPtr pbc, ref Guid riid, out IntPtr ppv);
        [PreserveSig] int BindToStorage(IntPtr pidl, IntPtr pbc, ref Guid riid, out IntPtr ppv);
        [PreserveSig] int CompareIDs(IntPtr lParam, IntPtr p1, IntPtr p2);
        [PreserveSig] int CreateViewObject(IntPtr hwnd, ref Guid riid, out IntPtr ppv);
        [PreserveSig] int GetAttributesOf(uint cidl, [MarshalAs(UnmanagedType.LPArray)] IntPtr[] apidl, ref uint rgf);
        [PreserveSig] int GetUIObjectOf(IntPtr hwnd, uint cidl, [MarshalAs(UnmanagedType.LPArray)] IntPtr[] apidl, ref Guid riid, IntPtr rgf, out IntPtr ppv);
    }

    // Reads the classic ("Show more options") context menu the way Explorer builds it, so the preview
    // shows exactly what Windows would, built-ins and all. Must run on an STA thread.
    public static class MenuReader {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern int SHParseDisplayName(string name, IntPtr pbc, out IntPtr pidl, uint sfgao, out uint psfgao);
        [DllImport("shell32.dll")] static extern int SHBindToParent(IntPtr pidl, ref Guid riid, out IntPtr ppv, out IntPtr ppidlLast);
        [DllImport("shell32.dll")] static extern int SHBindToObject(IntPtr psf, IntPtr pidl, IntPtr pbc, ref Guid riid, out IntPtr ppv);
        [DllImport("shell32.dll")] static extern int SHGetDesktopFolder(out IntPtr ppshf);
        [DllImport("shell32.dll")] static extern IntPtr ILClone(IntPtr pidl);
        [DllImport("shell32.dll")] static extern bool ILRemoveLastID(IntPtr pidl);
        [DllImport("user32.dll")] static extern IntPtr CreatePopupMenu();
        [DllImport("user32.dll")] static extern bool DestroyMenu(IntPtr h);
        [DllImport("user32.dll")] static extern int GetMenuItemCount(IntPtr h);
        [DllImport("user32.dll")] static extern IntPtr GetSubMenu(IntPtr h, int pos);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMenuItemInfo(IntPtr h, uint item, bool byPos, ref MENUITEMINFO mii);
        [DllImport("ole32.dll")] static extern void CoTaskMemFree(IntPtr p);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct MENUITEMINFO {
            public uint cbSize, fMask, fType, fState, wID; public IntPtr hSubMenu, hbmpChecked, hbmpUnchecked, dwItemData;
            public IntPtr dwTypeData; public uint cch; public IntPtr hbmpItem;
        }

        static Guid IID_IShellFolder = new Guid("000214E6-0000-0000-C000-000000000046");
        static Guid IID_IContextMenu = new Guid("000214E4-0000-0000-C000-000000000046");
        static Guid IID_IDataObject = new Guid("0000010e-0000-0000-C000-000000000046");
        const uint FirstId = 1, LastId = 0x7FFF;

        // path "" is the desktop itself (only meaningful with background).
        static void Open(string path, out IntPtr pidl, out IntPtr folder) {
            uint a; folder = IntPtr.Zero; pidl = IntPtr.Zero;
            if (path.Length == 0) { Marshal.ThrowExceptionForHR(SHGetDesktopFolder(out folder)); return; }
            Marshal.ThrowExceptionForHR(SHParseDisplayName(path, IntPtr.Zero, out pidl, 0, out a));
        }

        static uint Flags(bool extended) { return extended ? 0x100u : 0u; } // CMF_EXTENDEDVERBS, as with Shift held

        public static List<MenuNode> Read(string path, bool background, bool extended) {
            IntPtr pidl, psf, child, pcm = IntPtr.Zero;
            Open(path, out pidl, out psf);
            try {
                int hr;
                Guid gsf = IID_IShellFolder, gcm = IID_IContextMenu;
                if (background) {
                    if (psf == IntPtr.Zero) Marshal.ThrowExceptionForHR(SHBindToObject(IntPtr.Zero, pidl, IntPtr.Zero, ref gsf, out psf));
                    hr = ((IShellFolder)Marshal.GetObjectForIUnknown(psf)).CreateViewObject(IntPtr.Zero, ref gcm, out pcm);
                } else {
                    Marshal.ThrowExceptionForHR(SHBindToParent(pidl, ref gsf, out psf, out child));
                    hr = ((IShellFolder)Marshal.GetObjectForIUnknown(psf)).GetUIObjectOf(IntPtr.Zero, 1, new[] { child }, ref gcm, IntPtr.Zero, out pcm);
                }
                Marshal.ThrowExceptionForHR(hr);
                var ctx = (IContextMenu)Marshal.GetObjectForIUnknown(pcm);
                IntPtr menu = CreatePopupMenu();
                try {
                    ctx.QueryContextMenu(menu, 0, FirstId, LastId, Flags(extended));
                    return ReadMenu(menu, ctx, 0);
                } finally { DestroyMenu(menu); }
            } finally {
                if (pcm != IntPtr.Zero) Marshal.Release(pcm);
                if (psf != IntPtr.Zero) Marshal.Release(psf);
                if (pidl != IntPtr.Zero) CoTaskMemFree(pidl);
            }
        }

        // The top-level texts one shell extension adds on its own. Their rows in the full menu carry no
        // verb, so this is how the preview tells which handler added which row.
        public static string[] ReadHandler(string path, bool background, string clsid, bool extended) {
            var result = new List<string>();
            IntPtr pidl, psf, child, folderPidl = IntPtr.Zero, pdo = IntPtr.Zero;
            Open(path, out pidl, out psf);
            object ext = null;
            try {
                if (!background) {
                    Guid gsf = IID_IShellFolder, gdo = IID_IDataObject;
                    Marshal.ThrowExceptionForHR(SHBindToParent(pidl, ref gsf, out psf, out child));
                    Marshal.ThrowExceptionForHR(((IShellFolder)Marshal.GetObjectForIUnknown(psf)).GetUIObjectOf(IntPtr.Zero, 1, new[] { child }, ref gdo, IntPtr.Zero, out pdo));
                    folderPidl = ILClone(pidl);
                    ILRemoveLastID(folderPidl);
                }
                var t = Type.GetTypeFromCLSID(new Guid(clsid), false);
                if (t == null) return result.ToArray();
                ext = Activator.CreateInstance(t);
                var init = ext as IShellExtInit;
                var ctx = ext as IContextMenu;
                if (init == null || ctx == null) return result.ToArray();
                if (init.Initialize(background ? pidl : folderPidl, pdo, IntPtr.Zero) != 0) return result.ToArray();
                IntPtr menu = CreatePopupMenu();
                try {
                    ctx.QueryContextMenu(menu, 0, FirstId, LastId, Flags(extended));
                    foreach (var n in ReadMenu(menu, null, 1)) if (!n.Separator && !string.IsNullOrEmpty(n.Text)) result.Add(n.Text);
                } finally { DestroyMenu(menu); }
            } finally {
                if (ext != null && Marshal.IsComObject(ext)) Marshal.ReleaseComObject(ext);
                if (pdo != IntPtr.Zero) Marshal.Release(pdo);
                if (psf != IntPtr.Zero) Marshal.Release(psf);
                if (folderPidl != IntPtr.Zero) CoTaskMemFree(folderPidl);
                if (pidl != IntPtr.Zero) CoTaskMemFree(pidl);
            }
            return result.ToArray();
        }

        static List<MenuNode> ReadMenu(IntPtr menu, IContextMenu ctx, int depth) {
            var list = new List<MenuNode>();
            int n = GetMenuItemCount(menu);
            for (int i = 0; i < n; i++) {
                var mii = new MENUITEMINFO();
                mii.cbSize = (uint)Marshal.SizeOf(typeof(MENUITEMINFO));
                mii.fMask = 0x1 | 0x2 | 0x40 | 0x100; // STATE, ID, STRING, FTYPE
                if (!GetMenuItemInfo(menu, (uint)i, true, ref mii)) continue;
                var node = new MenuNode();
                if ((mii.fType & 0x800) != 0) { node.Separator = true; list.Add(node); continue; }
                if (mii.cch > 0) {
                    IntPtr buf = Marshal.AllocHGlobal((int)(mii.cch + 1) * 2);
                    try {
                        mii.dwTypeData = buf; mii.cch++; mii.fMask = 0x40;
                        if (GetMenuItemInfo(menu, (uint)i, true, ref mii)) node.Text = Marshal.PtrToStringUni(buf);
                    } finally { Marshal.FreeHGlobal(buf); }
                }
                node.Disabled = (mii.fState & 0x3) != 0;
                node.IsDefault = (mii.fState & 0x1000) != 0;
                IntPtr sub = GetSubMenu(menu, i);
                if (sub != IntPtr.Zero) {
                    // Submenus such as Send to are filled in only when they are about to open.
                    if (ctx != null) {
                        IntPtr r;
                        var c3 = ctx as IContextMenu3; var c2 = ctx as IContextMenu2;
                        try {
                            if (c3 != null) c3.HandleMenuMsg2(0x117, sub, (IntPtr)i, out r); // WM_INITMENUPOPUP
                            else if (c2 != null) c2.HandleMenuMsg(0x117, sub, (IntPtr)i);
                        } catch { }
                    }
                    if (depth < 3) node.Children = ReadMenu(sub, ctx, depth + 1);
                }
                // Submenu rows can have a verb too (Windows 11 app submenus report their CLSID).
                if (ctx != null && mii.wID >= FirstId && mii.wID <= LastId) {
                    IntPtr sb = Marshal.AllocHGlobal(1024);
                    try {
                        Marshal.WriteInt16(sb, 0);
                        if (ctx.GetCommandString((UIntPtr)(mii.wID - FirstId), 4, IntPtr.Zero, sb, 512) == 0) node.Verb = Marshal.PtrToStringUni(sb); // GCS_VERBW
                    } catch { } finally { Marshal.FreeHGlobal(sb); }
                }
                list.Add(node);
            }
            return list;
        }
    }
}
