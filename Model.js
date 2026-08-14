// Pure JS helpers for the cpu-ram plugin: memory formatting, top-app
// aggregation, and safe accessors over the bar's polled snapshot. No Qt
// imports here so the functions stay testable in isolation.

function clamp(n, lo, hi) {
  n = Number(n)
  if (!isFinite(n)) return lo
  return Math.max(lo, Math.min(hi, n))
}

// Compact human memory: "1.2 GB" over a gigabyte, "790 MB" over a
// megabyte, otherwise plain kilobytes.
function fmtMemory(kb) {
  kb = Math.max(0, Number(kb) || 0)
  if (kb >= 1024 * 1024) {
    var g = (kb / 1024 / 1024).toFixed(1)
    return g.replace(/\.0$/, "") + " GB"
  }
  if (kb >= 1024) return Math.round(kb / 1024) + " MB"
  return Math.max(1, Math.round(kb)) + " KB"
}

function percentOf(used, total) {
  total = Number(total) || 0
  if (total <= 0) return 0
  return clamp(Math.round(100 * (Number(used) || 0) / total), 0, 100)
}

// Used/total percent for a top-level payload section ("ram", "swap").
function pctFor(stats, key) {
  var o = stats && stats[key]
  if (!o) return 0
  return percentOf(o.used_kb, o.total_kb)
}

function cpuPercent(stats) {
  return clamp(stats && stats.cpu && stats.cpu.percent, 0, 100)
}

// "56°C" from k10temp Tctl; an em dash when the machine reports none.
function cpuTemp(stats) {
  var t = Number(stats && stats.cpu && stats.cpu.temp) || 0
  if (t <= 0) return "\u2014"
  return t.toFixed(1).replace(/\.0$/, "") + "\u00b0C"
}

// Load average as "2.1 · 1.3 · 1.0", or empty when there's no data.
function loadLabel(stats) {
  var load = stats && stats.cpu && stats.cpu.load
  if (!load || !load.length) return ""
  var parts = []
  for (var i = 0; i < load.length; i++) {
    parts.push(Number(load[i]).toFixed(1))
  }
  return parts.join(" \u00b7 ")
}

// Top memory consumers for the panel: [{ name, label, pct }], most-first.
// Bars are scaled to the largest process in the list so they read against
// each other rather than against total RAM.
function topApps(stats) {
  var list = stats && stats.topapps ? stats.topapps : []
  var max = 0
  for (var i = 0; i < list.length; i++) {
    max = Math.max(max, Number(list[i].rss_kb) || 0)
  }
  var out = []
  for (var j = 0; j < list.length; j++) {
    var rss = Number(list[j].rss_kb) || 0
    out.push({
      name: String(list[j].name || "\u2014"),
      label: fmtMemory(rss),
      pct: max > 0 ? Math.round(100 * rss / max) : 0
    })
  }
  return out
}

// Number field from a payload section, e.g. value(stats, "ram", "used_kb", 0).
function value(stats, key, field, fallback) {
  var o = stats && stats[key]
  return o && o[field] !== undefined ? Number(o[field]) : fallback
}
