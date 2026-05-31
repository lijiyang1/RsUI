#pragma once

#include <stdint.h>
#include <wchar.h>

#ifdef __cplusplus
extern "C" {
#endif

// Sets the current process AppUserModelID. The taskbar uses this ID to group
// windows and to look up the jump list registered for this app, so it MUST
// match the AUMID passed to rs_register_new_window_task. Call once early in
// process startup, before any HWND is created. Returns 0 on success.
int32_t rs_set_app_user_model_id(const wchar_t *aumid);

// Writes the full path of the current executable into buf (wchar_t count in
// buf_capacity). Returns the number of characters written (not including the
// null terminator), or 0 on failure. Provided here to avoid pulling a second
// C bridge into Swift just for GetModuleFileNameW.
int32_t rs_get_self_exe_path(wchar_t *buf, int32_t buf_capacity);

// Registers a single "Tasks"-category jump list entry that re-launches the
// current EXE with the supplied argument (typically L"--new-window"). The
// list is replaced atomically on every call (idempotent). Returns 0 on
// success, non-zero HRESULT on failure.
int32_t rs_register_new_window_task(const wchar_t *aumid,
                                    const wchar_t *exe_path,
                                    const wchar_t *argument,
                                    const wchar_t *title,
                                    const wchar_t *icon_path,
                                    int32_t icon_index);

#ifdef __cplusplus
}
#endif
