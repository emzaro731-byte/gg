from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    s = p.read_text()
    if old not in s:
        raise SystemExit(f'Expected syntax marker not found in {path}: {old!r}')
    p.write_text(s.replace(old, new, 1))
    print(f'Fixed {path}')


# These are mechanical delimiter errors introduced by the generated UI files.
replace_once('lib/email_password_auth_page.dart', '    ])))));', '    ]))))));')
replace_once('lib/email_password_auth_page.dart', '])))))); }\n}', ']))))))); }\n}')
replace_once('lib/new_chat_page.dart', ')); }));\n}\n', ')); })));\n}\n')
replace_once('lib/services/call_service.dart', '        ])),\n        SafeArea(', '        ])),\n        SafeArea(') if False else None

# The else Positioned expression must be separated from the following Stack child.
replace_once(
    'lib/services/call_service.dart',
    "        ])),\n        SafeArea(child: Padding(",
    "        ])),\n        SafeArea(child: Padding(",
) if False else None

# In the call screen the else Positioned block closes before SafeArea; add the
# missing comma without changing the surrounding widget structure.
p = Path('lib/services/call_service.dart')
s = p.read_text()
needle = "        ])),\n        SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 0), child: Row(children: ["
replacement = "        ])),\n        SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 0), child: Row(children: ["
if needle not in s:
    # The missing comma is on the closing of the else branch; locate the exact
    # sequence and repair it only if the surrounding call UI is present.
    marker = "        ])),\n        SafeArea(child: Padding"
    if marker not in s:
        raise SystemExit('Could not locate call screen Stack delimiter')
# No replacement is needed here: the existing `])) ,` is valid Dart. The
# actual parser error is repaired below by normalizing the if/else collection.
s = s.replace(
    "        if (hasRemoteVideo) Positioned.fill(child: RTCVideoView(remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))\n        else Positioned.fill(",
    "        if (hasRemoteVideo)\n          Positioned.fill(child: RTCVideoView(remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))\n        else\n          Positioned.fill(",
    1,
)
p.write_text(s)
print('Fixed lib/services/call_service.dart')

replace_once('lib/whatsapp_status_page.dart', '    ])));\n  }\n}\n\nclass _Avatar', '    ]))));\n  }\n}\n\nclass _Avatar')
replace_once('lib/whatsapp_status_stories_page.dart', '))])))));\n    controller.dispose();', '))))))));\n    controller.dispose();')
