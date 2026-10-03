using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

// Send To bridge: runs a Windows 11 context-menu command (an IExplorerCommand COM handler) on the
// files Send To passes in, the same way Explorer invokes it from the right-click menu.
//   CmeSendTo.exe <clsid> [--sub i[,j]] files...     invoke (optionally a subcommand path)
//   CmeSendTo.exe --probe <clsid> <outfile> [file]   write title/flags/subcommands to outfile, invoke nothing
namespace CmeSendTo {
    [ComImport, Guid("a08ce4d0-fa25-44ab-b57c-c7b1c323e0b9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IExplorerCommand {
        [PreserveSig] int GetTitle(IntPtr items, out IntPtr name);
        [PreserveSig] int GetIcon(IntPtr items, out IntPtr icon);
        [PreserveSig] int GetToolTip(IntPtr items, out IntPtr tip);
        [PreserveSig] int GetCanonicalName(out Guid name);
        [PreserveSig] int GetState(IntPtr items, [MarshalAs(UnmanagedType.Bool)] bool okToBeSlow, out uint state);
        [PreserveSig] int Invoke(IntPtr items, IntPtr bindCtx);
        [PreserveSig] int GetFlags(out uint flags);
        [PreserveSig] int EnumSubCommands(out IEnumExplorerCommand commands);
    }

    [ComImport, Guid("a88826f8-186f-4987-aade-ea0cef8fbfe8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IEnumExplorerCommand {
        [PreserveSig] int Next(uint count, [Out, MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 0)] IExplorerCommand[] commands, out uint fetched);
        [PreserveSig] int Skip(uint count);
        [PreserveSig] int Reset();
        [PreserveSig] int Clone(out IEnumExplorerCommand copy);
    }

    static class Program {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern int SHParseDisplayName(string name, IntPtr bindCtx, out IntPtr pidl, uint sfgaoIn, out uint sfgaoOut);
        [DllImport("shell32.dll")]
        static extern int SHCreateShellItemArrayFromIDLists(uint count, IntPtr[] pidls, out IntPtr array);
        [DllImport("ole32.dll")]
        static extern void CoTaskMemFree(IntPtr p);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern int MessageBoxW(IntPtr owner, string text, string caption, uint type);

        const uint ECF_HASSUBCOMMANDS = 0x1;

        static string TakeString(IntPtr p) {
            if (p == IntPtr.Zero) return "";
            string s = Marshal.PtrToStringUni(p);
            CoTaskMemFree(p);
            return s;
        }

        static IntPtr MakeItemArray(IList<string> paths) {
            if (paths.Count == 0) return IntPtr.Zero;
            var pidls = new List<IntPtr>();
            try {
                foreach (string p in paths) {
                    IntPtr pidl; uint attrs;
                    int hr = SHParseDisplayName(Path.GetFullPath(p), IntPtr.Zero, out pidl, 0, out attrs);
                    if (hr != 0) throw new COMException("Could not open " + p, hr);
                    pidls.Add(pidl);
                }
                IntPtr array;
                int hr2 = SHCreateShellItemArrayFromIDLists((uint)pidls.Count, pidls.ToArray(), out array);
                if (hr2 != 0) throw new COMException("Could not build the item list", hr2);
                return array;
            } finally {
                foreach (IntPtr p in pidls) CoTaskMemFree(p);
            }
        }

        static IExplorerCommand Create(string clsid) {
            Type t = Type.GetTypeFromCLSID(new Guid(clsid), true);
            return (IExplorerCommand)Activator.CreateInstance(t);
        }

        static List<IExplorerCommand> SubCommands(IExplorerCommand cmd) {
            var list = new List<IExplorerCommand>();
            uint flags;
            if (cmd.GetFlags(out flags) != 0 || (flags & ECF_HASSUBCOMMANDS) == 0) return list;
            IEnumExplorerCommand e;
            if (cmd.EnumSubCommands(out e) != 0 || e == null) return list;
            var one = new IExplorerCommand[1];
            uint fetched;
            while (e.Next(1, one, out fetched) == 0 && fetched == 1) list.Add(one[0]);
            return list;
        }

        static void Describe(IExplorerCommand cmd, IntPtr items, string indent, StringBuilder sb, int depth) {
            IntPtr p; uint flags = 0, state = 0;
            string title = cmd.GetTitle(items, out p) == 0 ? TakeString(p) : "";
            cmd.GetFlags(out flags);
            cmd.GetState(items, true, out state);
            sb.AppendLine(indent + "title=" + title + "|flags=" + flags + "|state=" + state);
            if (depth > 2) return;
            int i = 0;
            foreach (var sub in SubCommands(cmd)) {
                sb.Append(indent + "  [" + i + "] ");
                Describe(sub, items, indent + "  ", sb, depth + 1);
                i++;
            }
        }

        [STAThread]
        static int Main(string[] args) {
            try {
                if (args.Length >= 3 && args[0] == "--probe") {
                    var files = new List<string>();
                    for (int i = 3; i < args.Length; i++) files.Add(args[i]);
                    IntPtr items = MakeItemArray(files);
                    var sb = new StringBuilder();
                    Describe(Create(args[1]), items, "", sb, 0);
                    File.WriteAllText(args[2], sb.ToString());
                    return 0;
                }

                if (args.Length < 2) {
                    MessageBoxW(IntPtr.Zero, "Usage: CmeSendTo.exe <clsid> [--sub i[,j]] files...", "Send To bridge", 0x10);
                    return 2;
                }
                string clsid = args[0];
                int next = 1;
                // --sub "index:title>index:title": each level is found by title first, so a reordered menu
                // (a new device paired, say) still hits the right item; the index is only a fallback.
                string[] route = new string[0];
                if (args[1] == "--sub" && args.Length > 2) {
                    route = args[2].Split('>');
                    next = 3;
                }
                var paths = new List<string>();
                for (int i = next; i < args.Length; i++) paths.Add(args[i]);
                if (paths.Count == 0) return 0;

                IntPtr array = MakeItemArray(paths);
                IExplorerCommand cmd = Create(clsid);
                foreach (string step in route) {
                    int colon = step.IndexOf(':');
                    int index = colon > 0 ? int.Parse(step.Substring(0, colon)) : -1;
                    string title = colon >= 0 ? step.Substring(colon + 1) : step;
                    var subs = SubCommands(cmd);
                    IExplorerCommand found = null;
                    foreach (var sub in subs) {
                        IntPtr p;
                        if (sub.GetTitle(array, out p) == 0 && TakeString(p) == title) { found = sub; break; }
                    }
                    if (found == null && index >= 0 && index < subs.Count) found = subs[index];
                    if (found == null) throw new InvalidOperationException("\"" + title + "\" is no longer in this menu.");
                    cmd = found;
                }
                int hr = cmd.Invoke(array, IntPtr.Zero);
                if (hr != 0) throw new COMException("The command reported an error", hr);
                // Give out-of-process handlers a moment to pick the items up before this process exits.
                Thread.Sleep(1500);
                return 0;
            } catch (Exception ex) {
                MessageBoxW(IntPtr.Zero, ex.Message + "\n\n" + ex.GetType().Name + (ex is COMException ? " 0x" + ((COMException)ex).ErrorCode.ToString("X8") : ""), "Send To", 0x10);
                return 1;
            }
        }
    }
}
