const state = {
  password: localStorage.getItem("spt-web-password") || "",
  busy: false,
  refreshInFlight: false,
  lastServerLogKey: "",
  lastBepInExLogKey: "",
  activeTab: "control",
  roots: {
    sp: { visible: true, path: "", items: [], parent: null, search: "" },
    coop: { visible: true, path: "", items: [], parent: null, search: "" },
  },
  editingRoot: "",
  editingPath: "",
};

const el = {
  loginForm: document.getElementById("loginForm"),
  passwordInput: document.getElementById("passwordInput"),
  controls: document.getElementById("controls"),
  statusText: document.getElementById("statusText"),
  modeValue: document.getElementById("modeValue"),
  serverValue: document.getElementById("serverValue"),
  headlessValue: document.getElementById("headlessValue"),
  portValue: document.getElementById("portValue"),
  serverLog: document.getElementById("serverLog"),
  bepinexLog: document.getElementById("bepinexLog"),
  serverLogPath: document.getElementById("serverLogPath"),
  bepinexLogPath: document.getElementById("bepinexLogPath"),
  controlView: document.getElementById("controlView"),
  filesView: document.getElementById("filesView"),
  fileManager: document.getElementById("fileManager"),
  fileMessage: document.getElementById("fileMessage"),
  editorTitle: document.getElementById("editorTitle"),
  editorSave: document.getElementById("editorSave"),
  editorClose: document.getElementById("editorClose"),
  fileEditor: document.getElementById("fileEditor"),
  rootToggles: document.querySelectorAll("[data-root-toggle]"),
  rootPanes: {
    sp: document.getElementById("spPane"),
    coop: document.getElementById("coopPane"),
  },
  filePaths: {
    sp: document.getElementById("spFilePath"),
    coop: document.getElementById("coopFilePath"),
  },
  fileLists: {
    sp: document.getElementById("spFileList"),
    coop: document.getElementById("coopFileList"),
  },
};

function preventDefault(event) {
  event.preventDefault();
  event.stopPropagation();
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function rootLabel(root) {
  return root === "coop" ? "Coop" : "SP";
}

function setUnlocked(unlocked) {
  el.loginForm.classList.toggle("hidden", unlocked);
  el.controls.classList.toggle("hidden", !unlocked);
}

function setTab(tab) {
  state.activeTab = tab;
  document.querySelectorAll("[data-tab]").forEach((button) => {
    button.classList.toggle("active", button.dataset.tab === tab);
  });
  el.controlView.classList.toggle("active", tab === "control");
  el.filesView.classList.toggle("active", tab === "files");
  if (tab === "files") {
    loadVisibleFilePanes();
  }
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      "X-SPT-Password": state.password,
      ...(options.headers || {}),
    },
  });

  const data = await response.json();
  if (!response.ok || data.ok === false) {
    throw new Error(data.error || `Request failed: ${response.status}`);
  }

  return data;
}

function renderStatus(status) {
  const mode = status.currentMode || "-";
  el.modeValue.textContent = mode;
  el.serverValue.textContent = status.serverRunning ? "Running" : "Stopped";
  el.headlessValue.textContent = status.headlessRunning ? "Running" : "Stopped";
  el.portValue.textContent = status.serverPortOpen ? "Open" : "Closed";
  el.statusText.textContent = status.message || status.lastAction || "Ready";
  el.serverLogPath.textContent = status.serverLogPath || "No active server log";
  el.bepinexLogPath.textContent = status.bepinexLogPath || "";
}

function renderLog(target, payload, pathTarget) {
  pathTarget.textContent = payload.path || "No log file selected";
  if (!payload.lines || payload.lines.length === 0) {
    target.innerHTML = '<span class="line-debug">No log lines available.</span>';
    target.scrollTop = target.scrollHeight;
    return;
  }

  target.innerHTML = payload.lines
    .map((line, index) => `<span class="line-${payload.levels?.[index] || "info"}">${escapeHtml(line)}</span>`)
    .join("\n");
  target.scrollTop = target.scrollHeight;
}

async function refresh() {
  if (!state.password) {
    setUnlocked(false);
    return;
  }

  if (state.refreshInFlight || state.busy) {
    return;
  }

  state.refreshInFlight = true;

  try {
    const statusPayload = await api("/api/status");
    setUnlocked(true);
    renderStatus(statusPayload.status);

    if (state.activeTab !== "control") {
      return;
    }

    const [serverLog, bepinexLog] = await Promise.all([
      api("/api/logs?type=server"),
      api("/api/logs?type=bepinex"),
    ]);

    const serverKey = `${serverLog.path || ""}:${serverLog.lines?.length || 0}:${serverLog.lines?.at(-1) || ""}`;
    if (serverKey !== state.lastServerLogKey) {
      state.lastServerLogKey = serverKey;
      renderLog(el.serverLog, serverLog, el.serverLogPath);
    } else {
      el.serverLogPath.textContent = serverLog.path || "No log file selected";
    }

    const bepinexKey = `${bepinexLog.path || ""}:${bepinexLog.lines?.length || 0}:${bepinexLog.lines?.at(-1) || ""}`;
    if (bepinexKey !== state.lastBepInExLogKey) {
      state.lastBepInExLogKey = bepinexKey;
      renderLog(el.bepinexLog, bepinexLog, el.bepinexLogPath);
    } else {
      el.bepinexLogPath.textContent = bepinexLog.path || "No log file selected";
    }
  } catch (error) {
    setUnlocked(false);
    el.statusText.textContent = error.message;
  } finally {
    state.refreshInFlight = false;
  }
}

function formatSize(size) {
  if (size === null || size === undefined) return "";
  if (size < 1024) return `${size} B`;
  if (size < 1048576) return `${(size / 1024).toFixed(1)} KB`;
  return `${(size / 1048576).toFixed(1)} MB`;
}

function setFileMessage(message) {
  el.fileMessage.textContent = message || "";
}

function visibleRoots() {
  return Object.keys(state.roots).filter((root) => state.roots[root].visible);
}

function updateFileLayout() {
  const roots = visibleRoots();
  el.fileManager.classList.toggle("editor-only", roots.length === 0);
  el.fileManager.classList.toggle("single-root", roots.length === 1);
  el.fileManager.classList.toggle("split-both", roots.length === 2);

  for (const root of Object.keys(state.roots)) {
    el.rootPanes[root].classList.toggle("hidden", !state.roots[root].visible);
  }

  el.rootToggles.forEach((button) => {
    const root = button.dataset.rootToggle;
    button.classList.toggle("active", state.roots[root].visible);
  });
}

function renderFiles(root, listing) {
  const pane = state.roots[root];
  pane.path = listing.path || "";
  pane.items = listing.items || [];
  pane.parent = listing.parent;
  el.filePaths[root].textContent = `${rootLabel(root)}: \\${pane.path}`;

  const upButton = document.querySelector(`[data-file-up="${root}"]`);
  if (upButton) upButton.disabled = !pane.parent;

  const rows = [];
  if (!pane.search && pane.parent !== null && pane.parent !== undefined) {
    rows.push(`
      <div class="file-row">
        <button type="button" data-open-folder="${escapeHtml(pane.parent)}" data-root="${root}" class="file-name">..</button>
        <span class="file-meta">folder</span>
        <span></span>
      </div>
    `);
  }

  const query = pane.search.trim().toLowerCase();
  const visibleItems = query
    ? pane.items.filter((item) => item.name.toLowerCase().includes(query))
    : pane.items;

  for (const item of visibleItems) {
    const rootAttr = `data-root="${root}"`;
    const actions = item.type === "folder"
      ? `<button type="button" data-open-folder="${escapeHtml(item.path)}" ${rootAttr}>Open</button>`
      : item.editable
        ? `<button type="button" data-edit-file="${escapeHtml(item.path)}" ${rootAttr}>Edit</button>`
        : `<span class="file-meta">binary</span>`;
    rows.push(`
      <div class="file-row">
        <button type="button" class="file-name" ${item.type === "folder" ? `data-open-folder="${escapeHtml(item.path)}" ${rootAttr}` : item.editable ? `data-edit-file="${escapeHtml(item.path)}" ${rootAttr}` : "disabled"}>
          ${item.type === "folder" ? "[D]" : "[F]"} ${escapeHtml(item.name)}
        </button>
        <span class="file-meta">${escapeHtml(formatSize(item.size))}</span>
        <span>${actions} <button type="button" class="danger" data-delete-path="${escapeHtml(item.path)}" ${rootAttr}>Trash</button></span>
      </div>
    `);
  }

  el.fileLists[root].innerHTML = rows.join("") || '<div class="file-row"><span class="file-name">Empty folder</span><span></span><span></span></div>';
}

async function loadFiles(root, path = state.roots[root].path) {
  if (!state.password || !state.roots[root].visible) return;
  try {
    setFileMessage(`Loading ${rootLabel(root)}...`);
    const payload = await api(`/api/files/list?root=${encodeURIComponent(root)}&path=${encodeURIComponent(path || "")}`);
    renderFiles(root, payload.listing);
    setFileMessage("");
  } catch (error) {
    setFileMessage(error.message);
  }
}

function loadVisibleFilePanes() {
  updateFileLayout();
  for (const root of visibleRoots()) {
    loadFiles(root);
  }
}

function rerenderCurrentFiles(root) {
  renderFiles(root, {
    path: state.roots[root].path,
    parent: state.roots[root].parent,
    items: state.roots[root].items,
  });
}

async function editFile(root, path) {
  try {
    const payload = await api(`/api/files/read?root=${encodeURIComponent(root)}&path=${encodeURIComponent(path)}`);
    state.editingRoot = root;
    state.editingPath = path;
    el.editorTitle.textContent = `${rootLabel(root)}: ${path || "Editor"}`;
    el.fileEditor.value = payload.file.content || "";
    el.fileEditor.disabled = false;
  } catch (error) {
    setFileMessage(error.message);
  }
}

async function saveEditor() {
  if (!state.editingRoot || !state.editingPath) return;
  try {
    await api("/api/files/save", {
      method: "POST",
      body: JSON.stringify({
        root: state.editingRoot,
        path: state.editingPath,
        content: el.fileEditor.value,
      }),
    });
    setFileMessage("Saved.");
    await loadFiles(state.editingRoot);
  } catch (error) {
    setFileMessage(error.message);
  }
}

function closeEditor() {
  state.editingRoot = "";
  state.editingPath = "";
  el.editorTitle.textContent = "Editor";
  el.fileEditor.value = "";
  el.fileEditor.disabled = true;
}

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = String(reader.result || "");
      resolve(result.includes(",") ? result.split(",", 2)[1] : result);
    };
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(file);
  });
}

async function uploadFiles(root, files) {
  try {
    for (const file of files) {
      setFileMessage(`Uploading ${file.name} to ${rootLabel(root)}...`);
      const contentBase64 = await fileToBase64(file);
      await api("/api/files/upload", {
        method: "POST",
        body: JSON.stringify({
          root,
          path: state.roots[root].path,
          name: file.name,
          contentBase64,
        }),
      });
    }
    setFileMessage("Upload complete.");
    await loadFiles(root);
  } catch (error) {
    setFileMessage(error.message);
  }
}

async function trashPath(root, path) {
  if (!confirm(`Move to trash?\n${rootLabel(root)}: ${path}`)) return;
  try {
    await api("/api/files/delete", {
      method: "POST",
      body: JSON.stringify({ root, path }),
    });
    if (state.editingRoot === root && state.editingPath === path) {
      closeEditor();
    }
    setFileMessage("Moved to trash.");
    await loadFiles(root);
  } catch (error) {
    setFileMessage(error.message);
  }
}

async function runAction(action) {
  if (state.busy) return;

  state.busy = true;
  document.querySelectorAll("button").forEach((button) => {
    button.disabled = true;
  });
  el.statusText.textContent = "Working...";

  try {
    const result = await api("/api/action", {
      method: "POST",
      body: JSON.stringify({ action }),
    });
    renderStatus(result.status);
    await refresh();
  } catch (error) {
    el.statusText.textContent = error.message;
  } finally {
    state.busy = false;
    document.querySelectorAll("button").forEach((button) => {
      button.disabled = false;
    });
  }
}

el.loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  state.password = el.passwordInput.value;
  localStorage.setItem("spt-web-password", state.password);
  await refresh();
});

document.querySelectorAll("[data-action]").forEach((button) => {
  button.addEventListener("click", () => runAction(button.dataset.action));
});

document.querySelectorAll("[data-tab]").forEach((button) => {
  button.addEventListener("click", () => setTab(button.dataset.tab));
});

el.rootToggles.forEach((button) => {
  button.addEventListener("click", () => {
    const root = button.dataset.rootToggle;
    state.roots[root].visible = !state.roots[root].visible;
    updateFileLayout();
    if (state.roots[root].visible) {
      loadFiles(root);
    }
  });
});

document.querySelectorAll("[data-file-up]").forEach((button) => {
  button.addEventListener("click", () => {
    const root = button.dataset.fileUp;
    const parts = state.roots[root].path.split(/[\\/]+/).filter(Boolean);
    parts.pop();
    loadFiles(root, parts.join("\\"));
  });
});

document.querySelectorAll("[data-file-upload]").forEach((input) => {
  input.addEventListener("change", async () => {
    const root = input.dataset.fileUpload;
    const files = Array.from(input.files || []);
    input.value = "";
    if (files.length > 0) {
      await uploadFiles(root, files);
    }
  });
});

document.querySelectorAll("[data-file-search]").forEach((input) => {
  input.addEventListener("input", () => {
    const root = input.dataset.fileSearch;
    state.roots[root].search = input.value;
    rerenderCurrentFiles(root);
  });
});

document.querySelectorAll("[data-file-list]").forEach((list) => {
  ["dragenter", "dragover"].forEach((eventName) => {
    list.addEventListener(eventName, (event) => {
      preventDefault(event);
      if (state.activeTab === "files") {
        list.classList.add("drag-over");
        setFileMessage(`Drop files to upload to ${rootLabel(list.dataset.fileList)}.`);
      }
    });
  });

  ["dragleave", "drop"].forEach((eventName) => {
    list.addEventListener(eventName, (event) => {
      preventDefault(event);
      list.classList.remove("drag-over");
    });
  });

  list.addEventListener("drop", async (event) => {
    const root = list.dataset.fileList;
    const files = Array.from(event.dataTransfer?.files || []);
    if (files.length > 0) {
      await uploadFiles(root, files);
    }
  });

  list.addEventListener("click", (event) => {
    const folderButton = event.target.closest("[data-open-folder]");
    if (folderButton) {
      loadFiles(folderButton.dataset.root, folderButton.dataset.openFolder || "");
      return;
    }

    const editButton = event.target.closest("[data-edit-file]");
    if (editButton) {
      editFile(editButton.dataset.root, editButton.dataset.editFile);
      return;
    }

    const deleteButton = event.target.closest("[data-delete-path]");
    if (deleteButton) {
      trashPath(deleteButton.dataset.root, deleteButton.dataset.deletePath);
    }
  });
});

el.editorSave.addEventListener("click", saveEditor);
el.editorClose.addEventListener("click", closeEditor);

document.addEventListener("keydown", async (event) => {
  const isSaveShortcut = (event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "s";
  if (!isSaveShortcut || state.activeTab !== "files" || !state.editingPath) return;

  preventDefault(event);
  await saveEditor();
});

updateFileLayout();

if (state.password) {
  el.passwordInput.value = state.password;
  refresh();
}

setInterval(refresh, 3000);
