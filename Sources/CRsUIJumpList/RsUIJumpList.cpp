#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shobjidl.h>
#include <shlobj.h>
#include <objbase.h>
#include <propkey.h>
#include <propvarutil.h>
#include <propsys.h>

#include "RsUIJumpList.h"

namespace {

// Owns a COM init/uninit pair when this thread had not been initialized yet.
// WinUI runs on an MTA, so in practice CoInitializeEx returns S_FALSE (already
// initialized) and we skip the uninit. Keeping it self-contained means the
// bridge is safe to call from any future Swift thread without surprising the
// caller.
struct ComScope {
    HRESULT init;
    explicit ComScope() {
        init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    }
    ~ComScope() {
        if (SUCCEEDED(init) && init != S_FALSE) {
            CoUninitialize();
        }
    }
};

template <typename T> void safe_release(T **pp) {
    if (*pp) {
        (*pp)->Release();
        *pp = nullptr;
    }
}

} // namespace

extern "C" int32_t rs_set_app_user_model_id(const wchar_t *aumid) {
    if (!aumid) {
        return E_INVALIDARG;
    }
    return (int32_t)SetCurrentProcessExplicitAppUserModelID(aumid);
}

extern "C" int32_t rs_get_self_exe_path(wchar_t *buf, int32_t buf_capacity) {
    if (!buf || buf_capacity <= 0) {
        return 0;
    }
    DWORD written = GetModuleFileNameW(nullptr, buf, (DWORD)buf_capacity);
    if (written == 0 || written == (DWORD)buf_capacity) {
        // Either failed or path was truncated. Treat truncation as failure
        // because a partial path would point somewhere wrong if used.
        return 0;
    }
    return (int32_t)written;
}

extern "C" int32_t rs_register_new_window_task(const wchar_t *aumid,
                                               const wchar_t *exe_path,
                                               const wchar_t *argument,
                                               const wchar_t *title,
                                               const wchar_t *icon_path,
                                               int32_t icon_index) {
    if (!aumid || !exe_path || !argument || !title) {
        return E_INVALIDARG;
    }

    ComScope com;
    HRESULT hr = S_OK;

    ICustomDestinationList *dest_list = nullptr;
    IObjectArray *removed = nullptr;
    IObjectCollection *collection = nullptr;
    IShellLinkW *link = nullptr;
    IPropertyStore *prop_store = nullptr;
    IObjectArray *tasks = nullptr;
    PROPVARIANT pv = {};

    hr = CoCreateInstance(CLSID_DestinationList, nullptr, CLSCTX_INPROC_SERVER,
                          IID_PPV_ARGS(&dest_list));
    if (FAILED(hr)) {
        goto done;
    }

    hr = dest_list->SetAppID(aumid);
    if (FAILED(hr)) {
        goto done;
    }

    UINT max_slots;
    hr = dest_list->BeginList(&max_slots, IID_PPV_ARGS(&removed));
    if (FAILED(hr)) {
        goto done;
    }

    hr = CoCreateInstance(CLSID_EnumerableObjectCollection, nullptr,
                          CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&collection));
    if (FAILED(hr)) {
        goto done;
    }

    hr = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                          IID_PPV_ARGS(&link));
    if (FAILED(hr)) {
        goto done;
    }

    hr = link->SetPath(exe_path);
    if (FAILED(hr)) {
        goto done;
    }
    hr = link->SetArguments(argument);
    if (FAILED(hr)) {
        goto done;
    }
    // SetDescription drives the menu item's tooltip.
    hr = link->SetDescription(title);
    if (FAILED(hr)) {
        goto done;
    }
    if (icon_path && icon_path[0] != L'\0') {
        link->SetIconLocation(icon_path, icon_index);
    }

    // The visible label in the jump list comes from PKEY_Title on the link's
    // property store, NOT from SetDescription. Skipping this leaves the entry
    // labeled with the EXE name.
    hr = link->QueryInterface(IID_PPV_ARGS(&prop_store));
    if (FAILED(hr)) {
        goto done;
    }
    hr = InitPropVariantFromString(title, &pv);
    if (FAILED(hr)) {
        goto done;
    }
    hr = prop_store->SetValue(PKEY_Title, pv);
    if (FAILED(hr)) {
        goto done;
    }
    hr = prop_store->Commit();
    if (FAILED(hr)) {
        goto done;
    }

    hr = collection->AddObject(link);
    if (FAILED(hr)) {
        goto done;
    }

    hr = collection->QueryInterface(IID_PPV_ARGS(&tasks));
    if (FAILED(hr)) {
        goto done;
    }

    hr = dest_list->AddUserTasks(tasks);
    if (FAILED(hr)) {
        goto done;
    }

    hr = dest_list->CommitList();

done:
    PropVariantClear(&pv);
    safe_release(&tasks);
    safe_release(&prop_store);
    safe_release(&link);
    safe_release(&collection);
    safe_release(&removed);
    safe_release(&dest_list);
    return (int32_t)hr;
}
