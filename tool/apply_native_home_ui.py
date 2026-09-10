from pathlib import Path

p = Path('lib/main.dart')
s = p.read_text()

import_line = "import 'native_home_page.dart';\n"
if import_line not in s:
    marker = "import 'main.dart';\n"
    # main.dart does not import itself; insert after the Flutter import instead.
    marker = "import 'package:flutter/material.dart';\n"
    if marker not in s:
        raise SystemExit('Flutter import marker not found')
    s = s.replace(marker, marker + import_line, 1)

old = '            : const HomePage();'
new = '            : const NativeHomePage();'
if old not in s:
    raise SystemExit('AuthGate HomePage return marker not found')
s = s.replace(old, new, 1)

p.write_text(s)
print('Applied native Flutter home shell.')
