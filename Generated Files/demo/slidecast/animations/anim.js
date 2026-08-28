/* slidecast animation runtime + helper library.
 * Load AFTER GSAP (and optional plugins) and BEFORE the deck's inline choreography script.
 *
 * Two consumers share ONE seekable timeline `window.master`:
 *   - LIVE player: manual keyboard/click navigation with optional user-enabled timed advance.
 *   - VIDEO renderer (scripts/capture.js): keeps master paused and calls master.seek(t) per frame,
 *     mapping audio time -> master time via the labels added by sc.cue().
 *
 * Authoring flow (in the deck's inline script):
 *     sc.init({ autoMs: 6000 });
 *     sc.slide('slide-01');
 *       sc.cue('s1-title');   sc.entrance('#title', { y:40 });
 *       sc.cue('s1-barGrow'); sc.bars('.bar');
 *     sc.slide('slide-02'); ...
 *     sc.ready();
 *
 * Every sc.cue(name) adds a GSAP label at the current end of the master timeline, so the label time
 * equals the segment's start. The storyboard's cue.toLabel references these names. Helpers append to
 * the timeline end (no explicit position) so labels line up with segment starts.
 */
(function (global) {
  var hasGSAP = typeof gsap !== 'undefined';
  if (hasGSAP) gsap.ticker.lagSmoothing(0); // determinism: no CPU-dependent catch-up

  var master = hasGSAP ? gsap.timeline({ paused: true }) : null;
  // Ambient timeline: holds ENDLESS loops (sc.flow, looping emphasis) so they never make
  // master.duration() Infinity (which would break live nav + progress). In live mode it plays
  // continuously; in render mode the capturer seeks it to pause-aware global visual time.
  var ambient = hasGSAP ? gsap.timeline({ paused: true }) : null;
  var slideBounds = [];           // [{id, start}] master time where each slide begins
  var captions = [];              // [{t, d, w}] absolute word times (optional, set by deck or loader)
  var opts = { autoMs: 6000, subtitles: true };
  var reducedMotionQuery = global.matchMedia
    ? global.matchMedia('(prefers-reduced-motion: reduce)')
    : null;

  function prefersReducedMotion() {
    return !global.__slidecastRenderMode && !!(reducedMotionQuery && reducedMotionQuery.matches);
  }
  function motionScale() {
    var m = getComputedStyle(document.documentElement).getPropertyValue('--sc-motion').trim();
    var n = parseFloat(m); return isNaN(n) ? 1 : n;            // 0..3
  }
  // duration multiplier: motion 0 => fast/minimal, 3 => lively
  function dur(base) {
    var s = motionScale(); return base * (0.4 + s * 0.4);
  }
  function syncAmbientMotion() {
    if (!ambient || global.__slidecastRenderMode) return;
    if (prefersReducedMotion()) ambient.pause(0);
    else ambient.play();
  }
  var EASE = { soft: 'power2.out', back: 'back.out(1.4)', bounce: 'elastic.out(1,0.5)', none: 'none' };

  // keep progress bar + slide counter in sync — runs on every master update, so it works in BOTH
  // live playback AND video render (the renderer seeks master each frame -> onUpdate fires).
  function updateChrome() {
    if (!master) return;
    var prog = document.getElementById('sc-progress');
    if (prog && isFinite(master.duration()) && master.duration() > 0)
      prog.style.width = (master.progress() * 100) + '%';
    var cnt = document.getElementById('sc-counter');
    if (cnt && slideBounds.length) {
      var t = master.time(), idx = 0;
      for (var i = 0; i < slideBounds.length; i++) if (t >= slideBounds[i].start - 1e-4) idx = i;
      cnt.textContent = (idx + 1) + ' / ' + slideBounds.length;
    }
  }

  var sc = {
    master: master,
    ambient: ambient,

    init: function (o) {
      Object.assign(opts, o || {});
      // hide every slide initially; each sc.slide() reveals its own and hides the previous one,
      // recorded as zero-duration sets on the timeline so seeking shows the right slide at any t.
      if (hasGSAP) gsap.set('.slide', { autoAlpha: 0 });
      return sc;
    },

    /* mark the start of a slide (also adds a label `slide:<id>`) and handles slide show/hide */
    slide: function (id) {
      if (!master) return sc;
      master.addLabel('slide:' + id);
      var prev = slideBounds.length ? slideBounds[slideBounds.length - 1].id : null;
      master.set('.slide[data-slide="' + id + '"]', { autoAlpha: 1, zIndex: 2 });
      if (prev) master.set('.slide[data-slide="' + prev + '"]', { autoAlpha: 0, zIndex: 1 });
      slideBounds.push({ id: id, start: master.duration() });
      return sc;
    },

    /* add a named cue label at the current timeline end */
    cue: function (name) { if (master) master.addLabel(name); return sc; },

    /* ENTRANCE — staggered fade/slide/zoom. preset: 'rise'|'left'|'right'|'zoom'|'fade' */
    entrance: function (targets, o) {
      o = o || {}; if (!master) return sc;
      var from = { opacity: 0, ease: o.ease || EASE.soft, duration: dur(o.duration || 0.6),
                   stagger: o.stagger != null ? o.stagger : 0.1 };
      var p = o.preset || (o.y != null || o.x != null ? 'custom' : 'rise');
      if (p === 'rise') from.y = 30; else if (p === 'left') from.x = -40;
      else if (p === 'right') from.x = 40; else if (p === 'zoom') { from.scale = 0.85; }
      if (o.y != null) from.y = o.y; if (o.x != null) from.x = o.x;
      master.from(targets, from, o.at);
      return sc;
    },

    /* EMPHASIS — pulse/glow/shake a part. repeat:-1 (endless) is routed to the ambient timeline so
       it never makes master.duration() infinite; finite repeats stay on the master choreography. */
    emphasis: function (target, o) {
      o = o || {}; if (!master) return sc;
      var rep = o.repeat != null ? o.repeat : 3, t = o.type || 'pulse';
      var tl = (rep === -1) ? ambient : master;
      var at = (rep === -1) ? (o.at || 0) : o.at;
      if (t === 'pulse')
        tl.to(target, { scale: 1.15, transformOrigin: 'center', yoyo: true, repeat: rep,
                        duration: dur(0.4), ease: 'sine.inOut' }, at);
      else if (t === 'glow')
        tl.to(target, { filter: 'drop-shadow(0 0 12px currentColor)', yoyo: true, repeat: rep,
                        duration: dur(0.5) }, at);
      else if (t === 'shake')
        tl.to(target, { x: '+=8', yoyo: true, repeat: rep < 0 ? -1 : rep * 2, duration: dur(0.06) }, at);
      return sc;
    },

    /* DRAW-ON SVG stroke (uses DrawSVGPlugin if present, else stroke-dashoffset) */
    draw: function (selector, o) {
      o = o || {}; if (!master) return sc;
      var els = document.querySelectorAll(selector);
      if (typeof DrawSVGPlugin !== 'undefined') {
        master.from(selector, { drawSVG: '0%', duration: dur(o.duration || 1.4), ease: EASE.none,
                               stagger: o.stagger || 0 }, o.at);
      } else {
        els.forEach(function (p) {
          var len = p.getTotalLength ? p.getTotalLength() : 100;
          p.style.strokeDasharray = len; p.style.strokeDashoffset = len;
          master.to(p, { strokeDashoffset: 0, duration: dur(o.duration || 1.4), ease: EASE.none }, o.at);
        });
      }
      return sc;
    },

    /* REVEAL — wipe in via scale (axis 'x' or 'y'); good for rules/underlines/bars */
    reveal: function (target, o) {
      o = o || {}; if (!master) return sc;
      var axis = o.axis === 'y' ? 'scaleY' : 'scaleX';
      var from = {}; from[axis] = 0;
      from.transformOrigin = o.axis === 'y' ? 'bottom' : 'left';
      from.duration = dur(o.duration || 0.6); from.ease = o.ease || EASE.soft;
      master.from(target, from, o.at);
      return sc;
    },

    /* FLOW — endless "marching ants" along a dashed path. Lives on the AMBIENT timeline so it never
       makes master.duration() infinite. In render mode the capturer seeks ambient to video time. */
    flow: function (selector, o) {
      o = o || {}; if (!ambient) return sc;
      ambient.to(selector, { strokeDashoffset: '-=' + (o.gap || 20), repeat: -1,
                            duration: dur(o.duration || 0.6), ease: EASE.none }, o.at || 0);
      return sc;
    },

    /* MOVE a token along a path (needs MotionPathPlugin) */
    move: function (target, pathSel, o) {
      o = o || {}; if (!master || typeof MotionPathPlugin === 'undefined') return sc;
      var rep = o.repeat != null ? o.repeat : 0;
      var tl = rep === -1 ? ambient : master;
      var at = rep === -1 ? (o.at || 0) : o.at;
      tl.to(target, { motionPath: { path: pathSel, align: pathSel, autoRotate: !!o.autoRotate },
                      duration: dur(o.duration || 3), ease: o.ease || EASE.none,
                      repeat: rep }, at);
      return sc;
    },

    /* COUNT-UP a number into a DOM node */
    countUp: function (target, to, o) {
      o = o || {}; if (!master) return sc;
      var el = typeof target === 'string' ? document.querySelector(target) : target;
      var proxy = { v: o.from || 0 }, fmt = o.format || function (v) { return Math.round(v).toLocaleString(); };
      master.to(proxy, { v: to, duration: dur(o.duration || 1.8), ease: 'power1.out',
                        onUpdate: function () { if (el) el.textContent = fmt(proxy.v); } }, o.at);
      return sc;
    },

    /* CHART bars grow from baseline (transform-origin:bottom) */
    bars: function (selector, o) {
      o = o || {}; if (!master) return sc;
      master.from(selector, { scaleY: 0, transformOrigin: 'bottom', duration: dur(o.duration || 0.8),
                             stagger: o.stagger != null ? o.stagger : 0.1, ease: 'power3.out' }, o.at);
      return sc;
    },

    /* TYPEWRITER (needs SplitText; else fades whole element) */
    type: function (selector, o) {
      o = o || {}; if (!master) return sc;
      if (typeof SplitText !== 'undefined') {
        var split = new SplitText(selector, { type: 'chars' });
        master.from(split.chars, { opacity: 0, duration: 0.02, stagger: o.speed || 0.04 }, o.at);
      } else master.from(selector, { opacity: 0, duration: dur(0.6) }, o.at);
      return sc;
    },

    /* REVEAL a video/element into a shape via clip-path animation */
    revealShape: function (selector, o) {
      o = o || {}; if (!master) return sc;
      var to = o.shape === 'circle' ? 'circle(75% at 50% 50%)' : 'inset(0% round var(--sc-radius))';
      var from = o.shape === 'circle' ? 'circle(0% at 50% 50%)' : 'inset(50% round var(--sc-radius))';
      master.fromTo(selector, { clipPath: from }, { clipPath: to, duration: dur(o.duration || 1) }, o.at);
      return sc;
    },

    setCaptions: function (arr) { captions = arr || []; return sc; },

    /* finalize: expose duration + labels; wire chrome; start LIVE player unless we are being rendered */
    ready: function () {
      global.__slidecastReady = true;
      if (master) { master.eventCallback('onUpdate', updateChrome); updateChrome(); }
      if (!global.__slidecastRenderMode && master) {
        Player.start();
        syncAmbientMotion();
        if (reducedMotionQuery) {
          var onMotionPreferenceChange = function () {
            if (Player._tw) { Player._tw.kill(); Player._tw = null; }
            if (prefersReducedMotion() && Player.idx >= 0) {
              master.pause();
              master.seek(Player.endOf(Player.idx));
              updateChrome();
            }
            if (Player.auto) Player.scheduleAuto();
            syncAmbientMotion();
          };
          if (reducedMotionQuery.addEventListener)
            reducedMotionQuery.addEventListener('change', onMotionPreferenceChange);
          else if (reducedMotionQuery.addListener)
            reducedMotionQuery.addListener(onMotionPreferenceChange);
        }
      }
      document.dispatchEvent(new CustomEvent('slidecast:ready'));
      return sc;
    }
  };

  /* ---------- LIVE player — PAGE-BY-PAGE (PowerPoint-style). Ignored during video render. ----------
     Each slide plays its entrance once, then HOLDS on the fully-revealed slide until the user advances.
     Space/Enter/→/↓/PageDown = next · ←/↑/PageUp = previous · Home/End = first/last ·
     a = toggle per-page autoplay · f = fullscreen · c = captions (reads each slide's data-caption). */
  var Player = {
    idx: -1, auto: false, timer: null, _tw: null,
    start: function () {
      if (!master) return;
      this.bindNav();
      this.show(0, false);                 // reveal the first slide, then hold
    },
    // time to pause at: just before the next slide's reveal fires (so this slide stays fully revealed)
    endOf: function (i) {
      return (i + 1 < slideBounds.length) ? slideBounds[i + 1].start - 0.001 : master.duration();
    },
    show: function (i, immediate) {
      if (!slideBounds.length) return;
      i = Math.max(0, Math.min(i, slideBounds.length - 1));
      this.idx = i;
      this.showCaption(i);
      clearTimeout(this.timer);
      if (this._tw) { this._tw.kill(); this._tw = null; }
      var to = this.endOf(i), self = this;
      if (immediate || prefersReducedMotion()) { // reduced motion shows the completed static state
        master.pause(); master.seek(to); updateChrome();
        if (self.auto) self.scheduleAuto();
      } else {                             // play this slide's fly-in, then stop on its end state
        this._tw = master.tweenFromTo(slideBounds[i].start, to, {
          ease: 'none', onUpdate: updateChrome,
          onComplete: function () { self._tw = null; if (self.auto) self.scheduleAuto(); }
        });
      }
    },
    next: function () {
      if (this.idx < slideBounds.length - 1) this.show(this.idx + 1, false);
      else if (this.auto) this.show(0, false);          // loop only while autoplaying
    },
    prev: function () { this.show(this.idx - 1, true); },
    // live captions: show the current slide's narration text in #sc-subtitle (toggle with 'c')
    showCaption: function (i) {
      var box = document.getElementById('sc-subtitle');
      if (!box || !slideBounds[i]) return;
      var el = document.querySelector('.slide[data-slide="' + slideBounds[i].id + '"]');
      box.textContent = (el && el.getAttribute('data-caption')) || '';
    },
    scheduleAuto: function () {
      var self = this; clearTimeout(this.timer);
      this.timer = setTimeout(function () { self.next(); }, opts.autoMs || 6000);
    },
    toggleAuto: function () {
      this.auto = !this.auto;
      if (this.auto) { if (!this._tw) this.scheduleAuto(); } else clearTimeout(this.timer);
    },
    stopAuto: function () { this.auto = false; clearTimeout(this.timer); },
    bindNav: function () {
      var self = this;
      document.addEventListener('keydown', function (e) {
        if (['ArrowRight', 'ArrowDown', ' ', 'Enter', 'PageDown'].includes(e.key)) {
          e.preventDefault(); self.stopAuto(); self.next();
        } else if (['ArrowLeft', 'ArrowUp', 'PageUp'].includes(e.key)) {
          e.preventDefault(); self.stopAuto(); self.prev();
        } else if (e.key === 'Home') { e.preventDefault(); self.stopAuto(); self.show(0, true); }
        else if (e.key === 'End') { e.preventDefault(); self.stopAuto(); self.show(slideBounds.length - 1, true); }
        else if (e.key === 'a' || e.key === 'A') { self.toggleAuto(); }
        else if (e.key === 'f') { document.documentElement.requestFullscreen?.(); }
        else if (e.key === 'c') {
          var cb = document.getElementById('cc-check');
          if (cb) { cb.checked = !cb.checked; cb.dispatchEvent(new Event('change')); }
          else document.body.classList.toggle('subtitles-off');
        }
      });
      document.addEventListener('click', function (e) {
        if (e.target.closest('a,button,input,label,.cc-toggle,.sc-interactive')) return;
        self.stopAuto();
        e.clientX > innerWidth / 2 ? self.next() : self.prev();
      });
    }
  };

  global.sc = sc;
  global.master = master;            // the seekable choreography timeline the renderer drives
  global.ambient = ambient;          // endless loops; renderer seeks to pause-aware visual time
  global.__slidecastPlayer = Player;
})(window);
