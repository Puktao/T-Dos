// F-Do’s service worker: uygulamayı telefonda hızlı ve çevrimdışı açar.
// Uygulamayı güncellediğinde aşağıdaki sürüm numarasını bir artır (v1 -> v2).
const CACHE = "fdos-v66";
const SHELL = ["./", "./index.html", "./supabase-config.js", "./manifest.webmanifest", "./icons/icon-192.png"];
const CDN = ["cdn.jsdelivr.net", "fonts.googleapis.com", "fonts.gstatic.com"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL.map(u => new Request(u, {cache: "reload"})))).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});
self.addEventListener("fetch", e => {
  if (e.request.method !== "GET") return;
  const url = new URL(e.request.url);
  // Supabase kütüphanesi ve yazı tipleri: önce önbellek
  if (CDN.includes(url.hostname)) {
    e.respondWith(caches.match(e.request).then(hit => hit || fetch(e.request).then(res => {
      const copy = res.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); return res;
    })));
    return;
  }
  if (url.origin !== location.origin) return; // veritabanı trafiğine dokunma
  // Uygulama dosyaları: önce internet (güncel sürüm, tarayıcı önbelleği atlanır), yoksa önbellek
  // İnternet yavaşsa 1,5 sn'den fazla beklenmez: önbellekteki sürüm açılır, güncel sürüm arkada indirilip sonraki açılışta gelir.
  const fresh = e.request.mode === "navigate" ? new Request(url.href, {cache: "no-cache"}) : new Request(e.request, {cache: "no-cache"});
  const net = fetch(fresh).then(res => {
    if (res.ok){ const copy = res.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); }
    return res;
  });
  const cached = () => caches.match(e.request).then(hit => hit || (e.request.mode === "navigate" ? caches.match("./index.html") : undefined));
  e.waitUntil(net.catch(() => {}));
  e.respondWith(new Promise(resolve => {
    let done = false;
    const give = r => { if (!done && r){ done = true; resolve(r); } };
    const timer = setTimeout(() => cached().then(give), 1500);
    net.then(r => { clearTimeout(timer); give(r); })
       .catch(() => { clearTimeout(timer); cached().then(hit => hit ? give(hit) : give(Response.error())); });
    // önbellekte yoksa ağı beklemeye devam et
  }));
});
