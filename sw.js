/**
 * صحتنا - Service Worker (PWA)
 * Enables offline functionality and install-to-home-screen
 */

const CACHE_NAME = 'sahatna-v4';
const ASSETS = [
  './',
  './index.html',
  './clinic.html',
  './admin.html',
  './css/styles.css',
  './js/data.js',
  './js/app.js',
  './js/clinic.js',
  './js/admin.js',
  './js/supabase-config.js',
  './js/db.js',
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

// Fetch: cache-first for assets, network-first for API
self.addEventListener('fetch', (event) => {
  const { request } = event;

  // Skip non-GET requests
  if (request.method !== 'GET') return;

  // Skip cross-origin requests (Tailwind CDN, Google Fonts, etc.)
  const url = new URL(request.url);
  if (url.origin !== location.origin) return;

  // Cache-first strategy
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