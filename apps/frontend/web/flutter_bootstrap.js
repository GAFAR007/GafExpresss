{{flutter_js}}
{{flutter_build_config}}

const clearOldFlutterCache = async () => {
  if ('serviceWorker' in navigator) {
    const registrations = await navigator.serviceWorker.getRegistrations();
    await Promise.all(
      registrations.map((registration) => registration.unregister()),
    );
  }

  if ('caches' in window) {
    const cacheNames = await caches.keys();
    await Promise.all(
      cacheNames
        .filter((cacheName) => cacheName.startsWith('flutter-'))
        .map((cacheName) => caches.delete(cacheName)),
    );
  }
};

clearOldFlutterCache()
  .catch((error) => {
    console.warn('Unable to clear old Flutter cache before boot.', error);
  })
  .then(() => {
    _flutter.loader.load();
  });
