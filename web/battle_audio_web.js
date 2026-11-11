(function () {
  'use strict';

  const MAX_STORM_DRIVE = 8.0;

  function buildSoftClipCurve() {
    const n = 4096;
    const curve = new Float32Array(n);
    const knee = 0.72;
    const span = 1.0 - knee;
    for (let i = 0; i < n; i++) {
      const u = (i * 2) / (n - 1) - 1;
      const x = u * MAX_STORM_DRIVE;
      const a = Math.abs(x);
      const y = a <= knee ? a : knee + span * Math.tanh((a - knee) / span);
      curve[i] = x < 0 ? -y : y;
    }
    return curve;
  }

  class WhcWebAudio {
    constructor() {
      this.ctx = null;
      this.stormClipper = null;
      this.buffers = Object.create(null);
      this.decoding = Object.create(null);
      this.loopDesired = Object.create(null);
      this.loopActive = Object.create(null);
      this.exclusive = Object.create(null);
      this.voiceSerial = 0;
      this._unlockBound = null;
      this._disposed = false;
    }

    ensureCtx() {
      if (this._disposed) return null;
      if (!this.ctx) {
        const Ctx = window.AudioContext || window.webkitAudioContext;
        if (!Ctx) return null;
        this.ctx = new Ctx();
        this.stormClipper = this.ctx.createWaveShaper();
        this.stormClipper.curve = buildSoftClipCurve();
        this.stormClipper.oversample = '2x';
        this.stormClipper.connect(this.ctx.destination);
        this._installUnlock();
      }
      return this.ctx;
    }

    _installUnlock() {
      if (this._unlockBound) return;
      const self = this;
      this._unlockBound = function () {
        if (!self.ctx || self._disposed) return;
        if (self.ctx.state === 'suspended') {
          self.ctx.resume().then(function () {
            self._syncAllLoops();
          }).catch(function () {});
        } else {
          self._syncAllLoops();
        }
      };
      for (const ev of ['pointerdown', 'keydown', 'touchstart', 'click']) {
        window.addEventListener(ev, this._unlockBound, { capture: true, passive: true });
      }
    }

    init() {
      this._disposed = false;
      this.ensureCtx();
    }

    hasBuffer(key) {
      return Boolean(this.buffers[key]);
    }

    setPcmBuffer(key, leftF32, rightF32, sampleRate) {
      const ctx = this.ensureCtx();
      if (!ctx || !leftF32) return;
      const channels = rightF32 ? 2 : 1;
      const buf = ctx.createBuffer(channels, leftF32.length, sampleRate);
      buf.copyToChannel(leftF32, 0);
      if (rightF32) {
        buf.copyToChannel(rightF32, 1);
      }
      this.buffers[key] = buf;
      this._syncAllLoops();
    }

    decodeBytes(key, uint8Array) {
      if (this.buffers[key]) return Promise.resolve(true);
      if (this.decoding[key]) return this.decoding[key];
      const ctx = this.ensureCtx();
      if (!ctx) return Promise.resolve(false);

      const copy = uint8Array.buffer.slice(
        uint8Array.byteOffset,
        uint8Array.byteOffset + uint8Array.byteLength
      );
      const self = this;
      const p = ctx.decodeAudioData(copy).then(
        function (buf) {
          delete self.decoding[key];
          if (!self._disposed) {
            self.buffers[key] = buf;
            self._syncAllLoops();
          }
          return true;
        },
        function () {
          delete self.decoding[key];
          return false;
        }
      );
      this.decoding[key] = p;
      return p;
    }

    _playNode(buf, volume, channel, softClip) {
      const ctx = this.ctx;
      if (!ctx || !buf || this._disposed) return;

      if (channel && this.exclusive[channel]) {
        try {
          this.exclusive[channel].stop();
          this.exclusive[channel].disconnect();
        } catch (_) {}
        delete this.exclusive[channel];
      }

      const src = ctx.createBufferSource();
      src.buffer = buf;
      const gain = ctx.createGain();
      if (softClip && this.stormClipper) {
        gain.gain.value = Math.max(0, Math.min(1, volume / MAX_STORM_DRIVE));
        src.connect(gain);
        gain.connect(this.stormClipper);
      } else {
        gain.gain.value = Math.max(0, Math.min(1, volume));
        src.connect(gain);
        gain.connect(ctx.destination);
      }
      if (channel) {
        this.exclusive[channel] = src;
        const self = this;
        src.onended = function () {
          if (self.exclusive[channel] === src) {
            delete self.exclusive[channel];
          }
        };
      }
      src.start(0);
    }

    playOneShot(key, volume, channel, softClip) {
      const ctx = this.ensureCtx();
      if (!ctx || this._disposed) return;
      const buf = this.buffers[key];
      if (!buf || volume <= 0.001) return;

      if (channel === 'voice') {
        const serial = ++this.voiceSerial;
        if (ctx.state === 'running') {
          this._playNode(buf, volume, 'voice', false);
        } else {
          const self = this;
          ctx.resume().then(function () {
            if (!self._disposed && serial === self.voiceSerial && ctx.state === 'running') {
              self._playNode(buf, volume, 'voice', false);
              self._syncAllLoops();
            }
          }).catch(function () {});
        }
        return;
      }

      if (ctx.state !== 'running') {
        ctx.resume().catch(function () {});
        return;
      }
      this._playNode(buf, volume, channel || '', Boolean(softClip));
    }

    setLoop(channel, key, volume, enabled, softClip) {
      this.loopDesired[channel] = {
        key: key || '',
        volume: Number(volume) || 0,
        enabled: Boolean(enabled),
        softClip: Boolean(softClip),
      };
      this._syncLoop(channel);
    }

    updateLoopVolume(channel, volume) {
      const d = this.loopDesired[channel];
      if (!d) return;
      d.volume = Number(volume) || 0;
      const active = this.loopActive[channel];
      const ctx = this.ctx;
      if (active && ctx) {
        const target = d.softClip
          ? Math.max(0, Math.min(1, d.volume / MAX_STORM_DRIVE))
          : Math.max(0, Math.min(1, d.volume));
        active.gain.gain.setTargetAtTime(target, ctx.currentTime, 0.03);
      }
      if (d.volume <= 0.001 && active) {
        this._stopLoop(channel);
      } else if (d.volume > 0.001 && d.enabled && !active) {
        this._syncLoop(channel);
      }
    }

    _stopLoop(channel) {
      const active = this.loopActive[channel];
      if (!active) return;
      try {
        active.src.stop();
        active.src.disconnect();
        active.gain.disconnect();
      } catch (_) {}
      delete this.loopActive[channel];
    }

    _syncAllLoops() {
      for (const ch of Object.keys(this.loopDesired)) {
        this._syncLoop(ch);
      }
    }

    _syncLoop(channel) {
      const ctx = this.ensureCtx();
      const d = this.loopDesired[channel];
      if (!ctx || !d || this._disposed) return;

      if (!d.enabled || d.volume <= 0.001 || !d.key) {
        this._stopLoop(channel);
        return;
      }

      const buf = this.buffers[d.key];
      if (!buf) return;

      if (ctx.state !== 'running') {
        return;
      }

      const targetGain = d.softClip
        ? Math.max(0, Math.min(1, d.volume / MAX_STORM_DRIVE))
        : Math.max(0, Math.min(1, d.volume));

      const active = this.loopActive[channel];
      if (active && active.key === d.key) {
        active.gain.gain.setTargetAtTime(targetGain, ctx.currentTime, 0.03);
        return;
      }

      this._stopLoop(channel);
      const src = ctx.createBufferSource();
      src.buffer = buf;
      src.loop = true;
      const gain = ctx.createGain();
      gain.gain.value = targetGain;
      src.connect(gain);
      if (d.softClip && this.stormClipper) {
        gain.connect(this.stormClipper);
      } else {
        gain.connect(ctx.destination);
      }
      src.start(0);
      this.loopActive[channel] = { key: d.key, src: src, gain: gain };
    }

    dispose() {
      this._disposed = true;
      for (const ch of Object.keys(this.loopActive)) {
        this._stopLoop(ch);
      }
      for (const ch of Object.keys(this.exclusive)) {
        try {
          this.exclusive[ch].stop();
        } catch (_) {}
      }
      this.exclusive = Object.create(null);
      if (this._unlockBound) {
        for (const ev of ['pointerdown', 'keydown', 'touchstart', 'click']) {
          window.removeEventListener(ev, this._unlockBound, { capture: true });
        }
        this._unlockBound = null;
      }
      if (this.ctx) {
        try {
          this.ctx.close();
        } catch (_) {}
        this.ctx = null;
      }
      this.buffers = Object.create(null);
      this.decoding = Object.create(null);
      this.loopDesired = Object.create(null);
    }
  }

  window.__whcAudio = new WhcWebAudio();
})();

