/* ===== Starfield: lightweight parallax canvas matching the game ===== */
(function starfield() {
  const canvas = document.getElementById("starfield");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let w, h, stars, dpr;

  function resize() {
    dpr = Math.min(devicePixelRatio || 1, 2);
    w = canvas.width = innerWidth * dpr;
    h = canvas.height = innerHeight * dpr;
    canvas.style.width = innerWidth + "px";
    canvas.style.height = innerHeight + "px";
    const count = Math.min(220, Math.floor((innerWidth * innerHeight) / 9000));
    stars = Array.from({ length: count }, () => ({
      x: Math.random() * w,
      y: Math.random() * h,
      z: Math.random() * 0.8 + 0.2,       // depth → size + speed
      tw: Math.random() * Math.PI * 2,    // twinkle phase
    }));
  }

  let scrollY = 0;
  addEventListener("scroll", () => { scrollY = window.scrollY; }, { passive: true });

  let t = 0;
  function frame() {
    t += 0.016;
    ctx.clearRect(0, 0, w, h);
    for (const s of stars) {
      // drift downward slowly + parallax with scroll by depth
      s.y += s.z * 0.25 * dpr;
      if (s.y > h) { s.y = 0; s.x = Math.random() * w; }
      const py = (s.y - scrollY * s.z * 0.4 * dpr) % h;
      const yy = py < 0 ? py + h : py;
      const r = s.z * 1.6 * dpr;
      const tw = reduce ? 1 : 0.55 + 0.45 * Math.sin(t * 1.5 + s.tw);
      const hue = s.z > 0.75 ? "190, 230, 255" : "150, 170, 230";
      ctx.beginPath();
      ctx.fillStyle = `rgba(${hue}, ${0.25 + s.z * 0.6 * tw})`;
      ctx.arc(s.x, yy, r, 0, Math.PI * 2);
      ctx.fill();
    }
    if (!reduce) requestAnimationFrame(frame);
  }

  resize();
  addEventListener("resize", resize);
  if (reduce) frame(); else requestAnimationFrame(frame);
})();

/* ===== Nav shadow on scroll ===== */
(function nav() {
  const nav = document.getElementById("nav");
  if (!nav) return;
  const onScroll = () => nav.classList.toggle("scrolled", window.scrollY > 20);
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();
})();

/* ===== Scroll reveal ===== */
(function reveal() {
  const items = document.querySelectorAll(
    ".section-head, .ship-card, .feature, .download-card, .stat"
  );
  items.forEach((el) => el.classList.add("reveal"));
  if (!("IntersectionObserver" in window)) {
    items.forEach((el) => el.classList.add("in"));
    return;
  }
  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((e, i) => {
        if (e.isIntersecting) {
          setTimeout(() => e.target.classList.add("in"), (i % 6) * 70);
          io.unobserve(e.target);
        }
      });
    },
    { threshold: 0.12 }
  );
  items.forEach((el) => io.observe(el));
})();

/* ===== Real APK size on the download button ===== */
(function apkSize() {
  const el = document.getElementById("dl-size");
  if (!el) return;
  fetch("downloads/ZetaLegacy.apk", { method: "HEAD" })
    .then((r) => {
      const len = r.headers.get("content-length");
      if (r.ok && len) {
        const mb = (Number(len) / (1024 * 1024)).toFixed(0);
        el.textContent = `Android 7.0+ · ${mb} MB`;
      }
    })
    .catch(() => {});
})();
