// Generated from app.ts. Do not edit directly.
const summaryCache = new Map();
let currentWindow = '24h';
const elements = {
  running: document.getElementById('status-running'),
  idle: document.getElementById('status-idle'),
  total: document.getElementById('status-total'),
  utilization: document.getElementById('status-utilization'),
  updatedAt: document.getElementById('updated-at'),
  kpiUtilization: document.getElementById('kpi-utilization'),
  kpiResponse: document.getElementById('kpi-response'),
  kpiIdle: document.getElementById('kpi-idle'),
  kpiThroughput: document.getElementById('kpi-throughput'),
  kpiBottleneck: document.getElementById('kpi-bottleneck'),
  detailRework: document.getElementById('detail-rework'),
  detailFragmentation: document.getElementById('detail-fragmentation'),
  detailLongtail: document.getElementById('detail-longtail'),
  detailCompleted: document.getElementById('detail-completed'),
  detailSupply: document.getElementById('detail-supply'),
  detailResponses: document.getElementById('detail-responses'),
  utilizationChart: document.getElementById('utilization-chart'),
  responseChart: document.getElementById('response-chart')
};
const segments = Array.from(document.querySelectorAll('.segment'));
segments.forEach((segment) => {
  segment.addEventListener('click', () => {
    const windowKey = segment.dataset.window;
    if (!windowKey || windowKey === currentWindow) {
      return;
    }
    setActiveWindow(windowKey);
  });
});
function setActiveWindow(windowKey) {
  currentWindow = windowKey;
  segments.forEach((segment) => {
    const isActive = segment.dataset.window === windowKey;
    segment.classList.toggle('is-active', isActive);
    segment.setAttribute('aria-selected', isActive ? 'true' : 'false');
  });
  render();
}
function formatPercent(value) {
  if (value === null || Number.isNaN(value)) {
    return '—';
  }
  return `${(value * 100).toFixed(1)}%`;
}
function formatDuration(seconds) {
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
function formatNumber(value, digits = 1) {
  if (value === null || Number.isNaN(value)) {
    return '—';
  }
  return value.toFixed(digits);
}
async function fetchSummary() {
  if (summaryCache.has('summary')) {
    return summaryCache.get('summary');
  }
  const response = await fetch('/api/summary');
  if (!response.ok) {
    throw new Error('Failed to load summary');
  }
  const data = await response.json();
  summaryCache.set('summary', data);
  setTimeout(() => summaryCache.delete('summary'), 4000);
  return data;
}
async function fetchTimeseries(windowKey) {
  const stepSeconds = windowKey === '7d' ? 300 : 60;
  const response = await fetch(`/api/timeseries?window=${encodeURIComponent(windowKey)}&step=${stepSeconds}`);
  if (!response.ok) {
    throw new Error('Failed to load timeseries');
  }
  return response.json();
}
function updateStatus(summary) {
  const current = summary.current;
  elements.running.textContent = String(current.running ?? '—');
  elements.idle.textContent = String(current.idle ?? '—');
  elements.total.textContent = String(current.total ?? '—');
  elements.utilization.textContent = formatPercent(current.utilization);
  elements.updatedAt.textContent = `Updated ${new Date(summary.generatedAt).toLocaleTimeString()}`;
}
function updateKPIs(metrics) {
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
function drawUtilizationChart(points) {
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
function drawResponseChart(histogram) {
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
function drawEmpty(ctx, width, height, label) {
  ctx.fillStyle = '#5a5751';
  ctx.font = '14px "Avenir Next", "Gill Sans", "Helvetica Neue", sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText(label, width / 2, height / 2);
  ctx.textAlign = 'left';
}
async function render() {
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
