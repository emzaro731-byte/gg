from pathlib import Path

p = Path('lib/main.dart')
s = p.read_text()

import_line = "import 'services/firebase_messaging_service.dart';\n"
if import_line not in s:
    anchor = "import 'services/notification_service.dart';\n"
    if anchor not in s:
        raise SystemExit('notification_service import anchor not found')
    s = s.replace(anchor, anchor + import_line, 1)

init_old = "    await NotificationService.instance.initialize();\n    runApp(const GGApp());"
init_new = "    await NotificationService.instance.initialize();\n    await FirebaseMessagingService.instance.initialize();\n    runApp(const GGApp());"
if init_old in s:
    s = s.replace(init_old, init_new, 1)

register_old = "    if (appSettings.notificationsEnabled) {\n      await NotificationService.instance.requestPermission();\n    }\n\n    notificationChannel ="
register_new = "    if (appSettings.notificationsEnabled) {\n      await NotificationService.instance.requestPermission();\n    }\n\n    await FirebaseMessagingService.instance.registerCurrentUser();\n\n    notificationChannel ="
if register_old in s:
    s = s.replace(register_old, register_new, 1)

p.write_text(s)
