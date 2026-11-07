# Сборка «Осколков Долины» для Android (на твоём ноутбуке)

Нужно один раз всё настроить, потом APK собирается одной кнопкой.

## Что понадобится
- Android Studio (она у тебя есть) — из неё берём Android SDK и Java.
- Godot 4.7.2 (папка `Godot_4.7.2` рядом с игрой) и шаблоны экспорта (они уже стоят, раз собирался Windows-exe).
- Телефон на Android и USB-кабель (или любой способ передать файл на телефон).

## Шаг 1. Поставить компоненты Android SDK
1. Открой Android Studio → `More Actions` (или `Tools`) → **SDK Manager**.
2. Вкладка **SDK Platforms**: отметь **Android 14 (API 34)** или новее.
3. Вкладка **SDK Tools**: отметь галочками
   - **Android SDK Build-Tools** (самая новая версия);
   - **Android SDK Command-line Tools (latest)**;
   - **Android SDK Platform-Tools**;
   - (по желанию) **NDK не нужен**.
4. Нажми **Apply** и дождись загрузки.
5. Запомни путь из поля **Android SDK Location**. Обычно это
   `C:\Users\ТВОЁ_ИМЯ\AppData\Local\Android\Sdk`.

## Шаг 2. Найти Java и ключ
- **Java (JDK)**: у Android Studio она встроена, папка
  `C:\Program Files\Android\Android Studio\jbr`.
  (Нужна именно папка `jbr`, внутри неё лежит `bin\java.exe`.)
- **Ключ подписи**: Android Studio уже создала файл
  `C:\Users\ТВОЁ_ИМЯ\.android\debug.keystore`.
  Если файла нет, создай командой (PowerShell):
  ```
  & "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
  ```

## Шаг 3. Показать Godot, где всё лежит
1. Запусти `Open_in_Godot_Editor.bat` (откроется редактор с игрой).
2. Меню **Editor → Editor Settings → Export → Android**:
   - **Java SDK Path**: `C:\Program Files\Android\Android Studio\jbr`
   - **Android SDK Path**: путь из шага 1
   - **Debug Keystore**: `C:\Users\ТВОЁ_ИМЯ\.android\debug.keystore`
   - **Debug Keystore User**: `androiddebugkey`
   - **Debug Keystore Pass**: `android`
3. Если Godot жалуется на «Build-Tools version …» — поставь в SDK Manager именно ту версию, что названа в сообщении (галочка **Show Package Details** внизу окна SDK Manager позволяет выбрать версию).

## Шаг 4. Собрать APK
1. В Godot: **Project → Export…**. Слева уже есть пресет **Android** (я его настроил: только arm64, сеть включена, во весь экран).
2. Если сверху красная надпись про шаблоны — **Manage Export Templates → Install from file** и выбери `templates.tpz` из папки Godot.
3. Нажми **Export Project**, назови файл `OskolkiDoliny.apk`, галочку **Export With Debug** оставь включённой, **Save**.

## Шаг 5. Поставить на телефон
**Способ А — по кабелю:**
1. На телефоне: **Настройки → О телефоне →** 7 раз нажми «Номер сборки» → появится «Для разработчиков» → включи **Отладка по USB**.
2. Подключи телефон, на нём нажми «Разрешить отладку».
3. В Godot справа вверху появится значок телефона (**Remote Debug**) — жми его, игра сама установится и запустится.

**Способ Б — файлом:**
1. Перекинь `OskolkiDoliny.apk` на телефон (Telegram, Google Диск, кабель).
2. Открой файл на телефоне, разреши «Установка из неизвестных источников» и установи.

## Управление на телефоне
Тап по клетке — идти; два пальца — приблизить и наклонить камеру; долгое нажатие на зверя — приручить/атаковать; щит в бою — тап по нему.

## Если что-то не получилось
Пришли мне текст ошибки из Godot (нижняя панель **Output**) или скриншот — разберёмся.
