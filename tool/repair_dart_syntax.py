from pathlib import Path


def replace_if_present(path: str, old: str, new: str) -> None:
    p = Path(path)
    s = p.read_text()
    if old not in s:
        print(f'No repair needed in {path}')
        return
    p.write_text(s.replace(old, new, 1))
    print(f'Fixed {path}')


# These repairs are intentionally idempotent because GitHub Actions starts from
# the latest committed source, where a previous repair may already be applied.
replace_if_present('lib/email_password_auth_page.dart', '    ])))));', '    ]))))));')
replace_if_present('lib/email_password_auth_page.dart', '])))))); }\n}', ']))))))); }\n}')

# NewChatPage is now committed in a fully formatted, syntactically valid form.
# Do not perform the old fragile marker replacement here.

replace_if_present(
    'lib/services/call_service.dart',
    '        ])),\n        SafeArea(child: Padding',
    '        ]))),\n        SafeArea(child: Padding',
)

p = Path('lib/services/call_service.dart')
s = p.read_text()
old = "        if (hasRemoteVideo) Positioned.fill(child: RTCVideoView(remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))\n        else Positioned.fill("
new = "        if (hasRemoteVideo)\n          Positioned.fill(child: RTCVideoView(remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))\n        else\n          Positioned.fill("
if old in s:
    p.write_text(s.replace(old, new, 1))
    print('Normalized call-screen collection-if')
else:
    print('No call-screen collection-if repair needed')

replace_if_present(
    'lib/whatsapp_status_page.dart',
    '    ])));\n  }\n}\n\nclass _Avatar',
    '    ]))));\n  }\n}\n\nclass _Avatar',
)
replace_if_present(
    'lib/whatsapp_status_stories_page.dart',
    '])))));\n    controller.dispose();',
    '))))));\n    controller.dispose();',
)

print('Dart syntax repair pass complete')
