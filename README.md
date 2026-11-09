# USB Monitor / USB-монитор

Небольшая программа для Windows с окном журнала подключений и отключений устройств. Помогает искать возможную причину периодических звуков подключения и отключения.

A small Windows utility with a window that logs device connections and disconnections. It can help investigate intermittent device connection sounds.

**[Русский](#русский) · [English](#english)**

---

## Русский

### Возможности

- Записывает полученные уведомления о подключении и отключении устройств с временем до миллисекунд.
- Показывает название, производителя, VID:PID и ID устройства, если Windows предоставляет эти сведения.
- По умолчанию фильтрует список по USB, USBSTOR и HID; фильтр можно отключить.
- Показывает счётчики событий и название, которое чаще всего встречается в событиях отключения за текущий сеанс.
- Сохраняет журнал рядом с программой в `usb-log.txt` и позволяет экспортировать видимые строки в TXT или CSV.
- Поддерживает режим «Поверх всех окон». Двойной щелчок по строке копирует её в буфер обмена.

### Требования и запуск

- Windows 10/11; программа использует Windows PowerShell, .NET и Windows Forms. Это скрипт, а не готовый EXE-файл.
- Установка дополнительных библиотек не требуется. Скопируйте или распакуйте **оба** файла в одну папку, в которой разрешена запись, например в «Документы».
- Дважды нажмите `Start-UsbMonitor.bat`. Оставьте открывшееся окно работающим и проверьте программу, подключив или отключив флешку.
- Когда услышите звук, посмотрите в журнале события за это время. Чтобы видеть больше событий, снимите галочку «Только USB-устройства» — настройка не возвращает ранее пропущенные события.

Если скачиваете проект с GitHub: нажмите **Code → Download ZIP**, распакуйте архив и запустите BAT-файл из распакованной папки. Не запускайте его прямо внутри ZIP.

### Важно: ограничения

- Монитор получает уведомления Windows об интерфейсах устройств. **Он может пропустить некоторые события**, в том числе вызвавшие звук Windows; снятие фильтра этого не гарантирует. Звук подключения сам по себе не доказывает, что причина именно в USB.
- Повторные одинаковые события одного типа для одного ID в течение трёх секунд подавляются. Одно физическое устройство может иметь несколько интерфейсов, поэтому счётчики не обязательно равны числу физических устройств.
- Показывается до 5 000 последних строк. Кнопка «Очистить» очищает окно и счётчики, но не удаляет существующий `usb-log.txt`. Автозапись работает, только пока программа запущена и включена галочка «Записывать в файл».
- В этой версии ошибки записи в автоматический лог не отображаются. Если файл не создаётся, убедитесь, что папка доступна для записи.
- Перед публикацией журнала или скриншота проверьте ID устройств: они могут содержать серийные номера и другие идентификаторы.
- Интерфейс программы пока только на русском языке.

### Как это работает

BAT-файл запускает Windows PowerShell с параметром `-ExecutionPolicy Bypass` **для этого процесса**, чтобы выполнить локальный скрипт. Скрипт компилирует встроенный код C# и создаёт окно Windows Forms, которое получает системные уведомления `WM_DEVICECHANGE`. Названия устройств запрашиваются из системных сведений Windows; не для всех событий удаётся получить все поля.

### Если окно не открывается

Проверьте, что оба файла находятся рядом и архив распакован. Если ошибка не видна, откройте BAT-файл в текстовом редакторе и удалите `-WindowStyle Hidden`, затем снова запустите его — окно PowerShell может показать подробности. В некоторых организациях запуск скриптов может блокироваться политиками безопасности; обратитесь к администратору.

---

## English

### Features

- Logs received device arrival and removal notifications with millisecond timestamps.
- Shows the device name, manufacturer, VID:PID, and device ID when available from Windows.
- Filters to USB, USBSTOR, and HID by default; the filter can be turned off.
- Shows event counts and the name most frequently associated with removal events in the current session.
- Writes a log to `usb-log.txt` next to the program and exports visible rows to TXT or CSV.
- Offers an always-on-top option. Double-click a row to copy it to the clipboard.

### Requirements and usage

- Windows 10/11; the program uses Windows PowerShell, .NET, and Windows Forms. It is a script, not a prebuilt EXE.
- No extra libraries need to be installed. Copy or extract **both** program files into the same writable folder, such as Documents.
- Double-click `Start-UsbMonitor.bat`. Leave the window open and test it by connecting or disconnecting a USB flash drive.
- When you hear the sound, look for events around that time. To see more events, uncheck “Только USB-устройства” (“USB devices only”). This does not recover events already missed.

To download the project from GitHub, choose **Code → Download ZIP**, extract it, and run the BAT file from the extracted folder, not from inside the ZIP.

### Important limitations

- The monitor receives Windows device-interface notifications. **It may miss some events**, including events that triggered a Windows sound; turning off the filter does not guarantee detection. A connection sound does not necessarily mean a USB device is responsible.
- Duplicate events of the same type for the same ID are suppressed for three seconds. A physical device can expose multiple interfaces, so event counts do not necessarily equal physical device counts.
- The window displays up to 5,000 recent rows. Clearing it resets the display and counters but does not delete the existing `usb-log.txt`. Automatic logging works only while the program is running and the logging checkbox is enabled.
- In this version, automatic log-write errors are not shown. If the file is not created, check that the folder is writable.
- Before sharing a log or screenshot, check device IDs for serial numbers and other identifiers.
- The program interface is currently in Russian only.

### How it works

The BAT file launches Windows PowerShell with `-ExecutionPolicy Bypass` **for that process** to run the local script. The script compiles embedded C# and opens a Windows Forms window that receives `WM_DEVICECHANGE` notifications. Device names are obtained from Windows system information; not all fields are available for every event.

### Troubleshooting

Make sure both files are in the same extracted folder. If no error is visible, open the BAT file in a text editor, remove `-WindowStyle Hidden`, and run it again; the PowerShell window may reveal details. Organizational security policies may block scripts; contact your administrator if necessary.
