/**
 * صحتنا - Service Worker (PWA)
 * Enables offline functionality and install-to-home-screen
 */

const CACHE_NAME = 'sahatna-v15';
const ASSETS = [
  './',
  './index.html',
  './clinic.html',
  './admin.html',
  './reset-password.html',
  './activate.html',
  './my-bookings.html',
  './about.html',
  './privacy.html',
  './terms.html',
  './contact.html',
  './faq.html',
  './404.html',
  './robots.txt',
  './sitemap.xml',
  './css/tailwind.generated.css',
  './css/styles.css',
  './css/mobile.css',
  './js/data.js',
  './js/app.js',
  './js/clinic.js',
  './js/admin.js',
  './js/reset-password.js',
  './js/activate.js',
  './js/my-bookings.js',
  './js/runtime-config.js',
  './js/supabase-config.js',
  './js/whatsapp.js',
  './manifest.json',
];

// Install: cache all assets
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(ASSETS);
    })
  );
  self.skipWaiting();
});

// Activate: clean old caches
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))
      );
    })
  );
  self.clients.claim();
});

// Fetch: network-first for JS/CSS/HTML (so updates are picked up immediately),
// cache-first for other assets, fallback to cache when offline.
self.addEventListener('fetch', (event) => {
  const { request } = event;

  // Skip non-GET requests
  if (request.method !== 'GET') return;
 
  // Skip cross-origin requests (Tailwind CDN, Google Fonts, Supabase API, etc.)
  const url = new URL(request.url);
  if (url.origin !== location.origin) return;

  // Network-first for JS, CSS, and HTML — ensures users always get the latest
  // code (critical for bug fixes). Falls back to cache when offline.
  if (url.pathname.endsWith('.js') || url.pathname.endsWith('.css') || url.pathname.endsWith('.html') || url.pathname === '/' || url.pathname === './') {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(request, clone);
          });
          return response;
        })
        .catch(() => caches.match(request).then((cached) => cached || new Response('Offline', { status: 503 })))
    );
    return;
  }

  // Cache-first for other assets (images, manifest, etc.)
  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) return cached;
      return fetch(request)
        .then((response) => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(request, clone);
          });
          return response;
        })
        .catch(() => cached);
    })
  );
});
