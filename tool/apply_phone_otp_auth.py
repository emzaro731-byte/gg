from pathlib import Path

main_path = Path('lib/main.dart')
auth_path = Path('lib/phone_auth_page.dart')

main = main_path.read_text(encoding='utf-8')
auth = auth_path.read_text(encoding='utf-8')

start = main.index('class LoginPage extends StatefulWidget {')
end = main.index('class HomePage extends StatefulWidget {')

auth_start = auth.index('class LoginPage extends StatefulWidget {')
auth_code = auth[auth_start:]

main = main[:start] + auth_code + '\n' + main[end:]
main_path.write_text(main, encoding='utf-8')
print('Applied passwordless phone OTP authentication to lib/main.dart')
