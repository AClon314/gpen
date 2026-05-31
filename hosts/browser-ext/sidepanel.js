const TOOL_SELECT = "select";
const TOOL_DRAW = "draw";
const TOOL_LASSO = "lasso";
const STATUS_OK = 0;
const OVERLAY_HOST_ID = "gpen-debug-overlay-host";

if (!document.getElementById(OVERLAY_HOST_ID)) {
  boot().catch((error) => {
    console.error("[gpen-demo]", error);
  });
}

async function boot() {
  const runtime = globalThis.browser?.runtime ?? globalThis.chrome?.runtime;
  if (!runtime) {
    throw new Error("Extension runtime API is unavailable.");
  }

  const host = document.createElement("div");
  host.id = OVERLAY_HOST_ID;
  host.style.position = "absolute";
  host.style.left = "0";
  host.style.top = "0";
  host.style.width = "0";
  host.style.height = "0";

  const shadow = host.attachShadow({ mode: "open" });
  shadow.innerHTML = `
    <link rel="stylesheet" href="${runtime.getURL("sidepanel.css")}" />
    <section class="gpen-root">
      <div class="gpen-canvas-layer">
        <canvas id="drawing-surface"></canvas>
      </div>
      <section class="gpen-toolbar-shell">
        <header class="gpen-toolbar-card">
          <div class="gpen-heading">
            <p class="gpen-eyebrow">v0.1 Browser Demo</p>
            <h1>GPen</h1>
          </div>
          <div class="gpen-toolbar" role="toolbar" aria-label="Tools">
            <button type="button" data-tool="select" class="gpen-tool-button is-active">Select</button>
            <button type="button" data-tool="draw" class="gpen-tool-button">Draw</button>
            <button type="button" data-tool="lasso" class="gpen-tool-button">Lasso</button>
            <button type="button" id="delete-button" class="gpen-ghost-button">Delete</button>
            <button type="button" id="clear-button" class="gpen-ghost-button">Clear</button>
            <button type="button" id="collapse-button" class="gpen-ghost-button">Collapse</button>
            <button type="button" id="close-button" class="gpen-ghost-button">Close</button>
          </div>
          <div class="gpen-status-block">
            <p id="status-line">Loading WASM...</p>
            <p id="hint-line">Select lets the page underneath behave normally.</p>
          </div>
        </header>
      </section>
    </section>
  `;

  (document.body ?? document.documentElement).appendChild(host);

  const canvas = shadow.getElementById("drawing-surface");
  const statusLine = shadow.getElementById("status-line");
  const hintLine = shadow.getElementById("hint-line");
  const deleteButton = shadow.getElementById("delete-button");
  const clearButton = shadow.getElementById("clear-button");
  const collapseButton = shadow.getElementById("collapse-button");
  const closeButton = shadow.getElementById("close-button");
  const root = shadow.querySelector(".gpen-root");
  const canvasLayer = shadow.querySelector(".gpen-canvas-layer");
  const toolButtons = [...shadow.querySelectorAll("[data-tool]")];
  const ctx = canvas.getContext("2d");

  const state = {
    activePointerId: null,
    activeTool: TOOL_SELECT,
    canvas,
    canvasLayer,
    closeButton,
    collapseButton,
    ctx,
    hintLine,
    host,
    lassoPath: [],
    livePoints: [],
    mutationObserver: null,
    pointerPressure: 0,
    pointerType: "unknown",
    resizeObserver: null,
    root,
    selectedIds: new Set(),
    statusLine,
    strokeStartStamp: 0,
    strokes: [],
    toolButtons,
    wasm: null,
  };

  let nextStrokeId = 1;

  wireUi();
  installPageTracking();
  await loadWasm();
  applyToolState();
  render();

  function wireUi() {
    canvas.addEventListener("pointerdown", onPointerDown);
    canvas.addEventListener("pointermove", onPointerMove);
    canvas.addEventListener("pointerup", onPointerUp);
    canvas.addEventListener("pointercancel", onPointerCancel);

    deleteButton.addEventListener("click", deleteSelectedStrokes);
    clearButton.addEventListener("click", () => {
      state.strokes = [];
      state.selectedIds.clear();
      state.livePoints = [];
      state.lassoPath = [];
      syncStatus("Overlay cleared.");
      render();
    });
    collapseButton.addEventListener("click", toggleCollapse);
    closeButton.addEventListener("click", destroyOverlay);

    toolButtons.forEach((button) => {
      button.addEventListener("click", () => setTool(button.dataset.tool));
    });

    window.addEventListener("keydown", onKeyDown, true);
    window.addEventListener("scroll", refreshCanvasMetrics, { passive: true });
    document.addEventListener("visibilitychange", refreshCanvasMetrics);
  }

  function installPageTracking() {
    refreshCanvasMetrics();
    window.addEventListener("resize", refreshCanvasMetrics);

    if (typeof ResizeObserver === "function") {
      state.resizeObserver = new ResizeObserver(() => refreshCanvasMetrics());
      state.resizeObserver.observe(document.documentElement);
      if (document.body) {
        state.resizeObserver.observe(document.body);
      }
    }

    if (typeof MutationObserver === "function" && document.body) {
      state.mutationObserver = new MutationObserver(() =>
        refreshCanvasMetrics(),
      );
      state.mutationObserver.observe(document.body, {
        childList: true,
        subtree: true,
        attributes: true,
      });
    }
  }

  async function loadWasm() {
    const bytes = await fetch(runtime.getURL("gpen_wasm.wasm")).then(
      (response) => {
        if (!response.ok) {
          throw new Error(`WASM fetch failed: ${response.status}`);
        }
        return response.arrayBuffer();
      },
    );

    const { instance } = await WebAssembly.instantiate(bytes, {});
    const exports = instance.exports;
    state.wasm = {
      allocInputPoints: exports.gp_alloc_input_points_wasm,
      allocResultHeader: exports.gp_alloc_result_header_wasm,
      inputPointSize: exports.gp_input_point_size_wasm(),
      memory: exports.memory,
      outputPointSize: exports.gp_output_point_size_wasm(),
      processStroke: exports.gp_process_stroke_web_wasm,
      resetArena: exports.gp_reset_arena,
    };

    syncStatus("WASM ready. Draw or lasso on the page overlay.");
  }

  function setTool(tool) {
    state.activeTool = tool;
    state.livePoints = [];
    state.lassoPath = [];
    applyToolState();
    render();
  }

  function applyToolState() {
    const interactive = state.activeTool !== TOOL_SELECT;
    state.canvasLayer.classList.toggle("is-interactive", interactive);
    state.toolButtons.forEach((button) => {
      button.classList.toggle(
        "is-active",
        button.dataset.tool === state.activeTool,
      );
    });

    if (state.activeTool === TOOL_SELECT) {
      state.hintLine.textContent =
        "Select mode passes pointer events through to the page underneath.";
    } else if (state.activeTool === TOOL_DRAW) {
      state.hintLine.textContent =
        "Draw mode captures pen or mouse input on the transparent page overlay.";
    } else {
      state.hintLine.textContent =
        "Lasso mode selects drawn strokes while the page remains visible underneath.";
    }
  }

  function refreshCanvasMetrics() {
    const dpr = window.devicePixelRatio || 1;
    const doc = document.documentElement;
    const body = document.body;
    const width = Math.max(
      doc.scrollWidth,
      doc.clientWidth,
      body?.scrollWidth ?? 0,
      window.innerWidth,
    );
    const height = Math.max(
      doc.scrollHeight,
      doc.clientHeight,
      body?.scrollHeight ?? 0,
      window.innerHeight,
    );

    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    state.canvasLayer.style.width = `${width}px`;
    state.canvasLayer.style.height = `${height}px`;
    canvas.width = Math.max(1, Math.floor(width * dpr));
    canvas.height = Math.max(1, Math.floor(height * dpr));
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    render();
  }

  function toggleCollapse() {
    const collapsed = state.root.classList.toggle("is-collapsed");
    collapseButton.textContent = collapsed ? "Expand" : "Collapse";
  }

  function destroyOverlay() {
    state.resizeObserver?.disconnect();
    state.mutationObserver?.disconnect();
    window.removeEventListener("resize", refreshCanvasMetrics);
    window.removeEventListener("scroll", refreshCanvasMetrics);
    document.removeEventListener("visibilitychange", refreshCanvasMetrics);
    window.removeEventListener("keydown", onKeyDown, true);
    host.remove();
  }

  function onKeyDown(event) {
    if (event.key === "Escape" && state.activePointerId !== null) {
      state.livePoints = [];
      state.lassoPath = [];
      releasePointer(state.activePointerId);
      render();
      return;
    }
    if (event.key === "Delete" || event.key === "Backspace") {
      if (deleteSelectedStrokes()) {
        event.preventDefault();
        event.stopPropagation();
      }
    }
  }

  function onPointerDown(event) {
    if (state.activeTool === TOOL_SELECT) return;
    if (!event.isPrimary || state.activePointerId !== null) return;

    state.activePointerId = event.pointerId;
    state.pointerType = event.pointerType || "unknown";
    state.pointerPressure = event.pressure || 0;
    canvas.setPointerCapture(event.pointerId);

    if (state.activeTool === TOOL_DRAW) {
      state.livePoints = [];
      state.strokeStartStamp = event.timeStamp;
      pushPointerSamples(event);
    } else {
      state.lassoPath = [];
      pushLassoSamples(event);
    }

    render();
    event.preventDefault();
    event.stopPropagation();
  }

  function onPointerMove(event) {
    if (event.pointerId !== state.activePointerId) return;
    state.pointerType = event.pointerType || state.pointerType;
    state.pointerPressure = event.pressure || 0;

    if (state.activeTool === TOOL_DRAW) {
      pushPointerSamples(event);
    } else if (state.activeTool === TOOL_LASSO) {
      pushLassoSamples(event);
    }

    render();
    event.preventDefault();
    event.stopPropagation();
  }

  async function onPointerUp(event) {
    if (event.pointerId !== state.activePointerId) return;

    if (state.activeTool === TOOL_DRAW) {
      pushPointerSamples(event);
      await commitStroke();
    } else if (state.activeTool === TOOL_LASSO) {
      pushLassoSamples(event);
      commitLassoSelection();
    }

    releasePointer(event.pointerId);
    event.preventDefault();
    event.stopPropagation();
  }

  function onPointerCancel(event) {
    if (event.pointerId !== state.activePointerId) return;
    state.livePoints = [];
    state.lassoPath = [];
    releasePointer(event.pointerId);
    render();
  }

  function releasePointer(pointerId) {
    if (pointerId == null) return;
    if (canvas.hasPointerCapture(pointerId)) {
      canvas.releasePointerCapture(pointerId);
    }
    state.activePointerId = null;
  }

  function pushPointerSamples(event) {
    const samples = getPointerSamples(event);
    for (const sample of samples) {
      state.livePoints.push(sample);
    }
  }

  function pushLassoSamples(event) {
    const samples = getPointerSamples(event);
    for (const sample of samples) {
      state.lassoPath.push({ x: sample.x, y: sample.y });
    }
  }

  function getPointerSamples(event) {
    const events =
      typeof event.getCoalescedEvents === "function"
        ? event.getCoalescedEvents()
        : [event];
    const result = events.length > 0 ? events : [event];
    return result.map((item) => samplePointerEvent(item));
  }

  function samplePointerEvent(event) {
    const pressure = normalizePressure(event);
    return {
      pressure,
      time: (event.timeStamp - state.strokeStartStamp) / 1000,
      x: event.pageX,
      y: event.pageY,
    };
  }

  function normalizePressure(event) {
    if (event.pointerType === "pen" || event.pointerType === "touch") {
      return clamp(event.pressure || 0.5, 0.05, 1);
    }
    return clamp(event.pressure || 0.5, 0.2, 1);
  }

  async function commitStroke() {
    const rawPoints = dedupeSamples(state.livePoints);
    state.livePoints = [];
    if (rawPoints.length < 2) {
      syncStatus("Stroke ignored: draw at least two samples.");
      render();
      return;
    }

    let processedPoints = rawPoints;
    try {
      processedPoints = await processStrokeWithWasm(rawPoints);
      syncStatus(
        `Processed ${rawPoints.length} input samples into ${processedPoints.length} display points via WASM.`,
      );
    } catch (error) {
      console.error(error);
      syncStatus(`WASM processing failed, kept raw stroke: ${error.message}`);
    }

    state.strokes.push({
      id: nextStrokeId++,
      points: processedPoints,
      rawPoints,
    });
    render();
  }

  async function processStrokeWithWasm(points) {
    const wasm = state.wasm;
    if (!wasm) {
      return points;
    }

    wasm.resetArena();
    const inputPtr = wasm.allocInputPoints(points.length);
    const headerPtr = wasm.allocResultHeader();
    if (!inputPtr || !headerPtr) {
      throw new Error("WASM allocation returned null.");
    }

    const inputView = new DataView(
      wasm.memory.buffer,
      inputPtr,
      points.length * wasm.inputPointSize,
    );
    for (let i = 0; i < points.length; i += 1) {
      const base = i * wasm.inputPointSize;
      const point = points[i];
      inputView.setFloat32(base + 0, point.x, true);
      inputView.setFloat32(base + 4, point.y, true);
      inputView.setFloat32(base + 8, point.pressure, true);
      inputView.setFloat32(base + 12, point.time, true);
    }

    const status = wasm.processStroke(
      inputPtr,
      points.length,
      2,
      0,
      1,
      headerPtr,
    );
    if (status !== STATUS_OK) {
      throw new Error(`WASM status ${status}`);
    }

    const headerView = new DataView(wasm.memory.buffer, headerPtr, 8);
    const outputPtr = headerView.getUint32(0, true);
    const outputLen = headerView.getUint32(4, true);
    const outputView = new DataView(
      wasm.memory.buffer,
      outputPtr,
      outputLen * wasm.outputPointSize,
    );

    const processed = [];
    for (let i = 0; i < outputLen; i += 1) {
      const base = i * wasm.outputPointSize;
      processed.push({
        pressure: outputView.getFloat32(base + 8, true),
        x: outputView.getFloat32(base + 0, true),
        y: outputView.getFloat32(base + 4, true),
      });
    }
    return processed;
  }

  function commitLassoSelection() {
    const polygon = dedupePolygon(state.lassoPath);
    state.lassoPath = [];

    if (polygon.length < 3) {
      syncStatus(
        "Lasso ignored: draw a closed area with at least three points.",
      );
      render();
      return;
    }

    const nextSelection = new Set();
    for (const stroke of state.strokes) {
      if (strokeIntersectsPolygon(stroke.points, polygon)) {
        nextSelection.add(stroke.id);
      }
    }

    state.selectedIds = nextSelection;
    syncStatus(
      `Selected ${nextSelection.size} stroke${nextSelection.size === 1 ? "" : "s"}.`,
    );
    render();
  }

  function deleteSelectedStrokes() {
    if (state.selectedIds.size === 0) {
      return false;
    }

    const before = state.strokes.length;
    state.strokes = state.strokes.filter(
      (stroke) => !state.selectedIds.has(stroke.id),
    );
    state.selectedIds.clear();
    syncStatus(`Deleted ${before - state.strokes.length} selected stroke(s).`);
    render();
    return true;
  }

  function strokeIntersectsPolygon(points, polygon) {
    if (points.some((point) => pointInPolygon(point, polygon))) {
      return true;
    }

    for (let i = 0; i + 1 < points.length; i += 1) {
      const a = points[i];
      const b = points[i + 1];
      for (let j = 0; j < polygon.length; j += 1) {
        const c = polygon[j];
        const d = polygon[(j + 1) % polygon.length];
        if (segmentsIntersect(a, b, c, d)) {
          return true;
        }
      }
    }

    return false;
  }

  function pointInPolygon(point, polygon) {
    let inside = false;
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i, i += 1) {
      const xi = polygon[i].x;
      const yi = polygon[i].y;
      const xj = polygon[j].x;
      const yj = polygon[j].y;
      const intersects =
        yi > point.y !== yj > point.y &&
        point.x <
          ((xj - xi) * (point.y - yi)) / (yj - yi || Number.EPSILON) + xi;
      if (intersects) inside = !inside;
    }
    return inside;
  }

  function segmentsIntersect(a, b, c, d) {
    const ab = ccw(a, c, d) !== ccw(b, c, d);
    const cd = ccw(a, b, c) !== ccw(a, b, d);
    return ab && cd;
  }

  function ccw(a, b, c) {
    return (c.y - a.y) * (b.x - a.x) > (b.y - a.y) * (c.x - a.x);
  }

  function dedupeSamples(points) {
    const result = [];
    for (const point of points) {
      const prev = result[result.length - 1];
      if (!prev || prev.x !== point.x || prev.y !== point.y) {
        result.push(point);
      }
    }
    return result;
  }

  function dedupePolygon(points) {
    const result = dedupeSamples(points);
    if (result.length >= 2) {
      const first = result[0];
      const last = result[result.length - 1];
      if (first.x === last.x && first.y === last.y) {
        result.pop();
      }
    }
    return result;
  }

  function render() {
    const width = canvas.width / (window.devicePixelRatio || 1);
    const height = canvas.height / (window.devicePixelRatio || 1);
    ctx.clearRect(0, 0, width, height);

    for (const stroke of state.strokes) {
      drawStroke(stroke.points, state.selectedIds.has(stroke.id));
    }

    if (state.livePoints.length > 0) {
      drawStroke(state.livePoints, false, true);
    }

    if (state.lassoPath.length > 0) {
      drawLasso(state.lassoPath);
    }

  }

  function drawStroke(points, selected, live = false) {
    if (points.length < 2) return;

    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.strokeStyle = selected ? "#0e6b57" : live ? "#b75a2a" : "#1f2a28";
    ctx.beginPath();
    ctx.moveTo(points[0].x, points[0].y);

    for (let i = 1; i < points.length; i += 1) {
      const prev = points[i - 1];
      const point = points[i];
      const midX = (prev.x + point.x) * 0.5;
      const midY = (prev.y + point.y) * 0.5;
      ctx.quadraticCurveTo(prev.x, prev.y, midX, midY);
    }

    const last = points[points.length - 1];
    ctx.lineTo(last.x, last.y);
    ctx.lineWidth = averagePressure(points) * 6 + (live ? 1.8 : 1.2);
    ctx.globalAlpha = live ? 0.82 : 0.94;
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  function drawLasso(points) {
    if (points.length < 2) return;
    ctx.save();
    ctx.setLineDash([10, 8]);
    ctx.lineWidth = 1.4;
    ctx.strokeStyle = "#b75a2a";
    ctx.fillStyle = "rgba(183, 90, 42, 0.08)";
    ctx.beginPath();
    ctx.moveTo(points[0].x, points[0].y);
    for (let i = 1; i < points.length; i += 1) {
      ctx.lineTo(points[i].x, points[i].y);
    }
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  function averagePressure(points) {
    let sum = 0;
    for (const point of points) {
      sum += point.pressure ?? 0.5;
    }
    return sum / points.length;
  }

  function syncStatus(message) {
    state.statusLine.textContent = message;
  }
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}
