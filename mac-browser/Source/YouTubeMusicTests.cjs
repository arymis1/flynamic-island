const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const script = fs.readFileSync(require('node:path').join(__dirname, '../Resources/YouTubeMusic.js'), 'utf8');
function fixture(origin = 'https://music.youtube.com') {
  const video = {paused: false, ended: false, currentTime: 23, duration: 180, volume: 0.6, muted: false,
    play() {this.paused = false; return Promise.resolve();}, pause() {this.paused = true;}};
  let clicks = [];
  const bar = {getAttribute() { return null; }, querySelector(selector) {
    if (selector === '#shuffle') return {getAttribute: () => 'false', click: () => clicks.push('shuffle')};
    if (selector === '.next-button' || selector === '.previous-button') return {getAttribute: () => null, click: () => clicks.push(selector)};
    return null;
  }};
  const context = {URL, location: {origin, href: origin + '/watch?v=test-song'}, navigator: {mediaSession: {
    metadata: {title: 'Test Song', artist: 'Test Artist', album: 'Test Album', artwork: [{src: 'https://i.ytimg.com/vi/test/hqdefault.jpg'}]}}},
    document: {querySelector: selector => selector === 'video' ? video : bar}};
  return {video, clicks, run: request => JSON.parse(vm.runInNewContext(`(${script})(${JSON.stringify(request)})`, context))};
}
let f = fixture();
assert.deepEqual(f.run({}), {status:'track', id:'test-song', title:'Test Song', artist:'Test Artist', album:'Test Album',
  artworkURL:'https://i.ytimg.com/vi/test/hqdefault.jpg', playing:true, position:23, duration:180, volume:60, shuffleAvailable:true, shuffle:false});
assert.equal(f.run({command:'pause', track:'other-song'}).success, false);
assert.equal(f.video.paused, false);
assert.equal(f.run({command:'pause', track:'test-song'}).success, true);
assert.equal(f.run({}).playing, false);
assert.equal(f.run({command:'play', track:'test-song'}).success, true);
assert.equal(f.run({}).playing, true);
f.run({command:'seek', track:'test-song', value:999}); assert.equal(f.video.currentTime, 180);
f.run({command:'volume', track:'test-song', value:125}); assert.equal(f.video.volume, 1);
f.run({command:'volume', track:'test-song', value:0}); assert.equal(f.video.muted, true);
f.run({command:'next', track:'test-song'}); assert.deepEqual(f.clicks, ['.next-button']);
f.run({command:'shuffle', track:'test-song', value:1}); assert.equal(f.clicks[1], 'shuffle');
assert.equal(f.run({command:'arbitrary', track:'test-song'}).success, false);
assert.equal(fixture('https://example.com').run({command:'pause', track:'test-song'}).status, 'wrong-origin');
console.log('YouTube Music checks passed: metadata, real video state, playback, seek/volume bounds, next/shuffle, stale-song rejection, and exact-origin restriction.');
