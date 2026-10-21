/* Zala - Boodschappen App – koppeling met Supabase.
   Biedt de app dezelfde opslag-API als het prototype (collection/doc/onSnapshot/set/update/delete),
   plus inloggen met een e-mailcode. Zonder configuratie draait de app lokaal op het apparaat. */
(function () {
  "use strict";
  const C = window.BZ_CONFIG || {};
  const LANGS = ["nl", "de", "en", "hu"];
  const lang = (() => { try { const s = localStorage.getItem("bz-lang"); if (LANGS.includes(s)) return s; } catch (_) {} const n = (navigator.language || "en").slice(0, 2); return LANGS.includes(n) ? n : "en"; })();
  const X = {
    app: ["Boodschappen App", "Einkaufs-App", "Shopping App", "Bevásárló App"],
    title: ["Inloggen", "Anmelden", "Sign in", "Belépés"],
    intro: ["Vul je e-mailadres in. Je krijgt een code van 6 cijfers om in te loggen. Een wachtwoord is niet nodig.",
            "Gib deine E-Mail-Adresse ein. Du bekommst einen 6-stelligen Code zum Anmelden. Ein Passwort brauchst du nicht.",
            "Enter your email address. You'll get a 6-digit code to sign in. No password needed.",
            "Add meg az e-mail címed. Kapsz egy 6 jegyű kódot a belépéshez. Jelszó nem kell."],
    email: ["E-mailadres", "E-Mail-Adresse", "Email address", "E-mail cím"],
    send: ["Stuur code", "Code senden", "Send code", "Kód küldése"],
    code: ["Code uit de e-mail", "Code aus der E-Mail", "Code from the email", "Kód az e-mailből"],
    sentTo: ["Code verstuurd naar {0}. Kijk ook in je spam.", "Code an {0} gesendet. Schau auch im Spam nach.", "Code sent to {0}. Check your spam folder too.", "Kód elküldve: {0}. Nézd meg a spam mappát is."],
    verify: ["Inloggen", "Anmelden", "Sign in", "Belépés"],
    other: ["Ander e-mailadres", "Andere E-Mail-Adresse", "Different email", "Másik e-mail cím"],
    local: ["Zonder account verder (alleen op dit apparaat)", "Ohne Konto weiter (nur auf diesem Gerät)", "Continue without an account (this device only)", "Folytatás fiók nélkül (csak ezen az eszközön)"],
    badMail: ["Vul een geldig e-mailadres in.", "Gib eine gültige E-Mail-Adresse ein.", "Enter a valid email address.", "Adj meg érvényes e-mail címet."],
    badCode: ["Die code klopt niet of is verlopen. Vraag een nieuwe aan.", "Der Code stimmt nicht oder ist abgelaufen. Fordere einen neuen an.", "That code is wrong or has expired. Request a new one.", "A kód hibás vagy lejárt. Kérj újat."],
    fail: ["Dat lukte niet. Controleer je internetverbinding en probeer het opnieuw.", "Das hat nicht geklappt. Prüfe deine Internetverbindung und versuche es erneut.", "That didn't work. Check your internet connection and try again.", "Nem sikerült. Ellenőrizd az internetkapcsolatot, és próbáld újra."],
    wait: ["Even wachten…", "Einen Moment…", "One moment…", "Egy pillanat…"],
  };
  const tx = (k, a) => { let s = X[k][LANGS.indexOf(lang)] || X[k][0]; if (a != null) s = s.split("{0}").join(a); return s; };

  if (!C.supabaseUrl || !C.supabaseAnonKey || !window.supabase || !window.supabase.createClient) {
    window.BZ = { ready: Promise.resolve(null), online: false, logout() {}, setLang() {} };
    return;
  }

  const sb = window.supabase.createClient(C.supabaseUrl, C.supabaseAnonKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false, storageKey: "bz-auth" },
  });

  /* ---------- opslag met dezelfde vorm als de prototype-API ---------- */
  function err(e) {
    const o = new Error((e && e.message) || "error");
    o.code = e && (e.code === "42501" || /row-level security|geen toegang|permission/i.test(e.message || "")) ? "permission_denied" : "unknown";
    o.cause = e;
    return o;
  }
  const split = (path) => { const i = path.lastIndexOf("/"); return [path.slice(0, i), path.slice(i + 1)]; };
  const listeners = new Map(); // coll -> Set(refresh)
  let channel = null;
  function notify(coll) { const ls = listeners.get(coll); if (ls) ls.forEach((f) => f()); }
  function notifyAll() { listeners.forEach((ls) => ls.forEach((f) => f())); }
  function ensureChannel() {
    if (channel) return;
    channel = sb.channel("docs-live")
      .on("postgres_changes", { event: "*", schema: "public", table: "docs" }, (p) => {
        const c = (p.new && p.new.coll) || (p.old && p.old.coll);
        if (c) notify(c); else notifyAll();
      })
      .subscribe((status) => { if (status === "SUBSCRIBED") notifyAll(); });
  }
  document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") notifyAll(); });
  window.addEventListener("online", notifyAll);

  function listen(coll, run) {
    let seq = 0, timer = null;
    const refresh = () => { clearTimeout(timer); timer = setTimeout(() => { const my = ++seq; run(() => my === seq); }, 120); };
    if (!listeners.has(coll)) listeners.set(coll, new Set());
    listeners.get(coll).add(refresh);
    ensureChannel();
    const my = ++seq; run(() => my === seq);
    return () => { clearTimeout(timer); const ls = listeners.get(coll); if (ls) ls.delete(refresh); };
  }

  function docRef(coll, id) {
    return {
      async set(data) {
        const { error } = await sb.from("docs").upsert({ coll, id, data, updated_at: new Date().toISOString() });
        if (error) throw err(error);
        notify(coll);
      },
      async update(patch) {
        const { error } = await sb.rpc("doc_merge", { p_coll: coll, p_id: id, p_patch: patch });
        if (error) throw err(error);
        notify(coll);
      },
      async delete() {
        const { error } = await sb.from("docs").delete().eq("coll", coll).eq("id", id);
        if (error) throw err(error);
        notify(coll);
      },
      onSnapshot(cb, onErr) {
        return listen(coll, async (fresh) => {
          const { data, error } = await sb.from("docs").select("data").eq("coll", coll).eq("id", id).maybeSingle();
          if (!fresh()) return;
          if (error) { onErr && onErr(err(error)); return; }
          cb({ id, exists: !!data, data: () => (data ? data.data : undefined) });
        });
      },
    };
  }
  function collRef(coll) {
    return {
      doc: (id) => docRef(coll, id),
      onSnapshot(cb, onErr) {
        return listen(coll, async (fresh) => {
          const { data, error } = await sb.from("docs").select("id,data").eq("coll", coll).limit(2000);
          if (!fresh()) return;
          if (error) { onErr && onErr(err(error)); return; }
          const docs = data.map((r) => ({ id: r.id, data: () => r.data }));
          cb({ docs, empty: !docs.length, size: docs.length });
        });
      },
    };
  }
  const db = {
    collection: collRef,
    doc: (path) => { const [c, i] = split(path); return docRef(c, i); },
    async rpc(fn, args) { const { data, error } = await sb.rpc(fn, args); if (error) throw err(error); notifyAll(); return data; },
  };

  /* ---------- inloggen ---------- */
  function loginScreen() {
    return new Promise((resolve) => {
      const box = document.createElement("div");
      box.id = "bzLogin";
      box.innerHTML = `<style>
#bzLogin{position:fixed;inset:0;z-index:50;background:var(--bg,#f6f4ee);color:var(--ink,#1f2a24);overflow:auto;font-family:var(--f-body,system-ui,sans-serif)}
#bzLogin .in{max-width:420px;margin:0 auto;padding-block:calc(env(safe-area-inset-top,0px) + 40px) 40px;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));display:flex;flex-direction:column;gap:14px}
#bzLogin h1{font-family:var(--f-display,system-ui,sans-serif);font-size:1.7rem;margin:0}
#bzLogin p{margin:0;color:var(--muted,#5f6a63)}
#bzLogin .msg{font-size:.9rem;padding:8px 10px;border-radius:8px;background:var(--warn-soft,#f5ead2);color:var(--warn,#8f6512)}
#bzLogin .ok{background:var(--accent-soft,#e3ece4);color:var(--accent,#3d6b4f)}
#bzLogin .lnk{all:unset;cursor:pointer;color:var(--accent,#3d6b4f);font-weight:600;font-size:.92rem}
</style><div class="in">
  <nav aria-label="Taal / Sprache / Language / Nyelv" style="display:flex;gap:4px;justify-content:flex-end">${LANGS.map((l) => `<button type="button" class="btn ${l === lang ? "" : "ghost"} small" data-bzlang="${l}">${l.toUpperCase()}</button>`).join("")}</nav>
  <h1>Zala <small style="font-family:var(--f-body);font-size:.85rem;color:var(--accent);letter-spacing:.06em;text-transform:uppercase">${tx("app")}</small></h1>
  <div class="huflag" aria-hidden="true"><i></i><i></i><i></i></div>
  <h2 style="margin:6px 0 0">${tx("title")}</h2>
  <p>${tx("intro")}</p>
  <form id="bzF1" class="stack" autocomplete="on">
    <label>${tx("email")}<input id="bzMail" type="email" inputmode="email" autocomplete="email" required></label>
    <button class="btn" type="submit" id="bzSend">${tx("send")}</button>
  </form>
  <form id="bzF2" class="stack" hidden autocomplete="off">
    <div class="msg ok" id="bzSent"></div>
    <label>${tx("code")}<input id="bzCode" inputmode="numeric" autocomplete="one-time-code" maxlength="10" pattern="[0-9]*"></label>
    <button class="btn" type="submit" id="bzVerify">${tx("verify")}</button>
    <button class="lnk" type="button" id="bzBack">${tx("other")}</button>
  </form>
  <div class="msg" id="bzMsg" hidden></div>
  <button class="lnk" type="button" id="bzLocal" style="margin-top:10px">${tx("local")}</button>
</div>`;
      document.body.appendChild(box);
      const $ = (s) => box.querySelector(s);
      const msg = (m) => { $("#bzMsg").textContent = m || ""; $("#bzMsg").hidden = !m; };
      let email = "";
      try { email = localStorage.getItem("bz-last-mail") || ""; } catch (_) {}
      $("#bzMail").value = email;
      const busy = (btn, on, label) => { btn.disabled = on; btn.textContent = on ? tx("wait") : label; };
      $("#bzF1").addEventListener("submit", async (e) => {
        e.preventDefault(); msg("");
        email = $("#bzMail").value.trim().toLowerCase();
        if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) { msg(tx("badMail")); return; }
        busy($("#bzSend"), true, tx("send"));
        const { error } = await sb.auth.signInWithOtp({ email, options: { shouldCreateUser: true, data: { lang } } });
        busy($("#bzSend"), false, tx("send"));
        if (error) { msg(tx("fail") + " (" + error.message + ")"); return; }
        try { localStorage.setItem("bz-last-mail", email); } catch (_) {}
        $("#bzSent").textContent = tx("sentTo", email);
        $("#bzF1").hidden = true; $("#bzF2").hidden = false; $("#bzCode").focus();
      });
      $("#bzF2").addEventListener("submit", async (e) => {
        e.preventDefault(); msg("");
        const token = $("#bzCode").value.replace(/\D/g, "");
        if (token.length < 6) { msg(tx("badCode")); return; }
        busy($("#bzVerify"), true, tx("verify"));
        const { data, error } = await sb.auth.verifyOtp({ email, token, type: "email" });
        busy($("#bzVerify"), false, tx("verify"));
        if (error || !data || !data.session) { msg(tx("badCode")); return; }
        box.remove(); resolve(data.session);
      });
      $("#bzBack").addEventListener("click", () => { $("#bzF2").hidden = true; $("#bzF1").hidden = false; msg(""); });
      $("#bzLocal").addEventListener("click", () => { box.remove(); resolve(null); });
      box.querySelectorAll("[data-bzlang]").forEach((b) => b.addEventListener("click", () => { try { localStorage.setItem("bz-lang", b.dataset.bzlang); } catch (_) {} location.reload(); }));
    });
  }

  async function start() {
    let session = null;
    try { const r = await sb.auth.getSession(); session = r.data && r.data.session; } catch (_) {}
    if (!session) session = await loginScreen();
    if (!session) return null;
    const uid = session.user.id;
    syncLang(session, lang);
    sb.auth.onAuthStateChange((ev) => { if (ev === "SIGNED_OUT") location.reload(); });
    return { db, user: { id: async () => uid, can: async () => true, email: session.user.email } };
  }

  async function syncLang(session, l) {
    try {
      const cur = session && session.user && session.user.user_metadata && session.user.user_metadata.lang;
      if (LANGS.includes(l) && cur !== l) await sb.auth.updateUser({ data: { lang: l } });
    } catch (_) {}
  }

  window.BZ = {
    ready: start(),
    async setLang(l) { try { const r = await sb.auth.getSession(); await syncLang(r.data && r.data.session, l); } catch (_) {} },
    online: true,
    async logout() { try { await sb.auth.signOut(); } catch (_) {} location.reload(); },
  };
})();
