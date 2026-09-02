from pathlib import Path

source_path = Path('.github/temp-stage1-direct-scanner-apply.py')
source = source_path.read_text(encoding='utf-8')

start = source.index('def edit_aur_stage(stage: str) -> str:\n')
end_marker = '\n\ntext = edit_function(text, "install_aur_repo_apps_stage", edit_aur_stage)'
end = source.index(end_marker, start)

replacement = r'''def edit_aur_stage(stage: str) -> str:
    replacements = (
        ("  ensure_aur_guard_requirements\n", "  ensure_aur_install_requirements\n", "requirements call"),
        ('    log "Installing selected AUR packages through AUR Guard practical mode..."',
         '    log "Installing selected AUR packages through upstream aur-scanner..."',
         "stage log"),
        ('      log "Installing tlpui through AUR Guard practical mode..."',
         '      log "Installing tlpui through upstream aur-scanner..."',
         "tlpui log"),
        ('      if run_aur_guard_as_target aurinstall tlpui && pacman -Qq tlpui >/dev/null 2>&1; then',
         '      if install_aur_with_scanner tlpui && pacman -Qq tlpui >/dev/null 2>&1; then',
         "tlpui transaction"),
    )
    for old, new, label in replacements:
        if stage.count(old) != 1:
            raise SystemExit(f"installer AUR stage has unexpected {label}")
        stage = stage.replace(old, new, 1)

    preamble = "  ensure_aur_install_requirements\n  ensure_aur_sudo_access\n  ensure_yay\n"
    if stage.count(preamble) != 1:
        raise SystemExit("could not locate installer AUR stage preamble")
    stage = stage.replace(preamble, preamble + "  ensure_aur_scanner\n", 1)

    obs_call = '          install_obs_pipewire_audio_capture_package'
    obs_guard = '''          if ! install_obs_pipewire_audio_capture_package; then
            warn "AUR package failed: ${pkg}. Continuing with remaining selections."
            continue
          fi'''
    if stage.count(obs_call) != 1:
        raise SystemExit("could not locate selected OBS AUR install call")
    stage = stage.replace(obs_call, obs_guard, 1)

    scanner_call = '          run_aur_guard_as_target aurinstall "$pkg"'
    scanner_guard = '''          if ! install_aur_with_scanner "$pkg"; then
            warn "AUR package failed: ${pkg}. Continuing with remaining selections."
            continue
          fi'''
    if stage.count(scanner_call) != 1:
        raise SystemExit("could not locate selected AUR transaction call")
    stage = stage.replace(scanner_call, scanner_guard, 1)
    return stage'''

source = source[:start] + replacement + source[end:]
exec(compile(source, str(source_path), 'exec'), {'__name__': '__main__'})
