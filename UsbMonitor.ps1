# USB-монитор: окно с журналом подключений/отключений USB-устройств
# Запуск: двойной клик по Start-UsbMonitor.bat

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$code = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Microsoft.Win32;

public class UsbMonitorForm : Form
{
    const int WM_DEVICECHANGE = 0x0219;
    const int DBT_DEVICEARRIVAL = 0x8000;
    const int DBT_DEVICEREMOVECOMPLETE = 0x8004;
    const int DBT_DEVTYP_DEVICEINTERFACE = 5;
    const int DEVICE_NOTIFY_ALL_INTERFACE_CLASSES = 4;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DEV_BROADCAST_DEVICEINTERFACE
    {
        public int dbcc_size;
        public int dbcc_devicetype;
        public int dbcc_reserved;
        public Guid dbcc_classguid;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 255)]
        public string dbcc_name;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct DEVPROPKEY
    {
        public Guid fmtid;
        public uint pid;
    }

    [DllImport("user32.dll", SetLastError = true)]
    static extern IntPtr RegisterDeviceNotification(IntPtr hRecipient, IntPtr filter, int flags);

    [DllImport("user32.dll")]
    static extern bool UnregisterDeviceNotification(IntPtr handle);

    [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
    static extern int CM_Locate_DevNodeW(out uint devInst, string deviceId, uint flags);

    [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
    static extern int CM_Get_DevNode_PropertyW(uint devInst, ref DEVPROPKEY key, out uint propType,
        byte[] buffer, ref uint bufferSize, uint flags);

    readonly string logPath;
    ListView list;
    CheckBox chkUsbOnly, chkFile, chkTop;
    ToolStripStatusLabel status;
    IntPtr notifyHandle = IntPtr.Zero;

    readonly Dictionary<string, DateTime> recent = new Dictionary<string, DateTime>();
    readonly Dictionary<string, int> dropCounts = new Dictionary<string, int>();
    int countOn, countOff;

    static readonly Color OnColor = Color.FromArgb(232, 245, 236);
    static readonly Color OffColor = Color.FromArgb(252, 232, 230);

    public UsbMonitorForm(string logPath)
    {
        this.logPath = logPath;
        Text = "USB-монитор — журнал подключений и отключений";
        Font = new Font("Segoe UI", 9f);
        Size = new Size(1100, 600);
        MinimumSize = new Size(720, 360);
        StartPosition = FormStartPosition.CenterScreen;

        FlowLayoutPanel top = new FlowLayoutPanel();
        top.Dock = DockStyle.Top;
        top.AutoSize = true;
        top.Padding = new Padding(8, 6, 8, 6);
        top.WrapContents = true;

        chkUsbOnly = new CheckBox();
        chkUsbOnly.Text = "Только USB-устройства";
        chkUsbOnly.Checked = true;
        chkUsbOnly.AutoSize = true;
        chkUsbOnly.Margin = new Padding(3, 8, 12, 3);

        chkFile = new CheckBox();
        chkFile.Text = "Записывать в файл";
        chkFile.Checked = true;
        chkFile.AutoSize = true;
        chkFile.Margin = new Padding(3, 8, 12, 3);

        chkTop = new CheckBox();
        chkTop.Text = "Поверх всех окон";
        chkTop.AutoSize = true;
        chkTop.Margin = new Padding(3, 8, 20, 3);
        chkTop.CheckedChanged += delegate { TopMost = chkTop.Checked; };

        Button btnClear = MakeButton("Очистить");
        btnClear.Click += delegate
        {
            list.Items.Clear();
            countOn = 0; countOff = 0;
            dropCounts.Clear();
            UpdateStatus();
        };

        Button btnSave = MakeButton("Сохранить как…");
        btnSave.Click += delegate { SaveAs(); };

        Button btnOpen = MakeButton("Открыть файл лога");
        btnOpen.Click += delegate
        {
            if (File.Exists(this.logPath)) Process.Start(this.logPath);
            else MessageBox.Show("Файл лога пока не создан:\n" + this.logPath, Text);
        };

        top.Controls.Add(chkUsbOnly);
        top.Controls.Add(chkFile);
        top.Controls.Add(chkTop);
        top.Controls.Add(btnClear);
        top.Controls.Add(btnSave);
        top.Controls.Add(btnOpen);

        list = new ListView();
        list.Dock = DockStyle.Fill;
        list.View = View.Details;
        list.FullRowSelect = true;
        list.GridLines = true;
        list.HideSelection = false;
        list.Columns.Add("Время", 150);
        list.Columns.Add("Событие", 120);
        list.Columns.Add("Устройство", 330);
        list.Columns.Add("Производитель", 170);
        list.Columns.Add("VID:PID", 90);
        list.Columns.Add("ID устройства", 420);
        list.DoubleClick += delegate { CopySelected(); };

        StatusStrip strip = new StatusStrip();
        status = new ToolStripStatusLabel();
        status.Spring = true;
        status.TextAlign = ContentAlignment.MiddleLeft;
        strip.Items.Add(status);

        Controls.Add(list);
        Controls.Add(top);
        Controls.Add(strip);
        list.BringToFront();

        UpdateStatus();
    }

    Button MakeButton(string text)
    {
        Button b = new Button();
        b.Text = text;
        b.AutoSize = true;
        b.Height = 30;
        b.Margin = new Padding(3, 3, 6, 3);
        return b;
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        RegisterForDeviceEvents();
    }

    protected override void OnHandleDestroyed(EventArgs e)
    {
        if (notifyHandle != IntPtr.Zero)
        {
            UnregisterDeviceNotification(notifyHandle);
            notifyHandle = IntPtr.Zero;
        }
        base.OnHandleDestroyed(e);
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        AddInfo("Мониторинг запущен. Ждём подключений и отключений… Лог: " + logPath);
    }

    void RegisterForDeviceEvents()
    {
        DEV_BROADCAST_DEVICEINTERFACE filter = new DEV_BROADCAST_DEVICEINTERFACE();
        filter.dbcc_size = Marshal.SizeOf(typeof(DEV_BROADCAST_DEVICEINTERFACE));
        filter.dbcc_devicetype = DBT_DEVTYP_DEVICEINTERFACE;
        filter.dbcc_name = "";
        IntPtr buffer = Marshal.AllocHGlobal(filter.dbcc_size);
        try
        {
            Marshal.StructureToPtr(filter, buffer, false);
            notifyHandle = RegisterDeviceNotification(Handle, buffer, DEVICE_NOTIFY_ALL_INTERFACE_CLASSES);
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_DEVICECHANGE && m.LParam != IntPtr.Zero)
        {
            long ev = m.WParam.ToInt64();
            if (ev == DBT_DEVICEARRIVAL || ev == DBT_DEVICEREMOVECOMPLETE)
            {
                try
                {
                    int devType = Marshal.ReadInt32(m.LParam, 4);
                    if (devType == DBT_DEVTYP_DEVICEINTERFACE)
                    {
                        string path = Marshal.PtrToStringUni(new IntPtr(m.LParam.ToInt64() + 28));
                        OnDevice(ev == DBT_DEVICEARRIVAL, path);
                    }
                }
                catch (Exception ex)
                {
                    AddInfo("Ошибка обработки события: " + ex.Message);
                }
            }
        }
        base.WndProc(ref m);
    }

    void OnDevice(bool arrival, string path)
    {
        if (string.IsNullOrEmpty(path)) return;
        string id = PathToInstanceId(path);
        string bus = id.Split('\\')[0];

        if (chkUsbOnly.Checked && bus != "USB" && bus != "USBSTOR" && bus != "HID") return;

        // одно устройство присылает несколько уведомлений — оставляем одно
        DateTime now = DateTime.Now;
        string key = (arrival ? "+" : "-") + id;
        DateTime last;
        if (recent.TryGetValue(key, out last) && (now - last).TotalSeconds < 3) return;
        if (recent.Count > 1000) recent.Clear();
        recent[key] = now;

        string name, mfg;
        GetRegistryInfo(id, out name, out mfg);
        string busDesc = GetBusReportedName(id);
        if (busDesc.Length > 0)
        {
            if (name.Length == 0) name = busDesc;
            else if (!name.Equals(busDesc, StringComparison.OrdinalIgnoreCase)) name = name + " («" + busDesc + "»)";
        }
        if (name.Length == 0) name = "(неизвестное устройство)";

        string vidpid = "";
        Match mt = Regex.Match(id, @"VID_([0-9A-F]{4}).*?PID_([0-9A-F]{4})", RegexOptions.IgnoreCase);
        if (mt.Success) vidpid = mt.Groups[1].Value.ToUpperInvariant() + ":" + mt.Groups[2].Value.ToUpperInvariant();

        if (arrival) countOn++;
        else
        {
            countOff++;
            int n;
            dropCounts.TryGetValue(name, out n);
            dropCounts[name] = n + 1;
        }

        AddRow(now, arrival ? "▲ ПОДКЛЮЧЕНО" : "▼ ОТКЛЮЧЕНО", name, mfg, vidpid, id,
            arrival ? OnColor : OffColor, Color.Black);
        UpdateStatus();
    }

    static string PathToInstanceId(string path)
    {
        string s = path;
        if (s.StartsWith(@"\\?\") || s.StartsWith(@"\\.\")) s = s.Substring(4);
        int i = s.LastIndexOf("#{");
        if (i >= 0) s = s.Substring(0, i);
        return s.Replace('#', '\\').ToUpperInvariant();
    }

    static string CleanDesc(object value)
    {
        string v = value as string;
        if (string.IsNullOrEmpty(v)) return "";
        int i = v.LastIndexOf(';');
        return (i >= 0 ? v.Substring(i + 1) : v).Trim();
    }

    static void GetRegistryInfo(string id, out string name, out string mfg)
    {
        name = "";
        mfg = "";
        try
        {
            using (RegistryKey k = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Enum\" + id))
            {
                if (k == null) return;
                name = CleanDesc(k.GetValue("FriendlyName"));
                if (name.Length == 0) name = CleanDesc(k.GetValue("DeviceDesc"));
                mfg = CleanDesc(k.GetValue("Mfg"));
            }
        }
        catch { }
    }

    // Имя, которое сообщает само устройство (например, «USB Receiver»)
    static string GetBusReportedName(string id)
    {
        try
        {
            uint devInst;
            if (CM_Locate_DevNodeW(out devInst, id, 1 /* CM_LOCATE_DEVNODE_PHANTOM */) != 0) return "";
            DEVPROPKEY key = new DEVPROPKEY();
            key.fmtid = new Guid("540b947e-8b40-45bc-a8a2-6a0b894cbda2");
            key.pid = 4;
            byte[] buf = new byte[1024];
            uint size = (uint)buf.Length;
            uint type;
            if (CM_Get_DevNode_PropertyW(devInst, ref key, out type, buf, ref size, 0) != 0) return "";
            return Encoding.Unicode.GetString(buf, 0, (int)size).TrimEnd('\0').Trim();
        }
        catch
        {
            return "";
        }
    }

    void AddInfo(string text)
    {
        AddRow(DateTime.Now, "• инфо", text, "", "", "", SystemColors.Window, Color.DimGray);
    }

    void AddRow(DateTime time, string ev, string name, string mfg, string vidpid, string id, Color back, Color fore)
    {
        string t = time.ToString("dd.MM.yyyy HH:mm:ss.fff");
        ListViewItem item = new ListViewItem(new string[] { t, ev, name, mfg, vidpid, id });
        item.BackColor = back;
        item.ForeColor = fore;
        list.Items.Add(item);
        if (list.Items.Count > 5000) list.Items.RemoveAt(0);
        item.EnsureVisible();

        if (chkFile.Checked)
        {
            try
            {
                File.AppendAllText(logPath, string.Join("\t", new string[] { t, ev, name, mfg, vidpid, id })
                    + Environment.NewLine, Encoding.UTF8);
            }
            catch { }
        }
    }

    void UpdateStatus()
    {
        string top = "";
        int max = 0;
        foreach (KeyValuePair<string, int> p in dropCounts)
        {
            if (p.Value > max) { max = p.Value; top = p.Key; }
        }
        string s = string.Format("Подключений: {0}   ·   Отключений: {1}", countOn, countOff);
        if (max > 0) s += string.Format("   ·   Чаще всего отключается: {0} ({1} раз)", top, max);
        s += "   ·   Двойной клик по строке — скопировать";
        status.Text = s;
    }

    void CopySelected()
    {
        if (list.SelectedItems.Count == 0) return;
        StringBuilder sb = new StringBuilder();
        foreach (ListViewItem it in list.SelectedItems)
        {
            List<string> cells = new List<string>();
            foreach (ListViewItem.ListViewSubItem sub in it.SubItems) cells.Add(sub.Text);
            sb.AppendLine(string.Join("\t", cells.ToArray()));
        }
        Clipboard.SetText(sb.ToString());
        status.Text = "Скопировано в буфер обмена";
    }

    void SaveAs()
    {
        using (SaveFileDialog dlg = new SaveFileDialog())
        {
            dlg.Filter = "Текстовый файл (*.txt)|*.txt|CSV для Excel (*.csv)|*.csv";
            dlg.FileName = "usb-log-" + DateTime.Now.ToString("yyyy-MM-dd_HH-mm") + ".txt";
            if (dlg.ShowDialog(this) != DialogResult.OK) return;
            string sep = dlg.FileName.EndsWith(".csv", StringComparison.OrdinalIgnoreCase) ? ";" : "\t";
            StringBuilder sb = new StringBuilder();
            sb.AppendLine(string.Join(sep, new string[] { "Время", "Событие", "Устройство", "Производитель", "VID:PID", "ID устройства" }));
            foreach (ListViewItem it in list.Items)
            {
                List<string> cells = new List<string>();
                foreach (ListViewItem.ListViewSubItem sub in it.SubItems) cells.Add(sub.Text);
                sb.AppendLine(string.Join(sep, cells.ToArray()));
            }
            File.WriteAllText(dlg.FileName, sb.ToString(), Encoding.UTF8);
        }
    }
}
'@

try {
    Add-Type -TypeDefinition $code -ReferencedAssemblies System.Windows.Forms, System.Drawing
    $logPath = Join-Path $PSScriptRoot 'usb-log.txt'
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object UsbMonitorForm -ArgumentList $logPath
    [System.Windows.Forms.Application]::Run($form)
}
catch {
    [System.Windows.Forms.MessageBox]::Show("Не удалось запустить USB-монитор:`n`n$($_ | Out-String)", 'USB-монитор') | Out-Null
}
