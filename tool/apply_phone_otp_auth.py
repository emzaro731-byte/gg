from pathlib import Path

main_path = Path('lib/main.dart')
auth_path = Path('lib/email_password_auth_page.dart')

main = main_path.read_text(encoding='utf-8')
auth = auth_path.read_text(encoding='utf-8')

# The current main.dart already imports the dedicated email/password + OTP
# page and AuthGate points to it. In that case there is nothing to inject.
if 'email_password_auth_page.dart' in main and 'email_auth.LoginPage' in main:
    print('Email/password + 8-digit email OTP authentication is already applied to lib/main.dart')
    raise SystemExit(0)

# Backward-compatible path for older main.dart versions that still contain
# an inline LoginPage. Replace that class with the dedicated auth page.
login_marker = 'class LoginPage extends StatefulWidget {'
home_marker = 'class HomePage extends StatefulWidget {'

if login_marker not in main:
    raise RuntimeError(
        'lib/main.dart has no inline LoginPage and is not wired to '
        'email_password_auth_page.dart. Update AuthGate manually or use the '
        'current main.dart template.'
    )

if home_marker not in main:
    raise RuntimeError('Could not find HomePage marker in lib/main.dart.')

start = main.index(login_marker)
end = main.index(home_marker)
auth_start = auth.index(login_marker)
auth_code = auth[auth_start:]

if "import 'email_password_auth_page.dart' as email_auth;" not in main:
    import_anchor = "import 'supabase_flutter.dart';"
    # Supabase import is package-qualified, so add the auth import after the
    # app's existing local imports instead of relying on an exact anchor.
    lines = main.splitlines()
    insert_at = 0
    for i, line in enumerate(lines):
        if line.startswith("import "):
            insert_at = i + 1
    lines.insert(insert_at, "import 'email_password_auth_page.dart' as email_auth;")
    main = '\n'.join(lines) + ('\n' if main.endswith('\n') else '')
    start = main.index(login_marker)
    end = main.index(home_marker)

main = main[:start] + auth_code + '\n' + main[end:]

# Ensure AuthGate uses the dedicated page if an older version still used the
# inline LoginPage symbol.
main = main.replace(
    'const LoginPage()',
    'const email_auth.LoginPage()',
)

main_path.write_text(main, encoding='utf-8')
print('Applied email/password authentication with 8-digit email verification OTP to lib/main.dart')
