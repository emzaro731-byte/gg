from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    s = p.read_text()
    if old not in s:
        raise SystemExit(f'Expected syntax marker not found in {path}: {old!r}')
    p.write_text(s.replace(old, new, 1))
    print(f'Fixed {path}')


replace_once('lib/email_password_auth_page.dart', '    ])))));', '    ]))))));')
replace_once('lib/email_password_auth_page.dart', '])))))); }\n}', ']))))))); }\n}')
replace_once('lib/new_chat_page.dart', ')); }));\n}\n', ')); })));\n}\n')
replace_once(
    'lib/services/call_service.dart',
    '        ])),\n        SafeArea(child: Padding',
    '        ]))),\n        SafeArea(child: Padding',
)

p = Path('lib/services/call_service.dart')
s = p.read_text()
s = s.replace(
    "        if (hasRemoteVideo) Positioned.fill(child: RTCVideoView(remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))\n        else Positioned.fill(",
    "        if (hasRemoteVideo)\n          Positioned.fill(child: RTCVideoView(remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))\n        else\n          Positioned.fill(",
    1,
)
p.write_text(s)
print('Normalized call-screen collection-if')

replace_once('lib/whatsapp_status_page.dart', '    ])));\n  }\n}\n\nclass _Avatar', '    ]))));\n  }\n}\n\nclass _Avatar')
replace_once('lib/whatsapp_status_stories_page.dart', '])))));\n    controller.dispose();', '))))));\n    controller.dispose();')
