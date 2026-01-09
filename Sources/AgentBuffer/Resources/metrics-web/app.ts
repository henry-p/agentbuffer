interface MetricsRuntime {
  median: number | null;
  p90: number | null;
}

interface MetricsHistogram {
  buckets: number[];
  counts: number[];
}

interface MetricsWindow {
  windowStart: number;
  windowEnd: number;
  activeUtilization: number;
  idleOverThreshold: number;
  idleOverThresholdMinutes: number;
  throughputPerHour: number;
  taskSupplyRate: number;
  tasksCompleted: number;
  assignments: number;
  responseSamples: number;
  runtime: MetricsRuntime;
  responseTime: MetricsRuntime;
  responseHistogram: MetricsHistogram;
  bottleneckIndex: number | null;
  reworkRate: number | null;
  fragmentation: number | null;
  longTailRuntime: number | null;
}

interface MetricsSummary {
  generatedAt: string;
  current: {
    running: number;
    idle: number;
    total: number;
    utilization: number;
  };
  windows: Record<string, MetricsWindow>;
}

interface TimeseriesPoint {
  t: number;
  running: number;
  total: number;
  utilization: number;
}

interface TimeseriesResponse {
  window: string;
  windowStart: number;
  windowEnd: number;
  stepSeconds: number;
  points: TimeseriesPoint[];
}

interface LiveSnapshot {
  type: 'snapshot';
  summary: MetricsSummary;
  timeseries: TimeseriesResponse;
}

const summaryCache = new Map<string, MetricsSummary>();
const timeseriesCache = new Map<string, TimeseriesResponse>();
let currentWindow = '24h';
let latestSummary: MetricsSummary | null = null;
let liveSocket: WebSocket | null = null;
let reconnectTimer: number | null = null;
let reconnectAttempts = 0;
let pollingTimer: number | null = null;

const elements = {
  running: document.getElementById('status-running') as HTMLElement,
  idle: document.getElementById('status-idle') as HTMLElement,
  total: document.getElementById('status-total') as HTMLElement,
  utilization: document.getElementById('status-utilization') as HTMLElement,
  updatedAt: document.getElementById('updated-at') as HTMLElement,
  kpiUtilization: document.getElementById('kpi-utilization') as HTMLElement,
  kpiResponse: document.getElementById('kpi-response') as HTMLElement,
  kpiIdle: document.getElementById('kpi-idle') as HTMLElement,
  kpiThroughput: document.getElementById('kpi-throughput') as HTMLElement,
  kpiBottleneck: document.getElementById('kpi-bottleneck') as HTMLElement,
  detailRework: document.getElementById('detail-rework') as HTMLElement,
  detailFragmentation: document.getElementById('detail-fragmentation') as HTMLElement,
  detailLongtail: document.getElementById('detail-longtail') as HTMLElement,
  detailCompleted: document.getElementById('detail-completed') as HTMLElement,
  detailSupply: document.getElementById('detail-supply') as HTMLElement,
  detailResponses: document.getElementById('detail-responses') as HTMLElement,
  utilizationChart: document.getElementById('utilization-chart') as HTMLCanvasElement,
  responseChart: document.getElementById('response-chart') as HTMLCanvasElement
};

const segments = Array.from(document.querySelectorAll<HTMLButtonElement>('.segment'));
segments.forEach((segment) => {
  segment.addEventListener('click', () => {
    const windowKey = segment.dataset.window;
    if (!windowKey || windowKey === currentWindow) {
      return;
    }
    setActiveWindow(windowKey);
  });
});

function setActiveWindow(windowKey: string): void {
  currentWindow = windowKey;
  segments.forEach((segment) => {
    const isActive = segment.dataset.window === windowKey;
    segment.classList.toggle('is-active', isActive);
    segment.setAttribute('aria-selected', isActive ? 'true' : 'false');
  });
  refreshFromCache();
  if (liveSocket && liveSocket.readyState === WebSocket.OPEN) {
    sendWindowSelection();
  } else {
    render();
  }
}

function formatPercent(value: number | null): string {
  if (value === null || Number.isNaN(value)) {
    return '—';
  }
  return `${(value * 100).toFixed(1)}%`;
}

function formatDuration(seconds: number | null): string {
  if (seconds === null || Number.isNaN(seconds)) {
    return '—';
  }
  const mins = Math.round(seconds / 60);
  if (mins < 60) {
    return `${mins}m`;
  }
  const hours = Math.floor(mins / 60);
  const rem = mins % 60;
  return `${hours}h ${rem}m`;
}

function formatNumber(value: number | null, digits = 1): string {
  if (value === null || Number.isNaN(value)) {
    return '—';
  }
  return value.toFixed(digits);
}

function applySummary(summary: MetricsSummary): void {
  latestSummary = summary;
  updateStatus(summary);
  const metrics = summary.windows[currentWindow];
  if (metrics) {
    updateKPIs(metrics);
  }
  drawResponseChart(metrics ? metrics.responseHistogram : null);
}

function applyTimeseries(series: TimeseriesResponse): void {
  timeseriesCache.set(series.window, series);
  if (series.window === currentWindow) {
    drawUtilizationChart(series.points || []);
  }
}

function applySnapshot(snapshot: LiveSnapshot): void {
  applySummary(snapshot.summary);
  applyTimeseries(snapshot.timeseries);
}

async function fetchSummary(): Promise<MetricsSummary> {
  if (summaryCache.has('summary')) {
    return summaryCache.get('summary') as MetricsSummary;
  }
  const response = await fetch('/api/summary');
  if (!response.ok) {
    throw new Error('Failed to load summary');
  }
  const data = (await response.json()) as MetricsSummary;
  summaryCache.set('summary', data);
  setTimeout(() => summaryCache.delete('summary'), 4000);
  return data;
}

async function fetchTimeseries(windowKey: string): Promise<TimeseriesResponse> {
  const stepSeconds = windowKey === '7d' ? 300 : 60;
  const response = await fetch(`/api/timeseries?window=${encodeURIComponent(windowKey)}&step=${stepSeconds}`);
  if (!response.ok) {
    throw new Error('Failed to load timeseries');
  }
  return response.json();
}

function updateStatus(summary: MetricsSummary): void {
  const current = summary.current;
  elements.running.textContent = String(current.running ?? '—');
  elements.idle.textContent = String(current.idle ?? '—');
  elements.total.textContent = String(current.total ?? '—');
  elements.utilization.textContent = formatPercent(current.utilization);
  elements.updatedAt.textContent = `Updated ${new Date(summary.generatedAt).toLocaleTimeString()}`;
}

function updateKPIs(metrics: MetricsWindow): void {
  elements.kpiUtilization.textContent = formatPercent(metrics.activeUtilization);
  elements.kpiResponse.textContent = `${formatDuration(metrics.responseTime.median)} / ${formatDuration(metrics.responseTime.p90)}`;
  elements.kpiIdle.textContent = `${formatPercent(metrics.idleOverThreshold)} · ${metrics.idleOverThresholdMinutes}m`;
  elements.kpiThroughput.textContent = `${formatNumber(metrics.throughputPerHour, 2)} / hr`;
  elements.kpiBottleneck.textContent = metrics.bottleneckIndex === null
    ? '—'
    : formatNumber(metrics.bottleneckIndex, 2);

  elements.detailRework.textContent = metrics.reworkRate === null ? '—' : formatPercent(metrics.reworkRate);
  elements.detailFragmentation.textContent = metrics.fragmentation === null ? '—' : formatNumber(metrics.fragmentation, 2);
  elements.detailLongtail.textContent = formatDuration(metrics.longTailRuntime);
  elements.detailCompleted.textContent = String(metrics.tasksCompleted ?? '—');
  elements.detailSupply.textContent = `${formatNumber(metrics.taskSupplyRate, 2)} / hr`;
  elements.detailResponses.textContent = String(metrics.responseSamples ?? '—');
}

function drawUtilizationChart(points: TimeseriesPoint[]): void {
  const canvas = elements.utilizationChart;
  const ctx = canvas.getContext('2d');
  if (!ctx) {
    return;
  }
  const { width, height } = canvas;
  ctx.clearRect(0, 0, width, height);

  if (points.length === 0) {
    drawEmpty(ctx, width, height, 'No utilization samples');
    return;
  }

  ctx.lineWidth = 2;
  ctx.strokeStyle = '#d67b1d';
  ctx.fillStyle = 'rgba(214, 123, 29, 0.15)';

  ctx.beginPath();
  points.forEach((point, index) => {
    const x = (index / (points.length - 1)) * (width - 24) + 12;
    const y = height - 16 - point.utilization * (height - 32);
    if (index === 0) {
      ctx.moveTo(x, y);
    } else {
      ctx.lineTo(x, y);
    }
  });
  ctx.stroke();

  ctx.lineTo(width - 12, height - 12);
  ctx.lineTo(12, height - 12);
  ctx.closePath();
  ctx.fill();
}

function drawResponseChart(histogram: MetricsHistogram | null): void {
  const canvas = elements.responseChart;
  const ctx = canvas.getContext('2d');
  if (!ctx) {
    return;
  }
  const { width, height } = canvas;
  ctx.clearRect(0, 0, width, height);

  if (!histogram || histogram.counts.length === 0) {
    drawEmpty(ctx, width, height, 'No response samples');
    return;
  }

  const counts = histogram.counts;
  const maxCount = Math.max(...counts, 1);
  const barWidth = (width - 40) / counts.length;

  ctx.fillStyle = 'rgba(28, 124, 126, 0.45)';
  counts.forEach((count, index) => {
    const barHeight = (count / maxCount) * (height - 40);
    const x = 20 + index * barWidth;
    const y = height - 20 - barHeight;
    ctx.fillRect(x, y, barWidth - 6, barHeight);
  });

  ctx.fillStyle = '#5a5751';
  ctx.font = '12px "Avenir Next", "Gill Sans", "Helvetica Neue", sans-serif';
  ctx.fillText('Minutes to respond', 20, 18);
}

function drawEmpty(ctx: CanvasRenderingContext2D, width: number, height: number, label: string): void {
  ctx.fillStyle = '#5a5751';
  ctx.font = '14px "Avenir Next", "Gill Sans", "Helvetica Neue", sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText(label, width / 2, height / 2);
  ctx.textAlign = 'left';
}

async function render(): Promise<void> {
  try {
    const summary = await fetchSummary();
    applySummary(summary);
    const series = await fetchTimeseries(currentWindow);
    applyTimeseries(series);
  } catch (err) {
    console.error(err);
  }
}

function startPolling(): void {
  if (pollingTimer !== null) {
    return;
  }
  render();
  pollingTimer = window.setInterval(render, 15000);
}

function stopPolling(): void {
  if (pollingTimer === null) {
    return;
  }
  window.clearInterval(pollingTimer);
  pollingTimer = null;
}

function scheduleReconnect(): void {
  if (reconnectTimer !== null) {
    return;
  }
  reconnectAttempts = Math.min(reconnectAttempts + 1, 6);
  const delay = Math.min(30000, 1000 * 2 ** reconnectAttempts);
  reconnectTimer = window.setTimeout(() => {
    reconnectTimer = null;
    connectLive();
  }, delay);
}

function sendWindowSelection(): void {
  if (!liveSocket || liveSocket.readyState !== WebSocket.OPEN) {
    return;
  }
  liveSocket.send(JSON.stringify({ type: 'window', window: currentWindow }));
}

function refreshFromCache(): void {
  if (latestSummary) {
    applySummary(latestSummary);
  }
  const cached = timeseriesCache.get(currentWindow);
  if (cached) {
    applyTimeseries(cached);
  }
}

function connectLive(): void {
  if (liveSocket && (liveSocket.readyState === WebSocket.OPEN || liveSocket.readyState === WebSocket.CONNECTING)) {
    return;
  }
  const scheme = window.location.protocol === 'https:' ? 'wss' : 'ws';
  const socket = new WebSocket(`${scheme}://${window.location.host}/api/live`);
  liveSocket = socket;

  socket.addEventListener('open', () => {
    reconnectAttempts = 0;
    stopPolling();
    sendWindowSelection();
  });

  socket.addEventListener('message', (event) => {
    try {
      const payload = JSON.parse(event.data) as LiveSnapshot;
      if (payload?.type === 'snapshot') {
        applySnapshot(payload);
      }
    } catch (err) {
      console.error(err);
    }
  });

  socket.addEventListener('close', () => {
    liveSocket = null;
    startPolling();
    scheduleReconnect();
  });

  socket.addEventListener('error', () => {
    socket.close();
  });
}

startPolling();
connectLive();
