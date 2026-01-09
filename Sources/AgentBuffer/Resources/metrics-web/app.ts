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

const summaryCache = new Map<string, MetricsSummary>();
let currentWindow = '24h';

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
  render();
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
    updateStatus(summary);
    const metrics = summary.windows[currentWindow];
    if (metrics) {
      updateKPIs(metrics);
    }
    const series = await fetchTimeseries(currentWindow);
    drawUtilizationChart(series.points || []);
    drawResponseChart(metrics ? metrics.responseHistogram : null);
  } catch (err) {
    console.error(err);
  }
}

render();
setInterval(render, 15000);
