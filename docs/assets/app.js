/* ==========================================================
   Clip 产品介绍页 — 交互脚本
   中英双语切换 · 深浅色主题 · 复制按钮 · 进场动画 · 导航高亮
   ========================================================== */
(function () {
  "use strict";

  /* ---------- 语言包 ---------- */
  var MESSAGES = {
    zh: {
      "html.title": "Clip — macOS 剪贴板历史管理器",
      "nav.features": "功能特性",
      "nav.showcase": "截图",
      "nav.download": "下载安装",
      "nav.privacy": "隐私",
      "nav.opensource": "开源",

      "hero.badgeLatest": "最新版 v1.0.9",
      "hero.badgeOS": "macOS 27 或更高",
      "hero.title": "按一下快捷键，<br>历史就在手边。",
      "hero.sub": 'Clip 是一款常驻 macOS 菜单栏的剪贴板历史管理器。复制过的一切——文本、链接、色值、代码、图片——都安静地记着。<kbd>⇧⌘V</kbd> 随叫随到，回车即粘。',
      "hero.ctaDownload": "下载 Clip for macOS",
      "hero.ctaGithub": "GitHub 仓库",
      "hero.ctaMeta": "Clip-1.0.9.dmg · 826 KB · 零第三方依赖 · 数据只在本机",
      "hero.shotCaption": "主面板：分类筛选、实时计数、来源标注，向右展开预览",

      "chip.text": "文本",
      "chip.image": "图片",
      "chip.link": "链接",

      "intro.q1": "「你复制了一段代码，切去查文档；回头再要用，剪贴板已经被新内容覆盖了。」",
      "intro.a1": "Clip 在后台安静地记下你复制过的一切。没有窗口常驻，没有标签页，不用先想「我要找什么」——历史就摊在你面前，翻一下就行。",

      "features.eyebrow": "核心能力",
      "features.title": "一个快捷键，管好复制过的一切",
      "features.lead": "从呼出、选择到粘贴，全流程键盘完成；细节处也都替你想到了。",

      "f1.title": "什么都记得",
      "f1.desc": "文本、链接、颜色值、代码、文件路径、图片，复制什么记什么，每条都标着来自哪个应用。截图、设计稿、复制的色值，各自归位不打架。",
      "f2.title": "呼出即用",
      "f2.desc": "贴着光标弹出，鼠标在哪就在哪出现；屏幕放不下时自动翻到另一侧。高度固定，条目再多也只在列表内部滚动——呼出的瞬间窗口不会上下跳。",
      "f3.title": "回车即粘",
      "f3.desc": "选中一条按回车，直接送到当前光标处，不用手动切回上一个应用。<kbd>⌥↵</kbd> 还能以纯文本粘贴，不带格式。",
      "f4.title": "看得清再决定",
      "f4.desc": "选中一条按 <kbd>→</kbd> 向右展开预览，左上角固定不动，正在看的列表不会横向跳动。图片点一下放大到屏幕尺寸比对，任意处或 <kbd>esc</kbd> 收起。",
      "f5.title": "菜单栏里也能点",
      "f5.desc": "不方便用快捷键时，点状态栏图标也行：开关记录、看最近几条、直接从菜单栏粘贴。",
      "f6.title": "桌面上也放一块",
      "f6.desc": "通知中心 / 桌面小组件显示最近几条历史，点一下即复制，点空白处呼出完整面板。",
      "f7.title": "找到你要的那一条",
      "f7.desc": "顶部搜索框实时过滤。<kbd>⌘P</kbd> 固定过的条目永远不会被自动清理，参数、地址、常备片段这类东西可以一直留在手边。",
      "f8.title": "隐私是默认项",
      "f8.desc": "密码管理器标记为机密的剪贴板内容默认不记录，不记录自己回填的内容，可随时暂停记录——数据只在你本机。",
      "f9.title": "设置立即生效",
      "f9.desc": "语言、深浅色、列表密度、保留条数与时长、呼出方式，所有改动立即生效，没有「应用」按钮，不需要重启。",

      "keys.eyebrow": "全键盘操作",
      "keys.title": "手不用离开键盘",
      "keys.lead": "从呼出、选择到粘贴，全流程键盘完成。呼出键可改成任意组合键，速查面板就在设置里。",
      "keys.demoPaste": "粘贴",
      "keys.demoClose": "关闭",
      "keys.demoPreview": "展开预览",
      "k1": "呼出 / 收起（可改成任意组合键）",
      "k2": "选择",
      "k3": "粘贴到光标处",
      "k4": "以纯文本粘贴（不带格式）",
      "k5": "展开 / 收起预览",
      "k6": "直接粘贴第 N 条",
      "k7": "置顶 / 取消置顶",
      "k8": "删除这一条",
      "k9": "收起面板",

      "show.eyebrow": "实际样子",
      "show.title": "长这样",
      "show.lead": "原生 SwiftUI + AppKit，跟随系统 Liquid Glass 与深浅色，没有一行第三方 UI 库。",
      "show.c1": "紧凑面板 —— 条目再多，窗口也不跳",
      "show.c2": "菜单栏面板 —— 点状态栏图标即可操作",
      "show.c3": "设置 · 通用 —— 记录开关、条数与时长上限",
      "show.c4": "设置 · 外观 —— 深浅色、密度、面板尺寸",

      "dl.eyebrow": "下载与安装",
      "dl.title": "五分钟装好，按下快捷键就能用",
      "dl.lead": "通过 GitHub Releases 分发。安装包由 CI 自动构建，附 SHA-256 校验值。",
      "dl.cardSub": "macOS 剪贴板历史管理器",
      "dl.metaVersion": "最新版本",
      "dl.metaAsset": "安装包",
      "dl.metaReq": "系统要求",
      "dl.metaReqVal": "macOS 27（Golden Gate）或更高",
      "dl.metaLicense": "许可",
      "dl.btnDownload": "下载 Clip-1.0.9.dmg",
      "dl.copySha": "复制 SHA-256",
      "dl.copyCmd": "复制命令",
      "dl.verify": "下载后校验：",
      "dl.allVersions": "查看所有版本与更新日志",
      "dl.note": "辅助功能授权与自签名证书绑定，更新版本后无需重新授权。卸载：退出 Clip 后删掉「应用程序」里的 Clip.app，数据目录 ~/Library/Application Support/Clip 可一并删除。",

      "s1.title": "下载 .dmg",
      "s1.desc": "从 GitHub Releases 下载最新版的 Clip-1.0.9.dmg。也可以点上方按钮直接开始下载。",
      "s2.title": "拖进「应用程序」",
      "s2.desc": "打开 .dmg，把 Clip 拖到「应用程序」文件夹，然后弹出镜像。",
      "s3.title": "首次启动（重要）",
      "s3.desc": "Clip 使用自签名证书，Gatekeeper 可能提示「无法验证开发者」。在「应用程序」里右键 → 打开，再点「打开」；或在「终端」执行：",
      "s3.desc2": "之后启动，菜单栏会出现剪贴板图标。",
      "s4.title": "开启自动粘贴（可选）",
      "s4.desc": "想让 Clip 帮你按下 ⌘V，去 系统设置 → 隐私与安全性 → 辅助功能 勾选 Clip。不授权也能用，只是变成「复制好等你手动粘」并给个提示。",
      "s5.title": "按下 ⇧⌘V，开始使用",
      "s5.desc": "之后每次复制都会被记下。置顶（⌘P）过的条目永远不会被自动清理。",

      "pv.eyebrow": "隐私",
      "pv.title": "剪贴板能看见你复制的一切，所以这件事得说清楚",
      "pv1.title": "默认忽略机密内容",
      "pv1.desc": "密码管理器（1Password、TypeIt4me 等）标记为机密的剪贴板内容不会被记录。",
      "pv2.title": "不记录回填内容",
      "pv2.desc": "不记录自己回填的内容，也不会把你的历史再抄一遍。",
      "pv3.title": "随时暂停记录",
      "pv3.desc": "菜单栏一键开关，想安静的时候就安静。",
      "pv4.title": "数据只在你本机",
      "pv4.desc": "历史存在 ~/Library/Application Support/Clip，不上传、不同步、没有账号。",
      "pv5.title": "可设上限",
      "pv5.desc": "条数（默认 300）和保留时长都可调，还能一键清空全部数据。",
      "pv6.title": "开源可审计",
      "pv6.desc": "代码在 GitHub 上完全公开，每一行都可以自己看。",

      "os.eyebrow": "开源",
      "os.title": "MIT 协议，欢迎折腾",
      "os.lead": "基于 MIT 协议发布，可以自由使用、修改与分发。",
      "os.stackTitle": "技术栈",
      "os.li1": "原生 SwiftUI + AppKit，零第三方依赖",
      "os.li2": "菜单栏代理（LSUIElement）常驻，不占 Dock",
      "os.li3": "SwiftData 增量持久化，图片等二进制外置为文件",
      "os.li4": "Carbon RegisterEventHotKey 全局热键，无需辅助功能权限",
      "os.li5": "界面遵循 Apple 人机界面指南，系统原生 Liquid Glass",
      "os.li6": "Swift 6 严格并发，UI 与 I/O 分 actor 隔离",
      "os.buildTitle": "从源码构建",
      "os.buildDesc": "需要 XcodeGen（brew install xcodegen），工程由 project.yml 生成：",
      "os.copyBuild": "复制构建命令",
      "os.buildNote": "命令行构建与 DMG 打包说明见仓库 README；推 v* 标签后由 GitHub Actions 自动完成构建、签名与上传。",
      "os.linkRepo": "仓库",
      "os.linkReleases": "Releases",
      "os.linkIssues": "Issues",
      "os.linkLicense": "LICENSE",

      "cta.title": "让剪贴板记住该记住的",
      "cta.sub": "826 KB，一个菜单栏小工具，和一段不用再丢的历史。",

      "footer.line": "纯 SwiftUI + AppKit · 零第三方依赖 · 数据只在本机",
      "footer.notApple": "与 Apple Inc. 无关联",

      "toast.copied": "已复制到剪贴板",
      "toast.copyFailed": "复制失败，请手动选择复制"
    },

    en: {
      "html.title": "Clip — Clipboard History for macOS",
      "nav.features": "Features",
      "nav.showcase": "Screenshots",
      "nav.download": "Download",
      "nav.privacy": "Privacy",
      "nav.opensource": "Open Source",

      "hero.badgeLatest": "Latest v1.0.9",
      "hero.badgeOS": "macOS 27 or later",
      "hero.title": "One shortcut away,<br>your whole history.",
      "hero.sub": 'Clip is a menu-bar clipboard history manager for macOS. Everything you copy — text, links, color values, code, images — is quietly remembered. Hit <kbd>⇧⌘V</kbd> anytime, press Return to paste.',
      "hero.ctaDownload": "Download Clip for macOS",
      "hero.ctaGithub": "GitHub Repo",
      "hero.ctaMeta": "Clip-1.0.9.dmg · 826 KB · Zero dependencies · Stays on your Mac",
      "hero.shotCaption": "The panel: category filters, live counts, source tags, preview on the right",

      "chip.text": "Text",
      "chip.image": "Image",
      "chip.link": "Link",

      "intro.q1": "\"You copy a snippet, switch to the docs — and by the time you're back, the clipboard has already been overwritten.\"",
      "intro.a1": "Clip quietly remembers everything you copy. No window to babysit, no tabs, no thinking \"what was I looking for\" — the history is right there, one scroll away.",

      "features.eyebrow": "Features",
      "features.title": "One shortcut for everything you copy",
      "features.lead": "Summon, pick, paste — all from the keyboard. The details are covered too.",

      "f1.title": "It remembers everything",
      "f1.desc": "Text, links, color values, code, file paths, images — whatever you copy, with the source app on every entry. Screenshots, design files, color codes: each finds its own shelf.",
      "f2.title": "Summon and go",
      "f2.desc": "Pops up at your cursor, wherever the mouse is; flips to the other side when space runs out. Fixed height — even hundreds of entries scroll inside the list, so the window never jumps.",
      "f3.title": "Return to paste",
      "f3.desc": "Press Return and it lands at your cursor — no switching back to the previous app. <kbd>⌥↵</kbd> pastes as plain text, formatting stripped.",
      "f4.title": "Look before you paste",
      "f4.desc": "Select an entry and press <kbd>→</kbd> to expand a preview — the top-left corner stays anchored, the list never shifts sideways. Click an image to compare it at full screen; click anywhere or <kbd>esc</kbd> to dismiss.",
      "f5.title": "Lives in the menu bar",
      "f5.desc": "When a shortcut isn't handy, click the status icon: toggle recording, peek at recent items, paste straight from the menu.",
      "f6.title": "On your desktop too",
      "f6.desc": "Notification Center / desktop widgets show your recent history — click to copy, click the background to summon the full panel.",
      "f7.title": "Find the one you need",
      "f7.desc": "Live filtering in the search field. Pinned entries (<kbd>⌘P</kbd>) are never auto-purged — parameters, addresses, and go-to snippets stay within reach.",
      "f8.title": "Private by default",
      "f8.desc": "Contents flagged confidential by password managers are never recorded; your own pastes aren't echoed back; recording pauses anytime — and the data never leaves your Mac.",
      "f9.title": "Settings apply instantly",
      "f9.desc": "Language, appearance, list density, item count and retention limits, popup style — every change takes effect immediately. No Apply button, no restart.",

      "keys.eyebrow": "Keyboard first",
      "keys.title": "Your hands never leave the keyboard",
      "keys.lead": "Summon, choose, paste — the whole flow is keyboard-driven. The summon key is rebindable, and a cheat sheet lives in Settings.",
      "keys.demoPaste": "Paste",
      "keys.demoClose": "Close",
      "keys.demoPreview": "Preview",
      "k1": "Summon / dismiss (rebindable)",
      "k2": "Move selection",
      "k3": "Paste at cursor",
      "k4": "Paste as plain text",
      "k5": "Expand / collapse preview",
      "k6": "Paste the Nth entry directly",
      "k7": "Pin / unpin",
      "k8": "Delete this entry",
      "k9": "Dismiss the panel",

      "show.eyebrow": "See it",
      "show.title": "This is what it looks like",
      "show.lead": "Native SwiftUI + AppKit, following the system's Liquid Glass and light/dark appearance. Not a single third-party UI library.",
      "show.c1": "Compact panel — the window never jumps, however long the list",
      "show.c2": "Menu bar panel — everything from the status icon",
      "show.c3": "Settings · General — recording, limits, retention",
      "show.c4": "Settings · Appearance — light/dark, density, panel size",

      "dl.eyebrow": "Download & install",
      "dl.title": "Five minutes to set up, one shortcut to start",
      "dl.lead": "Distributed via GitHub Releases. Every build is produced by CI, with a SHA-256 checksum.",
      "dl.cardSub": "Clipboard history for macOS",
      "dl.metaVersion": "Latest version",
      "dl.metaAsset": "Installer",
      "dl.metaReq": "Requires",
      "dl.metaReqVal": "macOS 27 (Golden Gate) or later",
      "dl.metaLicense": "License",
      "dl.btnDownload": "Download Clip-1.0.9.dmg",
      "dl.copySha": "Copy SHA-256",
      "dl.copyCmd": "Copy command",
      "dl.verify": "Verify after download:",
      "dl.allVersions": "All releases & changelogs",
      "dl.note": "Accessibility permission is tied to the self-signed certificate, so it survives updates. To uninstall: quit Clip, delete Clip.app from Applications, and optionally remove ~/Library/Application Support/Clip.",

      "s1.title": "Download the .dmg",
      "s1.desc": "Grab the latest Clip-1.0.9.dmg from GitHub Releases — or just hit the download button on the left.",
      "s2.title": "Drag to Applications",
      "s2.desc": "Open the .dmg and drag Clip into the Applications folder, then eject the image.",
      "s3.title": "First launch (important)",
      "s3.desc": "Clip is signed with a self-signed certificate, so Gatekeeper may say the developer \"cannot be verified\". Right-click → Open in Applications, then click Open; or run this in Terminal:",
      "s3.desc2": "After that, a clipboard icon appears in your menu bar.",
      "s4.title": "Enable auto-paste (optional)",
      "s4.desc": "To let Clip press ⌘V for you, go to System Settings → Privacy & Security → Accessibility and tick Clip. Without it Clip still works — it just copies and waits for you to paste.",
      "s5.title": "Press ⇧⌘V and you're in",
      "s5.desc": "From now on, everything you copy is remembered. Pinned entries (⌘P) are never auto-purged.",

      "pv.eyebrow": "Privacy",
      "pv.title": "A clipboard sees everything you copy — so here's the deal",
      "pv1.title": "Confidential content ignored",
      "pv1.desc": "Clipboard contents flagged as confidential by password managers (1Password, TypeIt4me, …) are never recorded.",
      "pv2.title": "No echo of your own pastes",
      "pv2.desc": "Content Clip writes back is never recorded, and your history is never re-copied.",
      "pv3.title": "Pause recording anytime",
      "pv3.desc": "One toggle in the menu bar — silence whenever you want it.",
      "pv4.title": "Data stays on your Mac",
      "pv4.desc": "History lives in ~/Library/Application Support/Clip. No upload, no sync, no account.",
      "pv5.title": "Limits you control",
      "pv5.desc": "Item count (300 by default) and retention are adjustable, plus a one-click wipe of all data.",
      "pv6.title": "Auditable, because it's open",
      "pv6.desc": "The full source is on GitHub — read every line yourself.",

      "os.eyebrow": "Open source",
      "os.title": "MIT licensed, hack it your way",
      "os.lead": "Released under the MIT License — free to use, modify and redistribute.",
      "os.stackTitle": "Tech stack",
      "os.li1": "Native SwiftUI + AppKit, zero third-party dependencies",
      "os.li2": "Menu-bar agent (LSUIElement), never touches the Dock",
      "os.li3": "SwiftData incremental persistence; binaries stored as files",
      "os.li4": "Carbon RegisterEventHotKey global hotkey — no accessibility permission needed",
      "os.li5": "Follows the Apple HIG, with the system's native Liquid Glass",
      "os.li6": "Swift 6 strict concurrency; UI and I/O isolated per actor",
      "os.buildTitle": "Build from source",
      "os.buildDesc": "Requires XcodeGen (brew install xcodegen); the project is generated from project.yml:",
      "os.copyBuild": "Copy build commands",
      "os.buildNote": "Command-line builds and DMG packaging are documented in the repo README; pushing a v* tag triggers GitHub Actions to build, sign and upload automatically.",
      "os.linkRepo": "Repo",
      "os.linkReleases": "Releases",
      "os.linkIssues": "Issues",
      "os.linkLicense": "LICENSE",

      "cta.title": "Let your clipboard keep what matters",
      "cta.sub": "826 KB. One little menu-bar tool, and a history you'll never lose again.",

      "footer.line": "Pure SwiftUI + AppKit · Zero dependencies · Data stays local",
      "footer.notApple": "Not affiliated with Apple Inc.",

      "toast.copied": "Copied to clipboard",
      "toast.copyFailed": "Copy failed — please select and copy manually"
    }
  };

  /* ---------- 工具 ---------- */
  var docEl = document.documentElement;

  function store(key, value) {
    try { localStorage.setItem(key, value); } catch (e) { /* 隐私模式等场景忽略 */ }
  }

  function read(key) {
    try { return localStorage.getItem(key); } catch (e) { return null; }
  }

  var toastEl = document.getElementById("toast");
  var toastTimer = null;
  function showToast(text) {
    if (!toastEl) return;
    toastEl.textContent = text;
    toastEl.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      toastEl.classList.remove("show");
    }, 2200);
  }

  /* ---------- 语言切换 ---------- */
  var langLabel = document.getElementById("lang-label");

  function detectLang() {
    var stored = read("clip-lang");
    if (stored === "zh" || stored === "en") return stored;
    return (navigator.language || "").toLowerCase().indexOf("zh") === 0 ? "zh" : "en";
  }

  function applyLang(lang) {
    var dict = MESSAGES[lang] || MESSAGES.zh;
    docEl.setAttribute("lang", lang === "en" ? "en" : "zh-CN");

    document.querySelectorAll("[data-i18n]").forEach(function (el) {
      var v = dict[el.getAttribute("data-i18n")];
      if (v != null) el.textContent = v;
    });
    document.querySelectorAll("[data-i18n-html]").forEach(function (el) {
      var v = dict[el.getAttribute("data-i18n-html")];
      if (v != null) el.innerHTML = v;
    });
    document.querySelectorAll("[data-i18n-aria]").forEach(function (el) {
      var v = dict[el.getAttribute("data-i18n-aria")];
      if (v != null) el.setAttribute("aria-label", v);
    });

    if (dict["html.title"]) document.title = dict["html.title"];
    if (langLabel) langLabel.textContent = lang === "en" ? "中" : "EN";
    store("clip-lang", lang);
  }

  var currentLang = detectLang();
  applyLang(currentLang);

  document.getElementById("lang-toggle").addEventListener("click", function () {
    currentLang = currentLang === "en" ? "zh" : "en";
    applyLang(currentLang);
  });

  /* ---------- 主题切换 ---------- */
  function systemDark() {
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  }

  function currentTheme() {
    return docEl.getAttribute("data-theme") || (systemDark() ? "dark" : "light");
  }

  document.getElementById("theme-toggle").addEventListener("click", function () {
    var next = currentTheme() === "dark" ? "light" : "dark";
    docEl.setAttribute("data-theme", next);
    store("clip-theme", next);
  });

  // 跟随手动选择；未手动指定时跟随系统
  var storedTheme = read("clip-theme");
  if (storedTheme === "dark" || storedTheme === "light") {
    docEl.setAttribute("data-theme", storedTheme);
  }
  if (window.matchMedia) {
    var mq = window.matchMedia("(prefers-color-scheme: dark)");
    var onChange = function (e) {
      if (!read("clip-theme")) {
        // 未手动指定：CSS 媒体查询已自动处理，这里只需同步图标（由 CSS 完成）
        void e;
      }
    };
    if (mq.addEventListener) mq.addEventListener("change", onChange);
  }

  /* ---------- 复制按钮 ---------- */
  document.querySelectorAll("[data-copy]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var text = btn.getAttribute("data-copy") || "";
      var dict = MESSAGES[currentLang] || MESSAGES.zh;
      function done(ok) {
        btn.classList.add("copied");
        showToast(ok ? dict["toast.copied"] : dict["toast.copyFailed"]);
        setTimeout(function () { btn.classList.remove("copied"); }, 1600);
      }
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () { done(true); }, function () { done(false); });
      } else {
        var ta = document.createElement("textarea");
        ta.value = text;
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        document.body.appendChild(ta);
        ta.select();
        var ok = false;
        try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
        document.body.removeChild(ta);
        done(ok);
      }
    });
  });

  /* ---------- 进场动画 ---------- */
  var revealEls = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("visible");
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -40px 0px" });
    revealEls.forEach(function (el) { io.observe(el); });
  } else {
    revealEls.forEach(function (el) { el.classList.add("visible"); });
  }

  /* ---------- 导航高亮 ---------- */
  var navLinks = document.querySelectorAll(".nav-links a");
  var sections = [];
  navLinks.forEach(function (link) {
    var id = link.getAttribute("href");
    if (id && id.charAt(0) === "#") {
      var sec = document.querySelector(id);
      if (sec) sections.push({ link: link, sec: sec });
    }
  });

  if ("IntersectionObserver" in window && sections.length) {
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          navLinks.forEach(function (l) { l.classList.remove("active"); });
          var hit = sections.filter(function (s) { return s.sec === entry.target; })[0];
          if (hit) hit.link.classList.add("active");
        }
      });
    }, { rootMargin: "-30% 0px -60% 0px" });
    sections.forEach(function (s) { spy.observe(s.sec); });
  }

  /* ---------- 页脚年份 ---------- */
  var yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = String(new Date().getFullYear());
})();
