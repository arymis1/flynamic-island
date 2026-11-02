(function (request) {
  'use strict';
  // Recheck inside the tab as well as in the native bridge, including navigation races.
  if (location.origin !== 'https://music.youtube.com') return JSON.stringify({status: 'wrong-origin'});
  const bar = document.querySelector('ytmusic-player-bar');
  const video = document.querySelector('video');
  const metadata = navigator.mediaSession && navigator.mediaSession.metadata;
  const text = selector => (bar && bar.querySelector(selector)?.textContent || '').trim();
  const title = metadata?.title || text('.title');
  if (!video || !title) return JSON.stringify({status: 'idle'});
  const url = new URL(location.href);
  const track = url.searchParams.get('v') || title;
  const shuffle = bar && (bar.querySelector('#shuffle') || bar.querySelector('.shuffle'));
  const shuffleState = shuffle?.getAttribute('aria-pressed');
  const nativeShuffle = bar?.getAttribute('shuffle-on');
  const shuffleEnabled = shuffleState === 'true' || (nativeShuffle != null && nativeShuffle !== 'false');
  const shuffleAvailable = !!shuffle && !shuffle.disabled;
  if (request.command) {
    if (request.track !== track) return JSON.stringify({status: 'changed', success: false});
    const button = selector => {
      const node = bar && bar.querySelector(selector);
      if (!node || node.disabled || node.getAttribute('aria-disabled') === 'true') return false;
      node.click(); return true;
    };
    let success = true;
    switch (request.command) {
      case 'play': video.play().catch(() => {}); break;
      case 'pause': video.pause(); break;
      case 'next': success = button('.next-button'); break;
      case 'previous': success = button('.previous-button'); break;
      case 'seek':
        if (Number.isFinite(video.duration) && Number.isFinite(request.value)) {
          video.currentTime = Math.max(0, Math.min(video.duration, request.value));
        } else success = false;
        break;
      case 'volume':
        if (Number.isFinite(request.value)) {
          video.volume = Math.max(0, Math.min(1, request.value / 100));
          video.muted = request.value <= 0;
        } else success = false;
        break;
      case 'shuffle':
        if (!shuffleAvailable) success = false;
        else if (shuffleEnabled !== (request.value > 0)) { shuffle.click(); }
        break;
      default: success = false;
    }
    return JSON.stringify({status: 'command', success});
  }
  let artwork = metadata?.artwork?.slice(-1)[0]?.src || bar?.querySelector('img')?.src || '';
  return JSON.stringify({status: 'track', id: track, title,
    artist: metadata?.artist || text('.byline'), album: metadata?.album || '',
    artworkURL: artwork,
    playing: !video.paused && !video.ended,
    position: Number.isFinite(video.currentTime) ? video.currentTime : 0,
    duration: Number.isFinite(video.duration) ? video.duration : 0,
    volume: video.muted ? 0 : video.volume * 100,
    shuffleAvailable, shuffle: shuffleEnabled});
})
