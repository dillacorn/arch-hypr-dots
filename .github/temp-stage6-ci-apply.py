from pathlib import Path

path = Path('.github/workflows/validate-awtarchy.yml')
text = path.read_text(encoding='utf-8')

replacements = [
    (
        '          bash -n awtarchy-install.sh\n          bash -n local/bin/awtarchy\n',
        '          bash -n awtarchy-install.sh\n          bash -n bashrc\n          bash -n local/bin/awtarchy\n',
        'bashrc syntax anchor',
    ),
    (
        '          bash -n tests/test-awtarchy-update-notifications.sh\n          bash -n tests/test-bar-control-actions.sh\n',
        '          bash -n tests/test-awtarchy-update-notifications.sh\n'
        '          bash -n tests/test-installer-aur-scanner-delegation.sh\n'
        '          bash -n tests/test-aur-scanner-updater-migration.sh\n'
        '          bash -n tests/test-aur-helper-policy.sh\n'
        '          bash -n tests/test-aur-scanner-docs.sh\n'
        '          bash -n tests/test-aur-scanner-retirement.sh\n'
        '          bash -n tests/test-package-reconciler.sh\n'
        '          bash -n tests/test-package-reconciler-alternatives.sh\n'
        '          bash -n tests/test-package-reconciler-interrupted-recovery.sh\n'
        '          bash -n tests/test-package-reconciler-aur-equivalents.sh\n'
        '          bash -n tests/test-bar-control-actions.sh\n',
        'scanner test syntax anchor',
    ),
    (
        '          shellcheck \\\n            awtarchy-install.sh \\\n            local/bin/awtarchy \\\n',
        '          shellcheck \\\n            awtarchy-install.sh \\\n            bashrc \\\n            local/bin/awtarchy \\\n',
        'bashrc shellcheck anchor',
    ),
    (
        '            tests/test-awtarchy-update-notifications.sh \\\n            tests/test-bar-control-actions.sh \\\n',
        '            tests/test-awtarchy-update-notifications.sh \\\n'
        '            tests/test-installer-aur-scanner-delegation.sh \\\n'
        '            tests/test-aur-scanner-updater-migration.sh \\\n'
        '            tests/test-aur-helper-policy.sh \\\n'
        '            tests/test-aur-scanner-docs.sh \\\n'
        '            tests/test-aur-scanner-retirement.sh \\\n'
        '            tests/test-package-reconciler.sh \\\n'
        '            tests/test-package-reconciler-alternatives.sh \\\n'
        '            tests/test-package-reconciler-interrupted-recovery.sh \\\n'
        '            tests/test-package-reconciler-aur-equivalents.sh \\\n'
        '            tests/test-bar-control-actions.sh \\\n',
        'scanner test shellcheck anchor',
    ),
    (
        '          bash tests/test-awtarchy-update-notifications.sh\n          bash tests/test-bar-control-actions.sh\n',
        '          bash tests/test-awtarchy-update-notifications.sh\n'
        '          bash tests/test-installer-aur-scanner-delegation.sh\n'
        '          bash tests/test-aur-scanner-updater-migration.sh\n'
        '          bash tests/test-aur-helper-policy.sh\n'
        '          bash tests/test-aur-scanner-docs.sh\n'
        '          bash tests/test-aur-scanner-retirement.sh\n'
        '          bash tests/test-package-reconciler.sh\n'
        '          bash tests/test-package-reconciler-alternatives.sh\n'
        '          bash tests/test-package-reconciler-interrupted-recovery.sh\n'
        '          bash tests/test-package-reconciler-aur-equivalents.sh\n'
        '          bash tests/test-bar-control-actions.sh\n',
        'scanner test execution anchor',
    ),
]

for old, new, label in replacements:
    if text.count(old) != 1:
        raise SystemExit(f'unexpected {label}: found {text.count(old)} matches')
    text = text.replace(old, new, 1)

required = [
    'bash -n bashrc',
    'shellcheck \\\n            awtarchy-install.sh \\\n            bashrc \\\',
    'bash tests/test-installer-aur-scanner-delegation.sh',
    'bash tests/test-aur-scanner-updater-migration.sh',
    'bash tests/test-aur-helper-policy.sh',
    'bash tests/test-aur-scanner-docs.sh',
    'bash tests/test-aur-scanner-retirement.sh',
    'bash tests/test-package-reconciler.sh',
    'bash tests/test-package-reconciler-alternatives.sh',
    'bash tests/test-package-reconciler-interrupted-recovery.sh',
    'bash tests/test-package-reconciler-aur-equivalents.sh',
]
for needle in required:
    if needle not in text:
        raise SystemExit(f'missing Stage 6 CI contract after edit: {needle!r}')

path.write_text(text, encoding='utf-8')
